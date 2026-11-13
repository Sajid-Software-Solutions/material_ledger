// People records: the tracker reader and exporter, and the People home,
// person record, person form, document dialog and import dialog against a
// fake server. Every name and number here is fictional.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/people_records/presentation/people_centre_screen.dart';
import 'package:material_ledger/features/people_records/presentation/person_form_screen.dart';
import 'package:material_ledger/features/people_records/presentation/person_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_people.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_workbook_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_people_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_people_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_people_workbook.dart';
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
  workforce: true,
  workforceAttendanceV2: true,
  peopleRecords: true,
);

const _company = 'Example Cooling Services LLC';
const _workerId = '7b000000-0000-4000-8000-000000000001';

Map<String, Object?> _doc(
  String id,
  String kind, {
  String status = 'ok',
  String? number,
  String? expiry,
  int? days,
  String? sites,
  bool current = true,
  String? endedReason,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'record_version': 1,
  'number': number,
  'expiry_date': expiry,
  'days_left': days,
  'sites': sites,
  'is_current': current,
  if (!current) 'ended_at': '2026-10-01T08:00:00Z',
  'ended_reason': endedReason,
  'updated_at': '2026-10-01T08:00:00Z',
  'updated_by': 'Local PR',
};

Map<String, Object?> _person({
  String id = _workerId,
  String name = 'RAVI TEST KUMAR',
  String number = 'WR-000101',
  String category = 'labour',
  bool canManage = true,
  bool detail = true,
}) => {
  'id': id,
  'number': number,
  'name': name,
  'company': _company,
  'profession': 'Technician',
  'status': 'active',
  'category': category,
  'record_version': 2,
  'joining_date': '2026-01-01',
  'date_of_birth': '1990-05-01',
  'unified_number': '100000001',
  'has_profile': true,
  'attention': 'expired',
  'documents': [
    _doc(
      'd-visa',
      'visa',
      status: 'expired',
      number: 'V-TEST-01',
      expiry: '2026-11-01',
      days: -12,
    ),
    _doc(
      'd-passport',
      'passport',
      number: 'TP1000001',
      expiry: '2030-05-01',
      days: 1265,
    ),
    _doc(
      'd-eid',
      'emirates_id',
      status: 'expiring',
      number: '784-1990-0000001-1',
      expiry: '2026-12-20',
      days: 37,
    ),
    _doc(
      'd-cicpa',
      'cicpa_pass',
      number: 'CP-0001',
      expiry: '2027-01-31',
      days: 79,
      sites: 'Ruwais, Habshan',
    ),
  ],
  'next_expiry': {
    'kind': 'emirates_id',
    'expiry_date': '2026-12-20',
    'days_left': 37,
  },
  'crew': {'id': 'crew-1', 'name': 'Crew Alpha'},
  if (detail) ...{
    'previous_documents': [
      _doc(
        'd-visa-old',
        'visa',
        status: 'expired',
        number: 'V-TEST-00',
        expiry: '2024-11-01',
        days: -742,
        current: false,
        endedReason: 'renewed',
      ),
    ],
    'history': [
      {
        'entity': 'person',
        'action': 'imported',
        'actor_name': 'Local PR',
        'actor_role': 'pr',
        'changed': <String>[],
        'at': '2026-11-10T08:00:00Z',
      },
      {
        'entity': 'document',
        'action': 'renewed',
        'kind': 'visa',
        'actor_name': 'Local PR',
        'actor_role': 'pr',
        'changed': ['expiry_date'],
        'at': '2026-11-11T09:30:00Z',
      },
    ],
  },
  'can_manage': canManage,
};

Map<String, Object?> _overview({bool canManage = true}) => {
  'today': '2026-11-13',
  'can_manage': canManage,
  'counts': {
    'total': 3,
    'staff': 1,
    'labour': 2,
    'expired': 1,
    'expiring': 1,
    'no_visa': 0,
  },
  'by_kind': {
    'visa': {'expired': 1, 'expiring': 0, 'total': 3},
    'emirates_id': {'expired': 0, 'expiring': 1, 'total': 3},
    'cicpa_pass': {'expired': 0, 'expiring': 0, 'total': 2},
  },
  'companies': [
    {'name': _company, 'count': 2},
    {'name': 'Example Contracting WLL', 'count': 1},
  ],
  'attention': [
    {
      'document': _doc(
        'd-visa',
        'visa',
        status: 'expired',
        number: 'V-TEST-01',
        expiry: '2026-11-01',
        days: -12,
      ),
      'person': {
        'id': _workerId,
        'number': 'WR-000101',
        'name': 'RAVI TEST KUMAR',
        'company': _company,
        'category': 'labour',
      },
    },
    {
      'document': _doc(
        'd-eid',
        'emirates_id',
        status: 'expiring',
        number: '784-1990-0000001-1',
        expiry: '2026-12-20',
        days: 37,
      ),
      'person': {
        'id': _workerId,
        'number': 'WR-000101',
        'name': 'RAVI TEST KUMAR',
        'company': _company,
        'category': 'labour',
      },
    },
  ],
};

Map<String, Object?> _page(List<Map<String, Object?>> rows) => {
  'today': '2026-11-13',
  'total': rows.length,
  'offset': 0,
  'limit': 25,
  'rows': rows,
};

final class _FakeRpc implements YorksV1PeopleRpcClient {
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

_FakeRpc _server({bool canManage = true}) => _FakeRpc({
  'v1_people_overview': (_) => _overview(canManage: canManage),
  'v1_people_list': (parameters) {
    final query = parameters['p_query'] as Map<String, Object?>;
    return _page([
      if (query['category'] != 'staff') _person(detail: false),
      if (query['category'] != 'labour')
        _person(
          id: '7b000000-0000-4000-8000-000000000002',
          name: 'SAMI TEST ONE',
          number: 'WR-000102',
          category: 'staff',
          detail: false,
        ),
    ]);
  },
  'v1_people_get': (_) => _person(canManage: canManage),
  'v1_people_save_person': (_) => _person(),
  'v1_people_save_document': (_) => _person(),
  'v1_people_end_document': (_) => _person(),
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
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1People,
        builder: (_, state) =>
            PeopleCentreScreen(initialView: state.uri.queryParameters['view']),
      ),
      GoRoute(
        path: RoutePaths.yorksV1PeopleNew,
        builder: (_, _) => const PeoplePersonFormScreen(),
      ),
      GoRoute(
        path: RoutePaths.yorksV1PeoplePerson,
        builder: (_, state) =>
            PeoplePersonScreen(workerId: state.pathParameters['workerId']!),
      ),
      GoRoute(
        path: RoutePaths.yorksV1PeopleEdit,
        builder: (_, state) =>
            PeoplePersonFormScreen(workerId: state.pathParameters['workerId']),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceAttendance,
        builder: (_, state) => Scaffold(
          body: Text('attendance ${state.uri.queryParameters['crew']}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('actor-pr'),
        yorksV1FeatureFlagsProvider.overrideWithValue(_flags),
        yorksV1PeopleRepositoryProvider.overrideWithValue(
          YorksV1PeopleRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            client: rpc,
          ),
        ),
        yorksV1BoqWorkbookFileServiceProvider.overrideWithValue(
          files ?? _Files(),
        ),
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

/// A small Staff Documents & Passes tracker in the owner's layout.
YorksV1BoqParsedWorkbook _tracker() => YorksV1BoqParsedWorkbook(
  fileName: 'Staff Documents Passes Tracking.xlsx',
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
          'ILOE Expiry',
          'Emirates ID',
          'Emirates ID Expiry',
        ],
        [
          _company,
          'RAVI TEST KUMAR',
          'Technician',
          '46418',
          'TP1000001',
          '2030-05-01',
          '46418',
          '31-Jan-2027',
          '7.84199012345678E14',
          '31/01/2027',
        ],
        [
          _company,
          'SAMI TEST ONE',
          'Site Engineer',
          '20261231',
          'TP1000002',
          '',
          '',
          '',
          '',
          '',
        ],
        [_company, 'GROUP MEDICAL INSURANCE', '', '46418'],
      ],
    ),
    YorksV1BoqWorkbookSheet(
      name: 'CICPA & CMW',
      rows: [
        [
          'EXPIRY',
          'NAME',
          'CNI NO',
          'SITES',
          'EXPIRY',
          'NAME',
          'CMW NO',
          'SITES',
        ],
        ['YORKS'],
        ['20270131', 'RAVI TEST KUMAR', '12345', 'Ruwais', '', '', '', ''],
        [
          '',
          'SAMI TEST ONE',
          '',
          '',
          '46418',
          'SAMI TEST ONE',
          'CMW-1',
          'Al Dhafra',
        ],
        ['20261201', 'NADIR TEST NEW', '777', '', '', '', '', ''],
        ['20261201', 'TRUCK 1234', '888', '', '', '', '', ''],
      ],
    ),
  ],
);

void main() {
  group('Tracker reader', () {
    test('reads dates, long numbers and blanks', () {
      expect(peopleParseDate('46418'), '2027-01-31');
      expect(peopleParseDate('20270131'), '2027-01-31');
      expect(peopleParseDate('31/01/2027'), '2027-01-31');
      expect(peopleParseDate('31-Jan-2027'), '2027-01-31');
      expect(peopleParseDate('2027-01-31'), '2027-01-31');
      expect(peopleParseDate(''), '');
      expect(peopleParseDate('soon'), isNull);
      expect(peopleNumberText('7.84199012345678E14'), '784199012345678');
      expect(peopleNumberText('12345.0'), '12345');
    });

    test('reads people, documents and gate passes', () {
      final read = peopleReadTracker(_tracker());
      expect(read.staffSheetFound, isTrue);
      expect(read.passSheetFound, isTrue);
      expect(read.issueCount, 0);
      expect(
        [for (final person in read.people) person.fullName],
        ['RAVI TEST KUMAR', 'SAMI TEST ONE', 'NADIR TEST NEW'],
      );
      expect(read.skippedRows.single.text, 'GROUP MEDICAL INSURANCE');
      expect(read.vehicles.single.name, 'TRUCK 1234');

      final ravi = read.people[0];
      expect(ravi.category, PeopleCategory.labour);
      String? expiry(PeopleTrackerPerson person, PeopleDocumentKind kind) =>
          person.documents.firstWhere((d) => d.kind == kind).expiryDate;
      expect(expiry(ravi, PeopleDocumentKind.visa), '2027-01-31');
      expect(expiry(ravi, PeopleDocumentKind.iloe), '2027-01-31');
      expect(
        ravi.documents
            .firstWhere((d) => d.kind == PeopleDocumentKind.emiratesId)
            .number,
        '784199012345678',
      );
      final pass = ravi.documents.firstWhere(
        (d) => d.kind == PeopleDocumentKind.cicpaPass,
      );
      expect(pass.number, '12345');
      expect(pass.expiryDate, '2027-01-31');
      expect(pass.sites, 'Ruwais');

      final sami = read.people[1];
      expect(sami.category, PeopleCategory.staff);
      // A name-only CICPA cell records nothing; the CMW pass is joined.
      expect(sami.documents.where((d) => d.kind.isPass).map((d) => d.kind), [
        PeopleDocumentKind.cmwPass,
      ]);

      final added = read.people[2];
      expect(added.origin, PeopleTrackerOrigin.passSheet);
      expect(added.company, isNotEmpty);
      expect(added.sourceNote, 'Added from the gate pass list');

      final payload = read.toPayload(
        sourceName: 'tracker.xlsx',
        joiningDate: '2026-11-13',
      );
      expect((payload['people'] as List).length, 3);
    });

    test('an export reads back into the same people and documents', () {
      final people = [
        PeoplePerson.fromJson(_person()),
        PeoplePerson.fromJson(
          _person(
            id: '7b000000-0000-4000-8000-000000000002',
            name: 'SAMI TEST ONE',
            number: 'WR-000102',
            category: 'staff',
          ),
        ),
      ];
      final bytes = peopleEncodeWorkbook(
        peopleExportSheets(people, today: '2026-11-13'),
      );
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: bytes,
        fileName: 'People.xlsx',
      );
      expect(workbook.sheets.map((sheet) => sheet.name), [
        'Staff Documents',
        'Gate Passes',
        'Needs Attention',
      ]);
      final read = peopleReadTracker(workbook);
      expect(read.issueCount, 0);
      final byName = {
        for (final person in read.people) person.fullName: person,
      };
      expect(
        byName.keys,
        unorderedEquals(['RAVI TEST KUMAR', 'SAMI TEST ONE']),
      );
      expect(byName['SAMI TEST ONE']!.category, PeopleCategory.staff);
      final ravi = byName['RAVI TEST KUMAR']!;
      expect(ravi.category, PeopleCategory.labour);
      final kinds = {for (final d in ravi.documents) d.kind: d};
      expect(kinds[PeopleDocumentKind.visa]?.expiryDate, '2026-11-01');
      expect(kinds[PeopleDocumentKind.passport]?.number, 'TP1000001');
      expect(
        kinds[PeopleDocumentKind.emiratesId]?.number,
        '784-1990-0000001-1',
      );
      expect(kinds[PeopleDocumentKind.cicpaPass]?.sites, 'Ruwais, Habshan');
    });
  });

  group('People screens', () {
    setUpAll(loadAccountsV2GoldenFonts);

    for (final (size, name) in [
      (const Size(1440, 1000), 'desktop'),
      (const Size(360, 800), 'phone'),
    ]) {
      testWidgets('home shows what needs attention ($name)', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), RoutePaths.yorksV1People);
        expect(find.byKey(const ValueKey('people-centre')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('people-attention-d-visa')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/people_records_${name}_home.png'),
        );
      });

      testWidgets('person record ($name)', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), RoutePaths.yorksV1People);
        await tester.pumpAndSettle();
        final router = GoRouter.of(
          tester.element(find.byKey(const ValueKey('people-centre'))),
        );
        router.go('/yorks/people/$_workerId');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('people-person')), findsOneWidget);
        expect(find.text('RAVI TEST KUMAR'), findsWidgets);
        expect(find.text('Visa expired on 1 Nov 2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/people_records_${name}_person.png'),
        );
      });

      testWidgets('person form ($name)', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), RoutePaths.yorksV1PeopleNew);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/people_records_${name}_form.png'),
        );
      });
    }

    testWidgets('the staff register opens a person', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '${RoutePaths.yorksV1People}?view=staff');
      expect(rpc.callsTo('v1_people_list').last['p_query'], {
        'category': 'staff',
        'sort': 'name',
        'limit': 25,
        'offset': 0,
      });
      await tester.tap(
        find.byKey(
          const ValueKey('people-row-7b000000-0000-4000-8000-000000000002'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('people-person')), findsOneWidget);
    });

    testWidgets('export saves a workbook of everyone', (tester) async {
      _size(tester, const Size(1440, 1000));
      final files = _Files();
      await _pump(tester, _server(), RoutePaths.yorksV1People, files: files);
      await tester.tap(find.byKey(const ValueKey('people-export')));
      await tester.pumpAndSettle();
      expect(files.saved, isNotNull);
      expect(files.savedName, endsWith('.xlsx'));
      final read = peopleReadTracker(
        const YorksV1BoqWorkbookCodec().decode(
          bytes: files.saved!,
          fileName: files.savedName!,
        ),
      );
      expect(read.people.length, 2);
    });

    testWidgets('a viewer sees no edit commands', (tester) async {
      _size(tester, const Size(1440, 1000));
      await _pump(
        tester,
        _server(canManage: false),
        '/yorks/people/$_workerId',
      );
      expect(find.byKey(const ValueKey('people-person-edit')), findsNothing);
      expect(
        find.byKey(const ValueKey('people-document-renew-d-visa')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('people-document-add-passport')),
        findsNothing,
      );
    });

    testWidgets('renewing a visa sends the renewal', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/people/$_workerId');
      await tester.tap(
        find.byKey(const ValueKey('people-document-renew-d-visa')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('people-doc-renew-hint')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('people-doc-number')),
        'V-TEST-02',
      );
      await tester.tap(find.byKey(const ValueKey('people-doc-expiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('people-doc-save')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final call = rpc.callsTo('v1_people_save_document').single;
      expect(call['p_payload'], {
        'worker_id': _workerId,
        'document_id': 'd-visa',
        'renew': true,
        'number': 'V-TEST-02',
        'expiry_date': today,
      });
      expect(call['p_expected_version'], 1);
      expect(call['p_idempotency_key'], isNotEmpty);
      expect(find.byKey(const ValueKey('people-doc-dialog')), findsNothing);
      expect(find.text('Visa renewed'), findsOneWidget);
    });

    testWidgets('a document needs a number or an expiry', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/people/$_workerId');
      await tester.tap(
        find.byKey(const ValueKey('people-document-add-labour_card')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('people-doc-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number or an expiry date.'), findsOneWidget);
      expect(rpc.callsTo('v1_people_save_document'), isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('people-doc-number')),
        'LC-0001',
      );
      await tester.tap(find.byKey(const ValueKey('people-doc-save')));
      await tester.pumpAndSettle();
      expect(rpc.callsTo('v1_people_save_document').single['p_payload'], {
        'worker_id': _workerId,
        'kind': 'labour_card',
        'number': 'LC-0001',
      });
      expect(
        rpc.callsTo('v1_people_save_document').single['p_expected_version'],
        0,
      );
    });

    testWidgets('a second current document is refused in place', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_people_save_document'] = (_) =>
          throw const PostgrestException(
            message: 'V1_PEOPLE_DOCUMENT_EXISTS',
            code: '23505',
          );
      await _pump(tester, rpc, '/yorks/people/$_workerId');
      await tester.tap(find.byKey(const ValueKey('people-document-add-iloe')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('people-doc-number')),
        'IL-1',
      );
      await tester.tap(find.byKey(const ValueKey('people-doc-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('This person already has a current ILOE. Renew it instead.'),
        findsOneWidget,
      );
      // Everything typed is still there.
      expect(find.text('IL-1'), findsOneWidget);
    });

    testWidgets('ending a document needs a reason', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/people/$_workerId');
      await tester.tap(
        find.byKey(const ValueKey('people-document-end-d-cicpa')),
      );
      await tester.pumpAndSettle();
      expect(find.text('End CICPA pass?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await tester.pumpAndSettle();
      expect(rpc.callsTo('v1_people_end_document'), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'Handed back');
      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_people_end_document').single;
      expect(call['p_document_id'], 'd-cicpa');
      expect(call['p_reason'], 'Handed back');
      expect(call['p_expected_version'], 1);
      expect(find.text('CICPA pass ended'), findsOneWidget);
    });

    testWidgets('a new person needs a name and company, then saves', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, RoutePaths.yorksV1PeopleNew);
      await tester.tap(find.byKey(const ValueKey('people-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the full name.'), findsOneWidget);
      expect(find.text('Enter the company.'), findsOneWidget);
      expect(rpc.callsTo('v1_people_save_person'), isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('people-form-name')),
        'RAVI TEST KUMAR',
      );
      await tester.enterText(
        find.byKey(const ValueKey('people-form-company')),
        _company,
      );
      await tester.enterText(
        find.byKey(const ValueKey('people-form-profession')),
        'Technician',
      );
      await tester.tap(find.text('Staff').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('people-form-save')));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_people_save_person').single;
      expect(call['p_payload'], {
        'full_name': 'RAVI TEST KUMAR',
        'employer_company': _company,
        'category': 'staff',
        'designation': 'Technician',
      });
      expect(call['p_expected_version'], 0);
      expect(find.byKey(const ValueKey('people-person')), findsOneWidget);
    });

    testWidgets('editing keeps the version and shows a conflict', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_people_save_person'] = (_) =>
          throw const PostgrestException(
            message: 'V1_PEOPLE_VERSION_CONFLICT',
            code: '40001',
          );
      await _pump(tester, rpc, '/yorks/people/$_workerId/edit');
      expect(find.text('Edit RAVI TEST KUMAR'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('people-form-mobile')),
        '0500000000',
      );
      await tester.tap(find.byKey(const ValueKey('people-form-save')));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_people_save_person').single;
      expect(call['p_expected_version'], 2);
      expect((call['p_payload'] as Map)['worker_id'], _workerId);
      expect((call['p_payload'] as Map)['mobile_number'], '0500000000');
      expect(
        find.text('Someone else changed this. Refresh and try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('people-form-desktop')), findsOneWidget);
    });

    testWidgets('import previews, then imports once', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      Map<String, Object?> result() => {
        'counts': {
          'new': 2,
          'update': 0,
          'unchanged': 0,
          'problem': 0,
          'documents_new': 7,
          'documents_renewed': 0,
          'documents_updated': 0,
        },
        'rows': [
          {
            'row': 3,
            'name': 'RAVI TEST KUMAR',
            'company': _company,
            'category': 'labour',
            'action': 'new',
            'changes': ['visa', 'passport'],
            'problems': <String>[],
          },
          {
            'row': 4,
            'name': 'SAMI TEST ONE',
            'company': _company,
            'category': 'staff',
            'action': 'new',
            'changes': ['visa'],
            'problems': <String>[],
          },
        ],
      };
      rpc.handlers['v1_people_preview_import'] = (_) => result();
      rpc.handlers['v1_people_import'] = (_) => result();
      final people = [
        PeoplePerson.fromJson(_person()),
        PeoplePerson.fromJson(
          _person(
            id: '7b000000-0000-4000-8000-000000000002',
            name: 'SAMI TEST ONE',
            number: 'WR-000102',
            category: 'staff',
          ),
        ),
      ];
      final files = _Files(
        YorksV1BoqSelectedWorkbook(
          fileName: 'People.xlsx',
          bytes: peopleEncodeWorkbook(
            peopleExportSheets(people, today: '2026-11-13'),
          ),
        ),
      );
      await _pump(tester, rpc, RoutePaths.yorksV1People, files: files);
      await tester.tap(find.byKey(const ValueKey('people-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('people-import-choose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('people-import-rows')), findsOneWidget);
      final preview = rpc.callsTo('v1_people_preview_import').single;
      expect(((preview['p_payload'] as Map)['people'] as List).length, 2);
      expect(rpc.callsTo('v1_people_import'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('people-import-commit')));
      await tester.pumpAndSettle();
      final commit = rpc.callsTo('v1_people_import').single;
      expect(commit['p_idempotency_key'], isNotEmpty);
      expect(find.byKey(const ValueKey('people-import-dialog')), findsNothing);
    });

    testWidgets('a refused reader is told so', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_people_overview'] = (_) =>
          throw const PostgrestException(
            message: 'permission denied',
            code: '42501',
          );
      await _pump(tester, rpc, RoutePaths.yorksV1People);
      expect(
        find.text('You do not have access to people records.'),
        findsOneWidget,
      );
    });
  });
}

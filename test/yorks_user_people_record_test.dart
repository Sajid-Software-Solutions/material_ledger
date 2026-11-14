// User Management shows and links the People record of an account
// (PRODUCT_DECISIONS section 56). Fictional fixtures only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/admin/presentation/screens/user_management_screen.dart';
import 'package:material_ledger/features/admin/presentation/widgets/yorks_v1_user_management_views.dart';
import 'package:material_ledger/features/people_records/presentation/account_people_record.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_record_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_people_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_people_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';
import 'support/yorks_v1_permission_test_support.dart';

const _authUserId = '10000000-0000-4000-8000-000000000037';
const _personId = '7b000000-0000-4000-8000-000000000137';
const _otherId = '7b000000-0000-4000-8000-000000000138';
const _takenId = '7b000000-0000-4000-8000-000000000139';

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
);

Map<String, Object?> _account() => {
  'auth_user_id': _authUserId,
  'name': 'Test Engineer',
  'email': 'test.engineer@example.test',
  'role': 'site_engineer',
  'active': true,
};

Map<String, Object?> _person(
  String id,
  String number,
  String name, {
  String company = 'Example Contracting LLC',
  String position = 'Site Engineer',
  Map<String, Object?>? account,
  int version = 3,
}) => {
  'id': id,
  'number': number,
  'name': name,
  'company': company,
  'profession': position,
  'category': 'staff',
  'status': 'active',
  'record_version': version,
  'documents': <Object?>[],
  'account': account,
};

Map<String, Object?> _accountPerson({
  bool linked = false,
  bool canLink = true,
}) => {
  'account': _account(),
  'person': linked
      ? _person(
          _personId,
          'WR-000137',
          'TEST ENGINEER',
          company: 'Not recorded',
          position: 'Not recorded',
          account: _account(),
        )
      : null,
  'can_link': canLink,
};

Map<String, Object?> _suggestions() => {
  'linked_count': 18,
  'accounts': [
    {
      ..._account(),
      'suggestions': [
        {
          'worker_id': _personId,
          'number': 'WR-000137',
          'name': 'TEST ENGINEER',
          'company': 'Not recorded',
          'position': 'Not recorded',
          'category': 'staff',
        },
      ],
    },
  ],
};

Map<String, Object?> _list(Map<String, Object?> parameters) => {
  'today': '2026-11-14',
  'total': 3,
  'offset': 0,
  'limit': 30,
  'rows': [
    _person(_personId, 'WR-000137', 'TEST ENGINEER'),
    _person(_otherId, 'WR-000138', 'SECOND TEST PERSON'),
    _person(
      _takenId,
      'WR-000139',
      'THIRD TEST PERSON',
      account: {..._account(), 'name': 'Someone Else'},
    ),
  ],
};

void main() {
  setUpAll(loadAccountsV2GoldenFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('who sees the People record in User Management', () {
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
      peopleRecordsEnabled: enabled,
    );

    test('HR/PRO, Admin and the Accountant with People view', () {
      for (final role in const [
        YorksV1Role.pr,
        YorksV1Role.admin,
        YorksV1Role.accountant,
      ]) {
        expect(
          resolve(role, const [
            YorksV1CapabilityKeys.peopleRecordsView,
          ]).canViewPeopleRecords,
          isTrue,
          reason: role.claimValue,
        );
      }
    });

    test('User Management alone, or the flag off, does not show it', () {
      expect(
        resolve(
          YorksV1Role.seniorMechanicalEngineer,
          const [],
        ).canViewPeopleRecords,
        isFalse,
      );
      expect(
        resolve(YorksV1Role.admin, const [
          YorksV1CapabilityKeys.peopleRecordsView,
        ], enabled: false).canViewPeopleRecords,
        isFalse,
      );
    });
  });

  testWidgets('an account not linked yet is linked to the chosen person', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    var linked = false;
    final rpc = _FakeRpc({
      'v1_people_account_person': (_) => _accountPerson(linked: linked),
      'v1_people_link_suggestions': (_) => _suggestions(),
      'v1_people_list': _list,
      'v1_people_get': (_) => _person(_personId, 'WR-000137', 'TEST ENGINEER'),
      'v1_people_set_account': (_) {
        linked = true;
        return _person(
          _personId,
          'WR-000137',
          'TEST ENGINEER',
          account: _account(),
        );
      },
    });
    await _pump(tester, rpc);

    expect(find.text('Not linked to a person yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('user-people-record-link')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('people-link-person-dialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('Link Test Engineer to a person'), findsOneWidget);
    // The suggested person comes first, without "Not recorded".
    expect(
      find.descendant(of: dialog, matching: find.text('Name matches')),
      findsOneWidget,
    );
    expect(find.text('WR-000137 · Staff'), findsOneWidget);
    // Someone linked to another account cannot be chosen.
    expect(find.text('Linked to Someone Else'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('people-link-person-$_takenId')),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/user_people_record/picker_1440x900.png'),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('people-link-person-$_personId')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    final call = rpc.callsTo('v1_people_set_account').single;
    expect(call['p_worker_id'], _personId);
    expect(call['p_auth_user_id'], _authUserId);
    expect(call['p_expected_version'], 3);
    expect(call['p_idempotency_key'], isNotEmpty);
    expect(dialog, findsNothing);
    expect(find.text('Account linked'), findsOneWidget);
    expect(find.text('TEST ENGINEER'), findsOneWidget);
    expect(find.text('WR-000137'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('searching asks the server and narrows the list', (tester) async {
    await _setViewport(tester, const Size(1440, 900));
    final rpc = _FakeRpc({
      'v1_people_account_person': (_) => _accountPerson(),
      'v1_people_link_suggestions': (_) => _suggestions(),
      'v1_people_list': _list,
    });
    await _pump(tester, rpc);
    await tester.tap(find.byKey(const ValueKey('user-people-record-link')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('people-link-person-search')),
      'second',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final query = rpc.callsTo('v1_people_list').last['p_query']! as Map;
    expect(query['search'], 'second');
    // The suggestion does not match the search, so it is not repeated.
    expect(find.text('Name matches'), findsNothing);
  });

  testWidgets('a linked account opens the record or unlinks', (tester) async {
    await _setViewport(tester, const Size(1440, 900));
    var linked = true;
    String? opened;
    final rpc = _FakeRpc({
      'v1_people_account_person': (_) => _accountPerson(linked: linked),
      'v1_people_set_account': (_) {
        linked = false;
        return _person(_personId, 'WR-000137', 'TEST ENGINEER');
      },
    });
    await _pump(tester, rpc, onOpen: (id) => opened = id);

    expect(find.text('TEST ENGINEER'), findsOneWidget);
    // "Not recorded" stays out of the line under the name.
    expect(find.text('WR-000137'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/user_people_record/linked_1440x900.png'),
    );

    await tester.tap(find.byKey(const ValueKey('user-people-record-open')));
    expect(opened, _personId);

    await tester.tap(find.byKey(const ValueKey('user-people-record-unlink')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink'));
    await tester.pumpAndSettle();
    final call = rpc.callsTo('v1_people_set_account').single;
    expect(call['p_worker_id'], _personId);
    expect(call['p_auth_user_id'], isNull);
    expect(call['p_expected_version'], 3);
    expect(find.text('Not linked to a person yet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a People viewer who cannot link only reads', (tester) async {
    await _setViewport(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_people_account_person': (_) => _accountPerson(canLink: false),
    });
    await _pump(tester, rpc);
    expect(find.text('HR/PRO or Admin links accounts to people.'), findsOne);
    expect(find.byKey(const ValueKey('user-people-record-link')), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/user_people_record/read_only_360x800.png'),
    );
  });

  testWidgets('a failed read offers a retry', (tester) async {
    await _setViewport(tester, const Size(360, 800));
    var calls = 0;
    final rpc = _FakeRpc({
      'v1_people_account_person': (_) {
        calls++;
        if (calls == 1) throw StateError('offline');
        return _accountPerson(linked: true);
      },
    });
    await _pump(tester, rpc);
    expect(
      find.byKey(const ValueKey('user-people-record-failed')),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('TEST ENGINEER'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRpc rpc, {
  ValueChanged<String>? onOpen,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1PeopleRepositoryProvider.overrideWithValue(
          YorksV1PeopleRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            client: rpc,
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          // The section inside the user panel's own frame and scroll list.
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: SizedBox(
                  width: 560,
                  child: YorksV1EditPanelSection(
                    icon: Icons.assignment_ind_outlined,
                    title: MyRecordStrings.peopleRecord,
                    subtitle: MyRecordStrings.peopleRecordDescription,
                    language: AppLanguage.english,
                    child: AccountPeopleRecordSection(
                      appUserId: 'usr-test-engineer',
                      accountName: 'Test Engineer',
                      language: AppLanguage.english,
                      onOpenRecord: onOpen ?? (_) {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

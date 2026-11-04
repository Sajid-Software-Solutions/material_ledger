import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/admin/presentation/screens/user_management_screen.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_user_project_access.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/users_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_user_project_access_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_user_project_access_repository.dart';
import 'package:material_ledger/features/admin/presentation/widgets/yorks_v1_user_management_views.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _membership(
  String projectId,
  String ref,
  String name,
  String role, {
  String state = 'active',
}) => {
  'project_id': projectId,
  'project_ref': ref,
  'project_name': name,
  'project_state': state,
  'project_role': role,
  'effective_from': '2026-08-01T08:00:00Z',
};

Map<String, dynamic> _member(String appUserId, String name, String role) => {
  'app_user_id': appUserId,
  'display_name': name,
  'project_role': role,
  'effective_from': '2026-08-01T08:00:00Z',
  'is_active': true,
};

final _directoryJson = <String, dynamic>{
  'generated_at': '2026-11-05T08:00:00Z',
  'commercial_visible': true,
  'users': [
    {
      'app_user_id': 'usr-admin',
      'exact_role': 'admin',
      'access_basis': 'all_projects',
      'is_active': true,
      'team_eligible': false,
      'last_sign_in_at': '2026-08-02T09:00:00Z',
      'project_count': 3,
      'memberships': <Object>[],
      'commercial': {'view': true, 'manage': true},
    },
    {
      'app_user_id': 'usr-shabir',
      'exact_role': 'site_engineer',
      'access_basis': 'assigned',
      'is_active': true,
      'team_eligible': true,
      'last_sign_in_at': '2026-08-03T09:00:00Z',
      'project_count': 2,
      'memberships': [
        _membership('p1', 'YRA-313', '132/22kV Substation', 'site_engineer'),
        _membership('p2', 'YRA-401', 'Jeddah Grid Station', 'site_engineer'),
      ],
      'commercial': {'view': false, 'manage': false},
    },
    {
      'app_user_id': 'usr-praveen',
      'exact_role': 'project_engineer',
      'access_basis': 'assigned',
      'is_active': true,
      'team_eligible': true,
      'last_sign_in_at': null,
      'project_count': 2,
      'memberships': [
        _membership('p1', 'YRA-313', '132/22kV Substation', 'project_engineer'),
        _membership(
          'p3',
          'YRA-200',
          'Completed Tower',
          'project_engineer',
          state: 'completed',
        ),
      ],
      'commercial': {'view': true, 'manage': false},
    },
    {
      'app_user_id': 'usr-arnal',
      'exact_role': 'project_engineer',
      'access_basis': 'assigned',
      'is_active': true,
      'team_eligible': true,
      'last_sign_in_at': null,
      'project_count': 0,
      'memberships': <Object>[],
      'commercial': {'view': false, 'manage': false},
    },
    {
      'app_user_id': 'usr-accountant',
      'exact_role': 'accountant',
      'access_basis': 'none',
      'is_active': true,
      'team_eligible': false,
      'last_sign_in_at': null,
      'project_count': 0,
      'memberships': <Object>[],
      'commercial': {'view': false, 'manage': false},
    },
  ],
  'projects': [
    {
      'project_id': 'p1',
      'project_ref': 'YRA-313',
      'project_name': '132/22kV Substation',
      'state': 'active',
      'record_version': 4,
      'can_manage_team': true,
      'members': [
        _member('usr-praveen', 'Praveen Kumar P', 'project_engineer'),
        _member('usr-shabir', 'Shabir', 'site_engineer'),
      ],
    },
    {
      'project_id': 'p2',
      'project_ref': 'YRA-401',
      'project_name': 'Jeddah Grid Station',
      'state': 'active',
      'record_version': 2,
      'can_manage_team': true,
      'members': [_member('usr-shabir', 'Shabir', 'site_engineer')],
    },
    {
      'project_id': 'p3',
      'project_ref': 'YRA-200',
      'project_name': 'Completed Tower',
      'state': 'completed',
      'record_version': 9,
      'can_manage_team': false,
      'members': [
        _member('usr-praveen', 'Praveen Kumar P', 'project_engineer'),
      ],
    },
  ],
};

AppUser _user(String id, String name, String email, YorksV1Role role) =>
    AppUser(
      id: id,
      fullName: name,
      email: email,
      role: role == YorksV1Role.admin ? UserRole.admin : UserRole.engineer,
      createdAt: DateTime(2026, 8, 1),
      yorksV1RoleCache: role,
      yorksV1Roles: [role],
    );

final _users = [
  _user('usr-admin', 'Khaled Sleiman', 'khaled@yorks.ae', YorksV1Role.admin),
  _user('usr-shabir', 'Shabir', 'shabir@yorks.ae', YorksV1Role.siteEngineer),
  _user(
    'usr-praveen',
    'Praveen Kumar P',
    'praveen@yorks.ae',
    YorksV1Role.projectEngineer,
  ),
  _user(
    'usr-arnal',
    'Arnal Palma',
    'arnal@yorks.ae',
    YorksV1Role.projectEngineer,
  ),
  _user(
    'usr-accountant',
    'Test Accountant',
    'account@yorks.ae',
    YorksV1Role.accountant,
  ),
];

class _FakeRepository implements YorksV1UserProjectAccessRepository {
  final calls = <YorksV1SetUserProjectMembershipInput>[];
  Object? failWith;
  int loads = 0;

  @override
  Future<YorksV1UserProjectAccessDirectory> load() async {
    loads++;
    return YorksV1UserProjectAccessDirectory.fromRpcJson(_directoryJson);
  }

  @override
  Future<YorksV1SetUserProjectMembershipResult> setMembership(
    YorksV1SetUserProjectMembershipInput input,
  ) async {
    calls.add(input);
    final failure = failWith;
    if (failure != null) throw failure;
    return YorksV1SetUserProjectMembershipResult(
      changed: true,
      projectRecordVersion: input.expectedProjectVersion + 1,
    );
  }
}

Future<_FakeRepository> _pump(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({
    'app_users_v3': jsonEncode(_users.map((user) => user.toJson()).toList()),
  });
  final preferences = await SharedPreferences.getInstance();
  final repository = _FakeRepository();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1UserProvisioningEnabledProvider.overrideWithValue(true),
        yorksV1UserProjectAccessRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
      child: RepaintBoundary(
        key: const ValueKey('user-management-evidence'),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const UserManagementScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Finder _inRow(String appUserId, Finder matching) => find.descendant(
  of: find.byKey(Key('user-row-$appUserId')),
  matching: matching,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('directory decodes access basis, memberships and staffing', () {
    final directory = YorksV1UserProjectAccessDirectory.fromRpcJson(
      _directoryJson,
    );
    expect(directory.userFor('usr-shabir')!.projectCount, 2);
    expect(
      directory.userFor('usr-shabir')!.memberships.first.role,
      YorksV1ProjectMembershipRole.siteEngineer,
    );
    expect(
      directory.userFor('usr-admin')!.basis,
      YorksV1ProjectAccessBasis.allProjects,
    );
    expect(directory.userFor('usr-arnal')!.isUnassignedEngineer, isTrue);
    expect(directory.userFor('usr-accountant')!.isUnassignedEngineer, isFalse);
    expect(directory.openProjectCount, 2);
    expect(directory.staffedOpenProjectCount, 1);
    expect(directory.projectFor('p2')!.needsProjectEngineer, isTrue);
    expect(directory.projectFor('p3')!.needsProjectEngineer, isFalse);
    expect(directory.userFor('usr-praveen')!.commercial!.canView, isTrue);
  });

  test('a malformed directory is rejected rather than guessed', () {
    expect(
      () => YorksV1UserProjectAccessDirectory.fromRpcJson({
        'generated_at': '2026-11-05T08:00:00Z',
        'users': [
          {'app_user_id': 'usr-x', 'memberships': 'not-a-list'},
        ],
        'projects': <Object>[],
      }),
      throwsA(isA<YorksV1DomainException>()),
    );
  });

  test('team change failures map to the rule that refused them', () {
    YorksV1DomainException failure(String code, String message) =>
        yorksV1UserProjectAccessFailure(code, message);
    expect(
      yorksV1TeamChangeError(
        failure('55000', 'V1_ACTIVE_PROJECT_REQUIRES_PROJECT_ENGINEER'),
      ).primary,
      contains('at least one Project Engineer'),
    );
    expect(
      yorksV1TeamChangeError(
        failure(
          '42501',
          'V1_PROJECT_MEMBER_MUST_HAVE_PROJECT_OR_SITE_ENGINEER_CLAIM',
        ),
      ).primary,
      contains('Only active Project and Site Engineers'),
    );
    expect(
      yorksV1TeamChangeError(
        failure('40001', 'V1_PROJECT_VERSION_CONFLICT'),
      ).primary,
      contains('changed while you were editing'),
    );
    expect(
      yorksV1TeamChangeError(
        failure('42501', 'V1_PROJECT_TEAM_MANAGEMENT_DENIED'),
      ).primary,
      contains("can't change this project's team"),
    );
  });

  testWidgets('users show their real project access', (tester) async {
    await _pump(tester, const Size(1440, 1000));

    expect(find.text('User Management'), findsOneWidget);
    expect(_inRow('usr-shabir', find.text('2 projects')), findsOneWidget);
    expect(_inRow('usr-shabir', find.text('YRA-313')), findsOneWidget);
    expect(_inRow('usr-admin', find.text('All projects · 3')), findsOneWidget);
    expect(_inRow('usr-arnal', find.text('Not on a project')), findsOneWidget);
    expect(
      _inRow('usr-accountant', find.text('No project access')),
      findsOneWidget,
    );
    expect(_inRow('usr-admin', find.text('View & manage')), findsOneWidget);
    expect(_inRow('usr-shabir', find.text('3 Aug 2026')), findsOneWidget);
    expect(_inRow('usr-arnal', find.text('Never')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-management-metric-projects')),
        matching: find.text('1/2'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('user-management-evidence')),
      matchesGoldenFile('goldens/user_management/users_1440x1000.png'),
    );
  });

  testWidgets('the unassigned metric filters to engineers without a team', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 1000));

    await tester.tap(
      find.byKey(const ValueKey('user-management-metric-unassigned')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-row-usr-arnal')), findsOneWidget);
    expect(find.byKey(const Key('user-row-usr-shabir')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('user-management-metric-unassigned')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-row-usr-shabir')), findsOneWidget);
  });

  testWidgets('search also matches the projects a person works on', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 1000));

    await tester.enterText(
      find.byKey(const ValueKey('user-management-search')),
      'YRA-401',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-row-usr-shabir')), findsOneWidget);
    expect(find.byKey(const Key('user-row-usr-praveen')), findsNothing);
  });

  testWidgets('project teams show staffing and save team changes', (
    tester,
  ) async {
    final repository = await _pump(tester, const Size(1440, 1000));

    await tester.tap(
      find.byKey(const ValueKey('user-management-tab-projectAccess')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-team-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-team-p2')), findsOneWidget);
    // Completed projects are outside the default "Open projects" view.
    expect(find.byKey(const ValueKey('project-team-p3')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-team-p2')),
        matching: find.text('Needs a Project Engineer'),
      ),
      findsOneWidget,
    );
    expect(find.text('Organisation-wide access'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('user-management-evidence')),
      matchesGoldenFile('goldens/user_management/project_teams_1440x1000.png'),
    );

    await tester.tap(find.byKey(const ValueKey('project-team-manage-p2')));
    await tester.pumpAndSettle();
    expect(find.text('Team · YRA-401'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('team-role-usr-arnal')),
        matching: find.byType(
          DropdownButtonFormField<YorksV1ProjectMembershipRole?>,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project Engineer').last);
    await tester.pumpAndSettle();
    expect(find.text('1 change to save'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-team-save')));
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    final call = repository.calls.single;
    expect(call.appUserId, 'usr-arnal');
    expect(call.projectId, 'p2');
    expect(call.role, YorksV1ProjectMembershipRole.projectEngineer);
    expect(call.expectedProjectVersion, 2);
    expect(find.text('Project team updated.'), findsOneWidget);
    expect(repository.loads, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused team change explains the rule and keeps the dialog', (
    tester,
  ) async {
    final repository = await _pump(tester, const Size(1440, 1000));
    repository.failWith = yorksV1UserProjectAccessFailure(
      '55000',
      'V1_ACTIVE_PROJECT_REQUIRES_PROJECT_ENGINEER',
    );

    await tester.tap(
      find.byKey(const ValueKey('user-management-tab-projectAccess')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-team-manage-p1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('team-role-usr-praveen')),
        matching: find.byType(
          DropdownButtonFormField<YorksV1ProjectMembershipRole?>,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not on this project').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-team-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('An active project must keep at least one Project Engineer.'),
      findsOneWidget,
    );
    expect(find.text('Team · YRA-313'), findsOneWidget);
  });

  testWidgets('edit user lists project roles and adds a project', (
    tester,
  ) async {
    final repository = await _pump(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const Key('manage-user-usr-shabir')));
    await tester.pumpAndSettle();
    expect(find.text('Edit User'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-project-membership-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('user-project-membership-p2')),
      findsOneWidget,
    );
    await expectLater(
      find.byKey(const ValueKey('user-management-evidence')),
      matchesGoldenFile('goldens/user_management/edit_user_1440x1000.png'),
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-user-usr-arnal')));
    await tester.pumpAndSettle();
    expect(find.text('Not on any project yet.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('user-project-add-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YRA-401 · Jeddah Grid Station').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-project-add')));
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.appUserId, 'usr-arnal');
    expect(repository.calls.single.projectId, 'p2');
    expect(
      repository.calls.single.role,
      YorksV1ProjectMembershipRole.siteEngineer,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout uses cards without overflow', (tester) async {
    await _pump(tester, const Size(390, 844));

    expect(find.byKey(const Key('user-card-usr-shabir')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('user-management-evidence')),
      matchesGoldenFile('goldens/user_management/users_390x844.png'),
    );

    await tester.tap(
      find.byKey(const ValueKey('user-management-tab-projectAccess')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

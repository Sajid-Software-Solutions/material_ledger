import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';

/// Capabilities in the shape the server really returns for an Accountant:
/// `role_default` true, `authoritative_effective` null, no overrides, and an empty
/// `project_access` because an Accountant is never a technical project member.
/// A fixture granting organization scope hid the fact that this denied everything.
Map<String, Object?> _capability(
  String key,
  String module, {
  bool roleDefault = true,
  List<Map<String, Object?>> overrides = const [],
}) => {
  'capability_key': key,
  'module_key': module,
  'action_key': 'test_action',
  'label': key,
  'description': key,
  'risk_level': 'critical',
  'allowed_scope_kinds': ['project'],
  'requires_project_access': true,
  'dependencies': <String>[],
  'runtime_status': 'operational',
  'is_assignable': true,
  'display_order': 1,
  'authorization_mode': 'enforced',
  'role_default': roleDefault,
  'organization_summary_visible': false,
  'authoritative_effective': null,
  'authoritative_source': null,
  'candidate_effective': null,
  'candidate_source': null,
  'parity': null,
  'actor_can_delegate': false,
  'actor_delegable_scope_kinds': <String>[],
  'project_overrides': overrides,
};

YorksV1CurrentPermissionSnapshotState _state(
  YorksV1Role role,
  List<Map<String, Object?>> capabilities,
) => YorksV1CurrentPermissionSnapshotState(
  snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'mixed',
    'generated_at': '2026-11-07T00:00:00Z',
    'user': {
      'app_user_id': 'u1',
      'display_name': 'Test user',
      'exact_role': role.claimValue,
      'is_active': true,
    },
    'revision': 1,
    'capabilities': capabilities,
    'project_access': <Object?>[],
  }),
  isStale: false,
  isRevisionSignalHealthy: true,
);

void main() {
  const accounts = YorksV1CapabilityKeys.viewProjectAccounts;
  const projects = YorksV1CapabilityKeys.projectsView;

  group('Accountant', () {
    test('holds Accounts capabilities on a project without membership', () {
      final state = _state(YorksV1Role.accountant, [
        _capability(accounts, 'accounts'),
      ]);
      expect(state.snapshot!.allows(accounts, projectId: 'p1'), isTrue);
      expect(
        state.hybridAllows(accounts, legacyAllowed: false, projectId: 'p1'),
        isTrue,
      );
    });

    test('opens the office, which uses the organization summary', () {
      final state = _state(YorksV1Role.accountant, [
        _capability(accounts, 'accounts'),
      ]);
      expect(
        state.hybridAllows(
          accounts,
          legacyAllowed: false,
          organizationSummary: true,
        ),
        isTrue,
      );
    });

    test('gains nothing outside the Accounts module', () {
      final state = _state(YorksV1Role.accountant, [
        _capability(projects, 'projects'),
      ]);
      expect(state.snapshot!.allows(projects, projectId: 'p1'), isFalse);
      expect(
        state.hybridAllows(
          projects,
          legacyAllowed: false,
          organizationSummary: true,
        ),
        isFalse,
      );
    });

    test('is denied an Accounts capability the role does not hold', () {
      final state = _state(YorksV1Role.accountant, [
        _capability(accounts, 'accounts', roleDefault: false),
      ]);
      expect(state.snapshot!.allows(accounts, projectId: 'p1'), isFalse);
    });

    test('a denial on one project wins, without affecting others', () {
      final state = _state(YorksV1Role.accountant, [
        _capability(
          accounts,
          'accounts',
          overrides: [
            {
              'project_id': 'p1',
              'project_ref': 'P-1',
              'project_name': 'Project one',
              'effect': 'deny',
              'has_project_access': false,
              'authoritative_effective': false,
              'authoritative_source': 'explicit_deny',
              'candidate_effective': false,
              'candidate_source': 'explicit_deny',
              'parity': true,
              'effective_from': '2026-11-01T00:00:00Z',
              'effective_until': null,
              'assignment_id': 'a1',
            },
          ],
        ),
      ]);
      expect(state.snapshot!.allows(accounts, projectId: 'p1'), isFalse);
      expect(state.snapshot!.allows(accounts, projectId: 'p2'), isTrue);
    });

    test('an inactive user is denied', () {
      final state = YorksV1CurrentPermissionSnapshotState(
        snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson({
          'schema_version': 1,
          'authorization_mode': 'mixed',
          'generated_at': '2026-11-07T00:00:00Z',
          'user': {
            'app_user_id': 'u1',
            'display_name': 'Test user',
            'exact_role': YorksV1Role.accountant.claimValue,
            'is_active': false,
          },
          'revision': 1,
          'capabilities': [_capability(accounts, 'accounts')],
          'project_access': <Object?>[],
        }),
        isStale: false,
        isRevisionSignalHealthy: true,
      );
      expect(state.snapshot!.allows(accounts, projectId: 'p1'), isFalse);
    });
  });

  group('Other roles are not widened', () {
    for (final role in const [
      YorksV1Role.projectEngineer,
      YorksV1Role.siteEngineer,
      YorksV1Role.procurement,
      YorksV1Role.admin,
    ]) {
      test('${role.claimValue} still needs project access', () {
        final state = _state(role, [_capability(accounts, 'accounts')]);
        expect(state.snapshot!.allows(accounts, projectId: 'p1'), isFalse);
        expect(
          state.hybridAllows(
            accounts,
            legacyAllowed: false,
            organizationSummary: true,
          ),
          isFalse,
        );
      });
    }
  });
}

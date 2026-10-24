import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';

const yorksV1EnforcedFeatureActionCapabilities = <String>{
  YorksV1CapabilityKeys.projectsView,
  YorksV1CapabilityKeys.projectsCreate,
  YorksV1CapabilityKeys.projectsEdit,
  YorksV1CapabilityKeys.projectsArchive,
  YorksV1CapabilityKeys.boqView,
  YorksV1CapabilityKeys.boqEdit,
  YorksV1CapabilityKeys.boqManageFolders,
  YorksV1CapabilityKeys.materialRequestsView,
  YorksV1CapabilityKeys.materialRequestsCreate,
  YorksV1CapabilityKeys.materialRequestsEdit,
  YorksV1CapabilityKeys.materialRequestsSubmit,
  YorksV1CapabilityKeys.materialRequestsApprove,
  YorksV1CapabilityKeys.materialRequestsReturnForChanges,
  YorksV1CapabilityKeys.materialRequestsCancel,
  YorksV1CapabilityKeys.materialRequestsClose,
  YorksV1CapabilityKeys.procurementArrange,
  YorksV1CapabilityKeys.dispatchCreate,
  YorksV1CapabilityKeys.deliveryOrdersGenerate,
  YorksV1CapabilityKeys.receiptsConfirm,
  YorksV1CapabilityKeys.returnsView,
  YorksV1CapabilityKeys.returnsCreate,
  YorksV1CapabilityKeys.returnsApprove,
  YorksV1CapabilityKeys.returnsDispatch,
};

/// Supplies a server-confirmed allow snapshot to direct feature widget tests.
///
/// Production screens intentionally fail closed without a confirmed snapshot;
/// tests that render those screens outside the workspace shell therefore need
/// to declare the permission state that the shell normally provides.
class YorksV1TestPermissionController
    extends YorksV1CurrentPermissionSnapshotController {
  void replace(YorksV1CurrentPermissionSnapshotState value) => state = value;
  YorksV1TestPermissionController(YorksV1CurrentPermissionSnapshotState value)
    : super(
        enabled: false,
        authUserId: null,
        client: null,
        repository: _UnusedPermissionRepository(),
      ) {
    state = value;
  }
}

YorksV1CurrentPermissionSnapshotState yorksV1TrustedFeaturePermissionState({
  YorksV1Role role = YorksV1Role.admin,
  Iterable<String> capabilities = yorksV1EnforcedFeatureActionCapabilities,
  bool stale = false,
  List<String>? projectIds,
}) => YorksV1CurrentPermissionSnapshotState(
  snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced',
    'generated_at': '2026-08-24T09:00:00Z',
    'user': {
      'app_user_id': 'permission-widget-test-user',
      'display_name': 'Permission widget test user',
      'exact_role': role.claimValue,
      'is_active': true,
    },
    'revision': 1,
    'capabilities': [
      for (final (index, capability) in capabilities.indexed)
        {
          'capability_key': capability,
          'module_key': capability.split('.').first,
          'action_key': capability.split('.').skip(1).join('.'),
          'label': capability,
          'description': capability,
          'risk_level': 'high',
          'allowed_scope_kinds': ['organization'],
          // Direct widget tests exercise layout and existing structural
          // predicates. Project membership/RLS semantics have dedicated model
          // and database tests, so this fixture grants organization scope.
          'requires_project_access': projectIds != null,
          'dependencies': <String>[],
          'runtime_status': 'operational',
          'is_assignable': true,
          'display_order': index,
          'authorization_mode': 'enforced',
          'role_default': true,
          'organization_summary_visible': true,
          'authoritative_effective': true,
          'authoritative_source': 'role_default',
          'candidate_effective': true,
          'candidate_source': 'role_default',
          'parity': true,
          'actor_can_delegate': true,
          'actor_delegable_scope_kinds': ['organization'],
          'project_overrides': [
            for (final id in projectIds ?? <String>[])
              {
                'project_id': id,
                'project_ref': id,
                'project_name': id,
                'effect': null,
                'has_project_access': true,
                'authoritative_effective': true,
                'authoritative_source': 'role_default',
                'candidate_effective': true,
                'candidate_source': 'role_default',
                'parity': true,
              },
          ],
        },
    ],
    'project_access': [
      for (final id in projectIds ?? <String>[])
        {
          'project_id': id,
          'project_ref': id,
          'project_name': id,
          'state': 'active',
          'has_access': true,
        },
    ],
  }),
  isStale: stale,
  isRevisionSignalHealthy: true,
);

class _UnusedPermissionRepository implements YorksV1PermissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

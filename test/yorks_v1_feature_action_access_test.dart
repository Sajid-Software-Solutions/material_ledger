import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/yorks_v1_feature_action_access.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';

void main() {
  const projectId = '11111111-1111-4111-8111-111111111111';

  test('unknown access keeps expected action visible while checking', () {
    final access = yorksV1FeatureActionAccess(
      const YorksV1CurrentPermissionSnapshotState(isInitialLoading: true),
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: true,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isFalse);
    expect(access.availability, YorksV1ActionAvailability.checking);
  });

  test('transport failure is distinct from confirmed denial', () {
    final access = yorksV1FeatureActionAccess(
      const YorksV1CurrentPermissionSnapshotState(
        error: YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      ),
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: true,
    );
    final denied = yorksV1FeatureActionAccess(
      const YorksV1CurrentPermissionSnapshotState(
        error: YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
      ),
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: true,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isFalse);
    expect(
      access.availability,
      YorksV1ActionAvailability.temporarilyUnavailable,
    );
    expect(denied.availability, YorksV1ActionAvailability.denied);
    expect(denied.isVisible, isFalse);
  });

  test('enforced project grant enables the matching trusted action', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: true),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isTrue);
    expect(access.isWritePaused, isFalse);
  });

  test('authoritative grant cannot bypass structural workflow eligibility', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: true),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: false,
      projectId: projectId,
    );

    expect(access.isVisible, isFalse);
    expect(access.canWrite, isFalse);
  });

  test('enforced project deny overrides a permissive legacy role', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: false),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isFalse);
    expect(access.canWrite, isFalse);
  });

  test('stale confirmed grant remains visible but write stays locked', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: true, stale: true),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isFalse);
    expect(access.isWritePaused, isTrue);
  });

  test('routine refresh keeps a trusted action available', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: true, refreshing: true),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isTrue);
    expect(access.isWritePaused, isFalse);
  });

  test('transient routine failure retains trusted action availability', () {
    final access = yorksV1FeatureActionAccess(
      _state(
        allowed: true,
        error: const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      ),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isTrue);
  });

  test('Realtime transport loss does not disable a confirmed action', () {
    final confirmed = _state(
      allowed: true,
      error: const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      ),
    );
    final disconnected = confirmed.copyWith(isRevisionSignalHealthy: false);
    final access = yorksV1FeatureActionAccess(
      disconnected,
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.availability, YorksV1ActionAvailability.allowed);
    expect(access.canWrite, isTrue);
  });

  test('shadow capability preserves the supplied legacy decision', () {
    final denied = yorksV1FeatureActionAccess(
      _state(allowed: true, mode: 'shadow'),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: false,
      projectId: projectId,
    );
    final allowed = yorksV1FeatureActionAccess(
      _state(allowed: false, mode: 'shadow'),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(denied.isVisible, isFalse);
    expect(allowed.canWrite, isTrue);
  });

  test('shadow legacy allow remains visible while stale writes pause', () {
    final access = yorksV1FeatureActionAccess(
      _state(allowed: false, mode: 'shadow', stale: true),
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: true,
      projectId: projectId,
    );

    expect(access.isVisible, isTrue);
    expect(access.canWrite, isFalse);
  });
}

YorksV1CurrentPermissionSnapshotState _state({
  required bool allowed,
  String mode = 'enforced',
  bool stale = false,
  bool refreshing = false,
  Object? error,
}) => YorksV1CurrentPermissionSnapshotState(
  snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': mode,
    'generated_at': '2026-08-24T09:00:00Z',
    'user': {
      'app_user_id': 'usr-engineer',
      'display_name': 'Project Engineer',
      'exact_role': 'project_engineer',
      'is_active': true,
    },
    'revision': 9,
    'capabilities': [
      {
        'capability_key': YorksV1CapabilityKeys.projectsEdit,
        'module_key': 'projects',
        'action_key': 'edit',
        'label': 'Edit projects',
        'description': 'Edit an authorized project.',
        'risk_level': 'high',
        'allowed_scope_kinds': ['organization', 'project'],
        'requires_project_access': true,
        'dependencies': ['projects.view'],
        'runtime_status': 'operational',
        'is_assignable': true,
        'display_order': 13,
        'authorization_mode': mode,
        'role_default': true,
        'organization_summary_visible': true,
        'authoritative_effective': allowed,
        'authoritative_source': allowed ? 'explicit_grant' : 'explicit_deny',
        'candidate_effective': allowed,
        'candidate_source': allowed ? 'explicit_grant' : 'explicit_deny',
        'parity': true,
        'actor_can_delegate': true,
        'actor_delegable_scope_kinds': ['organization'],
        'project_overrides': [
          {
            'assignment_id': null,
            'project_id': '11111111-1111-4111-8111-111111111111',
            'project_ref': 'YRA-313',
            'project_name': 'Riyadh Substation',
            'effect': null,
            'has_project_access': true,
            'authoritative_effective': allowed,
            'authoritative_source': allowed
                ? 'explicit_grant'
                : 'explicit_deny',
            'candidate_effective': allowed,
            'candidate_source': allowed ? 'explicit_grant' : 'explicit_deny',
            'parity': true,
            'effective_from': null,
            'effective_until': null,
          },
        ],
      },
    ],
    'project_access': [
      {
        'project_id': '11111111-1111-4111-8111-111111111111',
        'project_ref': 'YRA-313',
        'project_name': 'Riyadh Substation',
        'state': 'active',
        'has_access': true,
      },
    ],
  }),
  isRefreshing: refreshing,
  isStale: stale,
  isRevisionSignalHealthy: true,
  error: error,
);

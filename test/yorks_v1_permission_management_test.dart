import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('permission models', () {
    test('shadow candidate grant cannot open a protected action', () {
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(
        _snapshotJson(
          authorizationMode: 'shadow',
          capabilityMode: 'shadow',
          authoritativeEffective: false,
          candidateEffective: true,
          parity: false,
        ),
      );

      expect(
        snapshot.authorizationMode,
        YorksV1PermissionAuthorizationMode.shadow,
      );
      expect(
        snapshot
            .capability(YorksV1CapabilityKeys.projectsEdit)!
            .candidateEffective,
        isTrue,
      );
      expect(
        snapshot.capability(YorksV1CapabilityKeys.projectsEdit)!.canEdit,
        isFalse,
      );
      expect(
        snapshot.allows(
          YorksV1CapabilityKeys.projectsEdit,
          projectId: _projectId,
        ),
        isFalse,
      );
    });

    test('authoritative project decision also requires project access', () {
      final response = _snapshotJson(
        authoritativeEffective: true,
        candidateEffective: true,
      );
      (response['project_access'] as List).clear();
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(response);

      expect(
        snapshot.allows(
          YorksV1CapabilityKeys.projectsEdit,
          projectId: _projectId,
        ),
        isFalse,
      );
    });

    test('resolution-only project rows decode without a direct assignment', () {
      final response = _snapshotJson(
        authoritativeEffective: true,
        candidateEffective: true,
      );
      final capability =
          (response['capabilities'] as List).single as Map<String, dynamic>;
      capability['project_overrides'] = [
        {
          'project_id': _projectId,
          'project_ref': 'YRA-313',
          'project_name': 'Riyadh Substation',
          'effect': null,
          'has_project_access': true,
          'authoritative_effective': true,
          'authoritative_source': 'role_default',
          'candidate_effective': true,
          'candidate_source': 'role_default',
          'parity': true,
          'effective_from': null,
          'effective_until': null,
          'assignment_id': null,
        },
      ];

      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(response);
      final project = snapshot.capabilities.single.projectOverrides.single;

      expect(project.hasDirectAssignment, isFalse);
      expect(project.assignmentId, isNull);
      expect(project.effect, isNull);
      expect(
        snapshot.allows(
          YorksV1CapabilityKeys.projectsEdit,
          projectId: _projectId,
        ),
        isTrue,
      );
    });

    test('unknown future catalog key stays readable but fail-closed', () {
      final response = _snapshotJson(
        authoritativeEffective: true,
        candidateEffective: true,
      );
      final capability =
          (response['capabilities'] as List).single as Map<String, dynamic>;
      capability['capability_key'] = 'future_workspace.inspect';
      capability['module_key'] = 'future_workspace';
      capability['action_key'] = 'inspect';
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(response);

      expect(snapshot.capabilities.single.catalog.isClientRecognized, isFalse);
      expect(snapshot.capabilities.single.catalog.isOperational, isFalse);
      expect(
        snapshot.allows('future_workspace.inspect', projectId: _projectId),
        isFalse,
      );
    });

    test('delegation projection is required and gates row editing', () {
      final allowed = YorksV1PermissionCapabilityAccess.fromJson(
        _capabilityJson(),
        targetRole: YorksV1Role.projectEngineer,
      );
      expect(allowed.actorDelegableScopes, {
        YorksV1PermissionScopeKind.organization,
      });
      expect(allowed.canEdit, isTrue);

      final denied = _capabilityJson()..['actor_can_delegate'] = false;
      final access = YorksV1PermissionCapabilityAccess.fromJson(
        denied,
        targetRole: YorksV1Role.projectEngineer,
      );
      expect(access.actorCanDelegate, isFalse);
      expect(access.canEdit, isFalse);

      final missing = _capabilityJson()..remove('actor_can_delegate');
      expect(
        () => YorksV1PermissionCapabilityAccess.fromJson(
          missing,
          targetRole: YorksV1Role.projectEngineer,
        ),
        throwsFormatException,
      );

      final missingScopes = _capabilityJson()
        ..remove('actor_delegable_scope_kinds');
      final readOnly = YorksV1PermissionCapabilityAccess.fromJson(
        missingScopes,
        targetRole: YorksV1Role.projectEngineer,
      );
      expect(readOnly.actorDelegableScopes, isEmpty);
      expect(readOnly.canEdit, isFalse);

      final malformedScopes = _capabilityJson()
        ..['actor_delegable_scope_kinds'] = 'organization';
      expect(
        () => YorksV1PermissionCapabilityAccess.fromJson(
          malformedScopes,
          targetRole: YorksV1Role.projectEngineer,
        ),
        throwsFormatException,
      );
    });

    test('unsupported projection schema fails closed', () {
      final response = _snapshotJson()..['schema_version'] = 2;

      expect(
        () => YorksV1CurrentPermissionSnapshot.fromRpcJson(response),
        throwsFormatException,
      );
    });

    test('snapshot retains the next server assignment boundary', () {
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(
        _snapshotJson(nextTransitionAt: '2026-08-24T09:05:00Z'),
      );

      expect(snapshot.nextTransitionAt, DateTime.parse('2026-08-24T09:05:00Z'));
    });

    test('scope and persisted assignment effects reject ambiguous input', () {
      expect(
        () => YorksV1PermissionScope(
          kind: YorksV1PermissionScopeKind.organization,
          projectIds: const [_projectId],
        ),
        throwsFormatException,
      );
      expect(
        () => YorksV1PermissionAssignmentEffect.fromWire('inherit'),
        throwsFormatException,
      );
      expect(
        () => YorksV1PermissionRiskLevel.fromWire('severe'),
        throwsFormatException,
      );
    });

    test('system migration evidence parses without becoming an app role', () {
      final actor = YorksV1PermissionActor.fromJson({
        'actor_kind': 'system',
        'app_user_id': null,
        'display_name': 'System migration',
        'exact_role': 'system',
      });

      expect(actor.isSystem, isTrue);
      expect(actor.appUserId, isNull);
      expect(actor.exactRole, isNull);
    });

    test(
      'unknown effective source fails closed at the projection boundary',
      () {
        final response = _snapshotJson();
        final capability =
            (response['capabilities'] as List).single as Map<String, dynamic>;
        capability['authoritative_source'] = 'invented_source';

        expect(
          () => YorksV1CurrentPermissionSnapshot.fromRpcJson(response),
          throwsFormatException,
        );
      },
    );

    test('project override retains authoritative and shadow decisions', () {
      final response = _snapshotJson();
      final capability =
          (response['capabilities'] as List).single as Map<String, dynamic>;
      capability['project_overrides'] = [
        {
          'assignment_id': _assignmentId,
          'project_id': _projectId,
          'project_ref': 'YRA-313',
          'project_name': 'Riyadh Substation',
          'effect': 'grant',
          'has_project_access': true,
          'authoritative_effective': false,
          'authoritative_source': 'none',
          'candidate_effective': true,
          'candidate_source': 'explicit_grant',
          'parity': false,
          'effective_from': '2026-08-24T09:00:00Z',
          'effective_until': null,
        },
      ];
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(response);
      final access = snapshot.capabilities.single;

      expect(access.projectOverrides.single.hasParity, isFalse);
      expect(access.candidateEffectiveForProject(_projectId), isTrue);
      expect(access.authoritativeEffectiveForProject(_projectId), isFalse);
      expect(
        snapshot.allows(
          YorksV1CapabilityKeys.projectsEdit,
          projectId: _projectId,
        ),
        isFalse,
      );
    });

    test('legacy assignment and immutable history remain attributable', () {
      final workspaceJson = _workspaceJson();
      workspaceJson['assignments'] = [
        {
          'id': _assignmentId,
          'capability_key': YorksV1CapabilityKeys.commercialsView,
          'effect': 'grant',
          'scope_kind': 'organization',
          'origin': 'legacy_commercial',
          'project_ids': <String>[],
          'effective_from': '2026-08-24T09:00:00Z',
          'effective_until': null,
          'reason': 'Preserved legacy commercial override.',
          'version': 1,
          'changed_by': {
            'actor_kind': 'system',
            'app_user_id': null,
            'display_name': 'System migration',
            'exact_role': 'system',
          },
          'created_at': '2026-08-24T09:00:00Z',
          'updated_at': '2026-08-24T09:00:00Z',
        },
      ];
      workspaceJson['recent_history'] = [
        {
          'id': '55555555-5555-4555-8555-555555555555',
          'event_kind': 'legacy_sync',
          'capability_key': YorksV1CapabilityKeys.commercialsView,
          'effect': 'grant',
          'scope_kind': 'organization',
          'project_ids': <String>[],
          'before': [
            {
              'capability_key': YorksV1CapabilityKeys.commercialsView,
              'effect': 'deny',
              'scope_kind': 'organization',
              'project_ids': <String>[],
              'effective_from': '2026-08-24T08:00:00Z',
              'effective_until': null,
            },
          ],
          'after': [
            {
              'capability_key': YorksV1CapabilityKeys.commercialsView,
              'effect': 'grant',
              'scope_kind': 'organization',
              'project_ids': <String>[],
              'effective_from': '2026-08-24T09:00:00Z',
              'effective_until': null,
            },
          ],
          'reason': 'Preserved legacy commercial override.',
          'actor': {
            'actor_kind': 'system',
            'app_user_id': null,
            'display_name': 'System migration',
            'exact_role': 'system',
          },
          'occurred_at': '2026-08-24T09:00:00Z',
          'idempotency_key': null,
          'event_ordinal': 1,
          'revision': 7,
        },
      ];

      final workspace = YorksV1UserPermissionWorkspace.fromRpcJson(
        workspaceJson,
      );

      expect(
        workspace.assignments.single.origin,
        YorksV1PermissionAssignmentOrigin.legacyCommercial,
      );
      expect(workspace.assignments.single.changedBy?.isSystem, isTrue);
      expect(
        workspace.recentHistory.single.kind,
        YorksV1PermissionHistoryEventKind.legacySync,
      );
      expect(workspace.recentHistory.single.idempotencyKey, isNull);
      expect(
        workspace.recentHistory.single.before.single.effect,
        YorksV1PermissionAssignmentEffect.deny,
      );
      expect(
        workspace.recentHistory.single.after.single.effect,
        YorksV1PermissionAssignmentEffect.grant,
      );
    });

    test('workspace parses strict additive Workforce access status', () {
      final workspaceJson = _workspaceJson();
      workspaceJson['workforce_access'] = {
        'reference_date': '2026-08-31',
        'has_operational_access': true,
        'can_assign_organization_responsibility': true,
        'active_worker_count': 0,
        'active_team_count': 0,
        'scheduled_team_count': 0,
        'organization_responsibility': {
          'responsibility_assignment_id':
              '5ae50000-0000-4000-8000-000000000001',
          'valid_from': '2026-08-31',
          'valid_to': null,
          'record_version': 1,
        },
      };

      final workspace = YorksV1UserPermissionWorkspace.fromRpcJson(
        workspaceJson,
      );

      expect(workspace.workforceAccess, isNotNull);
      expect(workspace.workforceAccess!.hasOrganizationResponsibility, isTrue);
      expect(workspace.workforceAccess!.isConfigurationEmpty, isTrue);

      final malformed = _workspaceJson();
      malformed['workforce_access'] = {
        'reference_date': '2026-08-31',
        'has_operational_access': true,
        'can_assign_organization_responsibility': true,
        'active_worker_count': 0,
        'active_team_count': 0,
        'scheduled_team_count': 0,
        'organization_responsibility': {
          'responsibility_assignment_id':
              '5ae50000-0000-4000-8000-000000000001',
          'valid_from': '2026-08-31',
          'valid_to': null,
        },
      };
      expect(
        () => YorksV1UserPermissionWorkspace.fromRpcJson(malformed),
        throwsFormatException,
      );
    });
  });

  group('permission repository', () {
    test('current snapshot uses the self-only protected RPC', () async {
      final rpc = _RecordingPermissionRpc(_snapshotJson());
      final repository = _repository(rpc: rpc);

      final snapshot = await repository.getCurrentSnapshot();

      expect(rpc.functionName, 'v1_get_current_permission_snapshot');
      expect(rpc.parameters, isEmpty);
      expect(snapshot.user.appUserId, 'usr-engineer');
    });

    test(
      'target workspace uses stable app-user id, never an Auth UUID',
      () async {
        final rpc = _RecordingPermissionRpc(_workspaceJson());
        final repository = _repository(rpc: rpc);

        final workspace = await repository.getUserWorkspace(
          targetAppUserId: ' usr-engineer ',
        );

        expect(rpc.functionName, 'v1_get_user_permission_workspace');
        expect(rpc.parameters, {'p_target_app_user_id': 'usr-engineer'});
        expect(workspace.target.appUserId, 'usr-engineer');
      },
    );

    test('reviewed batch sends one exact atomic payload', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson(revision: 8));
      final repository = _repository(rpc: rpc);
      final changes = [
        YorksV1PermissionChange.set(
          capabilityKey: YorksV1CapabilityKeys.projectsEdit,
          effect: YorksV1PermissionAssignmentEffect.grant,
          scope: YorksV1PermissionScope(
            kind: YorksV1PermissionScopeKind.project,
            projectIds: const [_projectId],
          ),
          effectiveFrom: DateTime.utc(2026, 8, 25),
          effectiveUntil: DateTime.utc(2026, 9, 25),
        ),
        YorksV1PermissionChange.clear(assignmentId: _assignmentId),
      ];

      final workspace = await repository.applyChanges(
        YorksV1ApplyPermissionChangesInput(
          targetAppUserId: 'usr-engineer',
          changes: changes,
          reason: 'Approved project coverage adjustment.',
          expectedRevision: 7,
          idempotencyKey: _idempotencyKey,
        ),
      );

      expect(rpc.functionName, 'v1_apply_user_permission_changes');
      expect(rpc.parameters, {
        'p_target_app_user_id': 'usr-engineer',
        'p_changes': [
          {
            'operation': 'set',
            'capability_key': YorksV1CapabilityKeys.projectsEdit,
            'effect': 'grant',
            'scope_kind': 'project',
            'project_ids': [_projectId],
            'effective_from': '2026-08-25T00:00:00.000Z',
            'effective_until': '2026-09-25T00:00:00.000Z',
          },
          {'operation': 'clear', 'assignment_id': _assignmentId},
        ],
        'p_reason': 'Approved project coverage adjustment.',
        'p_expected_revision': 7,
        'p_idempotency_key': _idempotencyKey,
      });
      expect(workspace.revision, 8);
    });

    test('Workforce access recovery uses the exact reviewed RPCs', () async {
      final combinedRpc = _RecordingPermissionRpc(_workspaceJson(revision: 8));
      final repository = _repository(rpc: combinedRpc);
      final input = YorksV1ApplyPermissionChangesInput(
        targetAppUserId: 'usr-engineer',
        changes: [
          YorksV1PermissionChange.set(
            capabilityKey: YorksV1CapabilityKeys.workforceView,
            effect: YorksV1PermissionAssignmentEffect.grant,
            scope: YorksV1PermissionScope(
              kind: YorksV1PermissionScopeKind.organization,
            ),
          ),
        ],
        reason: 'Reviewed Workforce responsibility enablement.',
        expectedRevision: 7,
        idempotencyKey: _idempotencyKey,
      );

      await repository.applyChangesWithWorkforce(
        input: input,
        assignOrganizationResponsibility: true,
      );

      expect(
        combinedRpc.functionName,
        'v1_apply_user_permission_changes_with_workforce',
      );
      expect(combinedRpc.parameters, {
        'p_target_app_user_id': 'usr-engineer',
        'p_changes': [
          {
            'operation': 'set',
            'capability_key': YorksV1CapabilityKeys.workforceView,
            'effect': 'grant',
            'scope_kind': 'organization',
            'project_ids': <String>[],
            'effective_from': null,
            'effective_until': null,
          },
        ],
        'p_reason': 'Reviewed Workforce responsibility enablement.',
        'p_expected_revision': 7,
        'p_assign_organization_responsibility': true,
        'p_idempotency_key': _idempotencyKey,
      });

      final standaloneRpc = _RecordingPermissionRpc(
        _workspaceJson(revision: 8),
      );
      await _repository(
        rpc: standaloneRpc,
      ).assignWorkforceOrganizationResponsibility(
        targetAppUserId: 'usr-engineer',
        reason: 'Restore retained Workforce responsibility.',
        idempotencyKey: _idempotencyKey,
      );
      expect(
        standaloneRpc.functionName,
        'v1_assign_user_workforce_organization',
      );
      expect(standaloneRpc.parameters, {
        'p_target_app_user_id': 'usr-engineer',
        'p_reason': 'Restore retained Workforce responsibility.',
        'p_idempotency_key': _idempotencyKey,
      });
    });

    test(
      'singular set and clear wrappers use exact protected contracts',
      () async {
        final setRpc = _RecordingPermissionRpc(_workspaceJson(revision: 8));
        await _repository(rpc: setRpc).setAssignment(
          YorksV1SetPermissionAssignmentInput(
            targetAppUserId: 'usr-engineer',
            capabilityKey: YorksV1CapabilityKeys.inventoryView,
            effect: YorksV1PermissionAssignmentEffect.deny,
            scope: YorksV1PermissionScope(
              kind: YorksV1PermissionScopeKind.organization,
            ),
            reason: 'Reviewed temporary warehouse restriction.',
            expectedRevision: 7,
            idempotencyKey: _idempotencyKey,
          ),
        );
        expect(setRpc.functionName, 'v1_set_user_permission_assignment');
        expect(setRpc.parameters, {
          'p_target_app_user_id': 'usr-engineer',
          'p_capability_key': YorksV1CapabilityKeys.inventoryView,
          'p_effect': 'deny',
          'p_scope_kind': 'organization',
          'p_project_ids': <String>[],
          'p_effective_from': null,
          'p_effective_until': null,
          'p_reason': 'Reviewed temporary warehouse restriction.',
          'p_expected_revision': 7,
          'p_idempotency_key': _idempotencyKey,
        });

        final clearRpc = _RecordingPermissionRpc(_workspaceJson(revision: 9));
        await _repository(rpc: clearRpc).clearAssignment(
          YorksV1ClearPermissionAssignmentInput(
            targetAppUserId: 'usr-engineer',
            assignmentId: _assignmentId,
            reason: 'Return this capability to its role baseline.',
            expectedRevision: 8,
            idempotencyKey: _idempotencyKey,
          ),
        );
        expect(clearRpc.functionName, 'v1_clear_user_permission_assignment');
        expect(clearRpc.parameters, {
          'p_target_app_user_id': 'usr-engineer',
          'p_assignment_id': _assignmentId,
          'p_reason': 'Return this capability to its role baseline.',
          'p_expected_revision': 8,
          'p_idempotency_key': _idempotencyKey,
        });
      },
    );

    test('multi-segment capability key reaches the protected RPC', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson(revision: 8));
      final repository = _repository(rpc: rpc);

      await repository.applyChanges(
        YorksV1ApplyPermissionChangesInput(
          targetAppUserId: 'usr-engineer',
          changes: [
            YorksV1PermissionChange.set(
              capabilityKey:
                  YorksV1CapabilityKeys.procurementExternalReadinessManage,
              effect: YorksV1PermissionAssignmentEffect.grant,
              scope: YorksV1PermissionScope(
                kind: YorksV1PermissionScopeKind.project,
                projectIds: const [_projectId],
              ),
            ),
          ],
          reason: 'Reviewed external readiness responsibility.',
          expectedRevision: 7,
          idempotencyKey: _idempotencyKey,
        ),
      );

      final changes = rpc.parameters!['p_changes']! as List<Object?>;
      expect(
        (changes.single! as Map<String, Object?>)['capability_key'],
        'procurement.external_readiness.manage',
      );
    });

    test('all exact R39 Accounts keys reach the protected RPC', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson(revision: 8));
      final repository = _repository(rpc: rpc);

      await repository.applyChanges(
        YorksV1ApplyPermissionChangesInput(
          targetAppUserId: 'usr-engineer',
          changes: [
            for (final capability in YorksV1CapabilityKeys.r39Accounts)
              YorksV1PermissionChange.set(
                capabilityKey: capability,
                effect: YorksV1PermissionAssignmentEffect.grant,
                scope: YorksV1PermissionScope(
                  kind: YorksV1PermissionScopeKind.organization,
                ),
              ),
          ],
          reason: 'Reviewed R39 Accounts capability assignment.',
          expectedRevision: 7,
          idempotencyKey: _idempotencyKey,
        ),
      );

      final changes = rpc.parameters!['p_changes']! as List<Object?>;
      expect(
        changes
            .cast<Map<String, Object?>>()
            .map((change) => change['capability_key'])
            .toSet(),
        YorksV1CapabilityKeys.r39Accounts,
      );
    });

    test('unknown bare capability key is rejected before any RPC', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson());
      final repository = _repository(rpc: rpc);

      await expectLater(
        repository.setAssignment(
          YorksV1SetPermissionAssignmentInput(
            targetAppUserId: 'usr-engineer',
            capabilityKey: 'unknown_accounts_capability',
            effect: YorksV1PermissionAssignmentEffect.grant,
            scope: YorksV1PermissionScope(
              kind: YorksV1PermissionScopeKind.organization,
            ),
            reason: 'This key must remain outside the closed vocabulary.',
            expectedRevision: 7,
            idempotencyKey: _idempotencyKey,
          ),
        ),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.invalidInput,
          ),
        ),
      );
      expect(rpc.functionName, isNull);
    });

    test('invalid duplicate batch is rejected before any RPC', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson());
      final repository = _repository(rpc: rpc);
      final duplicate = YorksV1PermissionChange.clear(
        assignmentId: _assignmentId,
      );

      await expectLater(
        repository.applyChanges(
          YorksV1ApplyPermissionChangesInput(
            targetAppUserId: 'usr-engineer',
            changes: [duplicate, duplicate],
            reason: 'Invalid duplicate command must never reach Postgres.',
            expectedRevision: 7,
            idempotencyKey: _idempotencyKey,
          ),
        ),
        throwsA(_domainError(YorksV1DomainErrorCode.invalidInput)),
      );
      expect(rpc.functionName, isNull);
    });

    test(
      'duplicate set target is rejected even with different project lists',
      () async {
        final rpc = _RecordingPermissionRpc(_workspaceJson());
        final repository = _repository(rpc: rpc);
        final secondProject = '44444444-4444-4444-8444-444444444444';

        await expectLater(
          repository.applyChanges(
            YorksV1ApplyPermissionChangesInput(
              targetAppUserId: 'usr-engineer',
              changes: [
                for (final projectId in [_projectId, secondProject])
                  YorksV1PermissionChange.set(
                    capabilityKey: YorksV1CapabilityKeys.projectsEdit,
                    effect: YorksV1PermissionAssignmentEffect.grant,
                    scope: YorksV1PermissionScope(
                      kind: YorksV1PermissionScopeKind.project,
                      projectIds: [projectId],
                    ),
                  ),
              ],
              reason: 'Duplicate set targets must be combined before review.',
              expectedRevision: 7,
              idempotencyKey: _idempotencyKey,
            ),
          ),
          throwsA(_domainError(YorksV1DomainErrorCode.invalidInput)),
        );
        expect(rpc.functionName, isNull);
      },
    );

    test('overlong audit reason is rejected before any RPC', () async {
      final rpc = _RecordingPermissionRpc(_workspaceJson());
      final repository = _repository(rpc: rpc);

      await expectLater(
        repository.clearAssignment(
          YorksV1ClearPermissionAssignmentInput(
            targetAppUserId: 'usr-engineer',
            assignmentId: _assignmentId,
            reason: List.filled(2001, 'a').join(),
            expectedRevision: 7,
            idempotencyKey: _idempotencyKey,
          ),
        ),
        throwsA(_domainError(YorksV1DomainErrorCode.invalidInput)),
      );
      expect(rpc.functionName, isNull);
    });

    test('missing backend and offline operation fail closed', () async {
      await expectLater(
        _repository(rpc: null).getCurrentSnapshot(),
        throwsA(_domainError(YorksV1DomainErrorCode.backendUnavailable)),
      );
      await expectLater(
        _repository(
          rpc: _RecordingPermissionRpc(_snapshotJson()),
          online: false,
        ).getCurrentSnapshot(),
        throwsA(_domainError(YorksV1DomainErrorCode.offline)),
      );
    });

    test('database statement cancellation is a recoverable outage', () async {
      final repository = _repository(
        rpc: _ThrowingPermissionRpc(
          const PostgrestException(
            message: 'canceling statement due to statement timeout',
            code: '57014',
          ),
        ),
      );

      await expectLater(
        repository.getCurrentSnapshot(),
        throwsA(_domainError(YorksV1DomainErrorCode.backendUnavailable)),
      );
    });

    test('older or malformed response fails closed', () async {
      final response = _snapshotJson();
      ((response['capabilities'] as List).single as Map).remove(
        'authoritative_effective',
      );
      await expectLater(
        _repository(
          rpc: _RecordingPermissionRpc(response),
        ).getCurrentSnapshot(),
        throwsA(_domainError(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    });

    test('workspace response for another target fails closed', () async {
      final response = _workspaceJson();
      (response['target']! as Map<String, dynamic>)['app_user_id'] =
          'usr-other';

      await expectLater(
        _repository(
          rpc: _RecordingPermissionRpc(response),
        ).getUserWorkspace(targetAppUserId: 'usr-engineer'),
        throwsA(_domainError(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    });

    test('history response for another target fails closed', () async {
      final response = <String, dynamic>{
        'schema_version': YorksV1PermissionSchema.current,
        'target_app_user_id': 'usr-other',
        'items': <Object?>[],
        'next_cursor': null,
      };

      await expectLater(
        _repository(rpc: _RecordingPermissionRpc(response)).listHistory(
          const YorksV1PermissionHistoryQuery(targetAppUserId: 'usr-engineer'),
        ),
        throwsA(_domainError(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    });
  });

  group('permission providers and controllers', () {
    test(
      'late Realtime join catches up without pausing confirmed actions',
      () async {
        final join = Completer<bool>();
        final pendingCatchup = Completer<YorksV1CurrentPermissionSnapshot>();
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) => join.future,
          safetyRefreshInterval: const Duration(hours: 1),
        );
        addTearDown(controller.dispose);
        final startup = controller.start();
        await _waitFor(() => controller.state.snapshot != null);
        expect(controller.state.isRevisionSignalHealthy, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);

        repository.nextSnapshot = () => pendingCatchup.future;
        join.complete(true);
        await _waitFor(() => repository.currentLoads == 2);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);

        pendingCatchup.complete(_snapshot(revision: 8));
        await startup;
        expect(controller.state.snapshot?.revision, 8);
      },
    );

    test(
      'retry rejoins revision signal without withdrawing confirmed write access',
      () async {
        var joins = 0;
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: _FakePermissionRepository(currentSnapshot: _snapshot()),
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async =>
                  ++joins > 1,
        );
        addTearDown(controller.dispose);
        await controller.start();
        expect(controller.state.isTrustedForWrites, isTrue);

        await controller.retryVerification();
        expect(joins, 2);
        expect(controller.state.isTrustedForWrites, isTrue);
      },
    );
    test(
      'unavailable revision signal keeps confirmed actions and polls',
      () async {
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async => false,
          safetyRefreshInterval: const Duration(milliseconds: 5),
        );

        await controller.start();

        expect(controller.state.snapshot?.revision, 7);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isRevisionSignalHealthy, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        expect(
          controller.state.domainErrorCode,
          YorksV1DomainErrorCode.backendUnavailable,
        );
        expect(
          controller.state.hybridAllows(
            YorksV1CapabilityKeys.projectsEdit,
            legacyAllowed: false,
            organizationSummary: true,
          ),
          isTrue,
        );

        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(repository.currentLoads, greaterThanOrEqualTo(2));
        controller.dispose();
      },
    );

    test(
      'safety polling recovers after both initial snapshot and signal fail',
      () async {
        final repository = _FakePermissionRepository(
          nextSnapshot: () async => _snapshot(revision: 8),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async => false,
          safetyRefreshInterval: const Duration(milliseconds: 5),
        );

        await controller.start();
        expect(repository.currentLoads, greaterThanOrEqualTo(1));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(controller.state.snapshot?.revision, 8);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isRevisionSignalHealthy, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        expect(repository.currentLoads, greaterThanOrEqualTo(2));
        controller.dispose();
      },
    );

    test(
      'cold launch retries a temporary permission outage promptly',
      () async {
        final repository = _FakePermissionRepository(
          nextSnapshot: () async => _snapshot(revision: 8),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async => false,
          safetyRefreshInterval: const Duration(hours: 1),
          verificationRetryInterval: const Duration(milliseconds: 5),
        );
        addTearDown(controller.dispose);
        await controller.start();

        await Future<void>.delayed(const Duration(milliseconds: 25));
        await _waitFor(() => controller.state.snapshot?.revision == 8);
        expect(repository.currentLoads, greaterThanOrEqualTo(2));
        expect(controller.state.isTrustedForWrites, isTrue);
        expect(controller.state.isRevisionSignalHealthy, isFalse);
      },
    );

    test('hybrid shadow mode preserves legacy and ignores candidates', () {
      final snapshot = YorksV1CurrentPermissionSnapshot.fromRpcJson(
        _snapshotJson(
          authorizationMode: 'shadow',
          capabilityMode: 'shadow',
          authoritativeEffective: false,
          candidateEffective: true,
          parity: false,
        ),
      );
      final state = YorksV1CurrentPermissionSnapshotState(
        snapshot: snapshot,
        isRevisionSignalHealthy: true,
      );

      expect(
        state.hybridAllows(
          YorksV1CapabilityKeys.projectsEdit,
          legacyAllowed: false,
          organizationSummary: true,
        ),
        isFalse,
      );
      expect(
        state.hybridAllows(
          YorksV1CapabilityKeys.projectsEdit,
          legacyAllowed: true,
          organizationSummary: true,
        ),
        isTrue,
      );
    });

    test('route decisions keep transient verification stable', () {
      const pending = YorksV1CurrentPermissionSnapshotState(
        isInitialLoading: true,
      );
      const unavailable = YorksV1CurrentPermissionSnapshotState(
        error: YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      );
      const offline = YorksV1CurrentPermissionSnapshotState(
        error: YorksV1DomainException(YorksV1DomainErrorCode.offline),
      );
      const unauthorized = YorksV1CurrentPermissionSnapshotState(
        error: YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
      );

      expect(
        pending.hybridRouteAllows(
          YorksV1CapabilityKeys.projectsView,
          legacyAllowed: true,
        ),
        isNull,
      );
      expect(
        unavailable.hybridRouteAllows(
          YorksV1CapabilityKeys.projectsView,
          legacyAllowed: true,
        ),
        isNull,
      );
      expect(
        offline.hybridRouteAllows(
          YorksV1CapabilityKeys.projectsView,
          legacyAllowed: true,
        ),
        isNull,
      );
      expect(
        unauthorized.hybridRouteAllows(
          YorksV1CapabilityKeys.projectsView,
          legacyAllowed: true,
        ),
        isFalse,
      );
    });

    test(
      'organization summary includes an allowed accessible project override',
      () {
        final response = _snapshotJson(
          authoritativeEffective: false,
          candidateEffective: false,
        );
        final capability =
            (response['capabilities'] as List).single as Map<String, dynamic>;
        capability['project_overrides'] = [
          {
            'assignment_id': _assignmentId,
            'project_id': _projectId,
            'project_ref': 'YRA-313',
            'project_name': 'Riyadh Substation',
            'effect': 'grant',
            'has_project_access': true,
            'authoritative_effective': true,
            'authoritative_source': 'explicit_grant',
            'candidate_effective': true,
            'candidate_source': 'explicit_grant',
            'parity': true,
            'effective_from': '2026-08-24T09:00:00Z',
            'effective_until': null,
          },
        ];
        final state = YorksV1CurrentPermissionSnapshotState(
          snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson(response),
          isRevisionSignalHealthy: true,
        );

        expect(
          state.hybridAllows(
            YorksV1CapabilityKeys.projectsEdit,
            legacyAllowed: false,
            organizationSummary: true,
          ),
          isTrue,
        );

        (response['project_access'] as List).clear();
        final inaccessible = YorksV1CurrentPermissionSnapshotState(
          snapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson(response),
          isRevisionSignalHealthy: true,
        );
        expect(
          inaccessible.hybridAllows(
            YorksV1CapabilityKeys.projectsEdit,
            legacyAllowed: false,
            organizationSummary: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'confirmed enforced read survives routine failure while writes pause',
      () {
        final state = YorksV1CurrentPermissionSnapshotState(
          snapshot: _snapshot(),
          isStale: true,
          isRevisionSignalHealthy: false,
          error: const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        );

        final decision = state.hybridDecision(
          YorksV1CapabilityKeys.projectsEdit,
          legacyAllowed: false,
          organizationSummary: true,
        );
        expect(decision.canRead, isTrue);
        expect(decision.canWrite, isFalse);

        const purged = YorksV1CurrentPermissionSnapshotState(
          error: YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
        );
        final denied = purged.hybridDecision(
          YorksV1CapabilityKeys.projectsEdit,
          legacyAllowed: true,
          organizationSummary: true,
        );
        expect(denied.canRead, isFalse);
        expect(denied.canWrite, isFalse);
      },
    );

    test(
      'routine refresh retains the confirmed snapshot without flicker',
      () async {
        final deferred = Completer<YorksV1CurrentPermissionSnapshot>();
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = _currentController(repository);
        await controller.start();
        expect(controller.state.hasConfirmedSnapshot, isTrue);
        expect(controller.state.isTrustedForWrites, isTrue);

        repository.nextSnapshot = () => deferred.future;
        final refresh = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.snapshot?.revision, 7);
        expect(controller.state.isRefreshing, isTrue);
        expect(controller.state.isTrustedForWrites, isTrue);

        deferred.complete(_snapshot(revision: 8));
        await refresh;
        expect(controller.state.snapshot?.revision, 8);
        expect(controller.state.isRefreshing, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        controller.dispose();
      },
    );

    test(
      'transient routine failure retains the trusted snapshot and writes',
      () async {
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = _currentController(repository);
        await controller.start();

        repository.nextSnapshot = () => throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
        await controller.refresh();

        expect(controller.state.snapshot?.revision, 7);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        expect(
          controller.state.domainErrorCode,
          YorksV1DomainErrorCode.backendUnavailable,
        );
        expect(
          controller.state.allows(
            YorksV1CapabilityKeys.projectsEdit,
            projectId: _projectId,
          ),
          isTrue,
        );
        controller.dispose();
      },
    );

    test('duplicate routine refreshes coalesce into one RPC', () async {
      final deferred = Completer<YorksV1CurrentPermissionSnapshot>();
      final repository = _FakePermissionRepository(
        currentSnapshot: _snapshot(),
      );
      final controller = _currentController(repository);
      await controller.start();
      expect(repository.currentLoads, 1);

      repository.nextSnapshot = () => deferred.future;
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = controller.refresh();
      await second;

      expect(repository.currentLoads, 2);
      expect(controller.state.isRefreshing, isTrue);
      expect(controller.state.isTrustedForWrites, isTrue);

      deferred.complete(_snapshot(revision: 8));
      await first;
      expect(repository.currentLoads, 2);
      expect(controller.state.snapshot?.revision, 8);
      controller.dispose();
    });

    test(
      'revision signal pauses writes until fresh authority arrives',
      () async {
        final deferred = Completer<YorksV1CurrentPermissionSnapshot>();
        late Future<void> Function() signal;
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async {
                signal = onSignal;
                return true;
              },
          safetyRefreshInterval: const Duration(hours: 1),
        );
        await controller.start();
        expect(controller.state.isTrustedForWrites, isTrue);

        repository.nextSnapshot = () => deferred.future;
        final refresh = signal();
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.snapshot?.revision, 7);
        expect(controller.state.isStale, isTrue);
        expect(controller.state.isTrustedForWrites, isFalse);

        deferred.complete(_snapshot(revision: 8));
        await refresh;
        expect(controller.state.snapshot?.revision, 8);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        controller.dispose();
      },
    );

    test('late failed refresh cannot overwrite a newer revision', () async {
      final oldRefresh = Completer<YorksV1CurrentPermissionSnapshot>();
      late Future<void> Function() signal;
      var laterLoads = 0;
      final repository = _FakePermissionRepository(
        currentSnapshot: _snapshot(),
      );
      final controller = YorksV1CurrentPermissionSnapshotController(
        enabled: true,
        authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        client: null,
        repository: repository,
        revisionSignalSubscription:
            ({required onSignal, required onUnavailable}) async {
              signal = onSignal;
              return true;
            },
        safetyRefreshInterval: const Duration(hours: 1),
      );
      addTearDown(controller.dispose);
      await controller.start();
      repository.nextSnapshot = () async {
        laterLoads++;
        return laterLoads == 1 ? oldRefresh.future : _snapshot(revision: 9);
      };

      final refresh = controller.refresh();
      await _waitFor(() => controller.state.isRefreshing);
      await signal();
      expect(controller.state.isStale, isTrue);
      oldRefresh.completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.backendUnavailable),
      );
      await refresh;

      expect(laterLoads, 2);
      expect(controller.state.snapshot?.revision, 9);
      expect(controller.state.error, isNull);
      expect(controller.state.isTrustedForWrites, isTrue);
    });

    test(
      'expired authorization purges a previously confirmed snapshot',
      () async {
        final controller = _currentController(
          _FakePermissionRepository(currentSnapshot: _snapshot()),
        );
        await controller.start();

        controller.invalidateForAuthorizationFailure(
          const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
        );

        expect(controller.state.snapshot, isNull);
        expect(controller.state.isTrustedForWrites, isFalse);
        expect(
          controller.state.domainErrorCode,
          YorksV1DomainErrorCode.unauthenticated,
        );
        controller.dispose();
      },
    );

    test(
      'revision signal loss retains confirmed actions without inventing revocation',
      () async {
        void Function(Object? error)? unavailable;
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: _FakePermissionRepository(currentSnapshot: _snapshot()),
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async {
                unavailable = onUnavailable;
                return true;
              },
          safetyRefreshInterval: const Duration(hours: 1),
        );
        await controller.start();

        unavailable!(StateError('channel closed'));

        expect(controller.state.snapshot?.revision, 7);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isRevisionSignalHealthy, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        controller.dispose();
      },
    );

    test(
      'reconnect and foreground refresh keep the last confirmed action',
      () async {
        var now = DateTime.utc(2026, 8, 24, 9);
        late void Function(Object? error) unavailable;
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: repository,
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async {
                unavailable = onUnavailable;
                return true;
              },
          safetyRefreshInterval: const Duration(hours: 1),
          now: () => now,
        );
        addTearDown(controller.dispose);
        await controller.start();
        unavailable(StateError('mobile radio switched networks'));

        final pending = Completer<YorksV1CurrentPermissionSnapshot>();
        repository.nextSnapshot = () => pending.future;
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        now = now.add(const Duration(minutes: 3));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _waitFor(() => repository.currentLoads == 2);

        expect(controller.state.isRefreshing, isTrue);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        pending.completeError(
          const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
        await _waitFor(() => !controller.state.isRefreshing);
        expect(controller.state.isTrustedForWrites, isTrue);
        expect(controller.state.snapshot?.revision, 7);
      },
    );

    test(
      'late permission response cannot restore a signed-out actor',
      () async {
        final pending = Completer<YorksV1CurrentPermissionSnapshot>();
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = _currentController(repository);
        addTearDown(controller.dispose);
        await controller.start();

        repository.nextSnapshot = () => pending.future;
        final refresh = controller.refresh();
        await _waitFor(() => controller.state.isRefreshing);
        controller.invalidateForAuthorizationFailure(
          const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
        );
        pending.complete(_snapshot(revision: 8));
        await refresh;

        expect(controller.state.snapshot, isNull);
        expect(controller.state.isTrustedForWrites, isFalse);
        expect(
          controller.state.domainErrorCode,
          YorksV1DomainErrorCode.unauthenticated,
        );
      },
    );

    test('short foreground gap does not repeat the permission RPC', () async {
      var now = DateTime.utc(2026, 8, 24, 9);
      final repository = _FakePermissionRepository(
        currentSnapshot: _snapshot(),
      );
      final controller = _currentController(repository, now: () => now);
      await controller.start();
      expect(repository.currentLoads, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 20));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(repository.currentLoads, 1);
      expect(controller.state.isTrustedForWrites, isTrue);
      controller.dispose();
    });

    test(
      'long foreground gap performs one authoritative safety refresh',
      () async {
        var now = DateTime.utc(2026, 8, 24, 9);
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = _currentController(repository, now: () => now);
        await controller.start();
        expect(repository.currentLoads, 1);

        repository.nextSnapshot = () async => _snapshot(revision: 8);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        now = now.add(const Duration(minutes: 3));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _waitFor(() => repository.currentLoads >= 2);

        expect(controller.state.snapshot?.revision, 8);
        expect(repository.currentLoads, 2);
        controller.dispose();
      },
    );

    test(
      'mobile resume retains actions while safety refresh is in flight',
      () async {
        var now = DateTime.utc(2026, 8, 24, 9);
        final pending = Completer<YorksV1CurrentPermissionSnapshot>();
        final repository = _FakePermissionRepository(
          currentSnapshot: _snapshot(),
        );
        final controller = _currentController(repository, now: () => now);
        await controller.start();

        repository.nextSnapshot = () => pending.future;
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        now = now.add(const Duration(minutes: 3));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _waitFor(() => repository.currentLoads >= 2);

        expect(controller.state.isRefreshing, isTrue);
        expect(controller.state.isStale, isFalse);
        expect(controller.state.isTrustedForWrites, isTrue);
        pending.complete(_snapshot(revision: 8));
        await _waitFor(() => controller.state.snapshot?.revision == 8);
        expect(controller.state.isTrustedForWrites, isTrue);
        controller.dispose();
      },
    );

    test('future assignment boundary triggers an exact refresh', () async {
      final repository = _FakePermissionRepository(
        currentSnapshot: YorksV1CurrentPermissionSnapshot.fromRpcJson(
          _snapshotJson(nextTransitionAt: '2026-08-24T09:00:00.020Z'),
        ),
      );
      final controller = _currentController(repository);
      await controller.start();

      repository.nextSnapshot = () async => _snapshot(revision: 8);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(repository.currentLoads, greaterThanOrEqualTo(2));
      expect(controller.state.snapshot?.revision, 8);
      controller.dispose();
    });

    test(
      'batch controller never applies an optimistic privilege result',
      () async {
        SharedPreferences.setMockInitialValues({});
        final completion = Completer<YorksV1UserPermissionWorkspace>();
        final repository = _FakePermissionRepository(
          workspace: _workspace(),
          applyResult: () => completion.future,
        );
        final controller = YorksV1UserPermissionWorkspaceController(
          repository: repository,
          targetAppUserId: 'usr-engineer',
          commandKeys: YorksV1CriticalCommandKeyStore(
            preferences: await SharedPreferences.getInstance(),
            actorAuthUserId: 'actor-auth-id',
          ),
        );
        await controller.load();
        final pending = controller.applyChanges(
          changes: [
            YorksV1PermissionChange.set(
              capabilityKey: YorksV1CapabilityKeys.projectsEdit,
              effect: YorksV1PermissionAssignmentEffect.grant,
              scope: YorksV1PermissionScope(
                kind: YorksV1PermissionScopeKind.project,
                projectIds: const [_projectId],
              ),
            ),
          ],
          reason: 'Grant only the reviewed project scope.',
          expectedRevision: 7,
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.isSaving, isTrue);
        expect(controller.state.workspace?.revision, 7);
        expect(repository.lastApplyInput?.idempotencyKey, _isUuid);

        completion.complete(_workspace(revision: 8));
        expect(await pending, isTrue);
        expect(controller.state.workspace?.revision, 8);
        expect(controller.state.isSaving, isFalse);
        controller.dispose();
      },
    );

    test(
      'conflict reloads latest server workspace and preserves error',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = _FakePermissionRepository(
          workspace: _workspace(),
          applyResult: () => throw const YorksV1DomainException(
            YorksV1DomainErrorCode.conflict,
          ),
        );
        final controller = YorksV1UserPermissionWorkspaceController(
          repository: repository,
          targetAppUserId: 'usr-engineer',
          commandKeys: YorksV1CriticalCommandKeyStore(
            preferences: await SharedPreferences.getInstance(),
            actorAuthUserId: 'actor-auth-id',
          ),
        );
        await controller.load();
        repository.workspace = _workspace(revision: 9);

        final saved = await controller.applyChanges(
          changes: [YorksV1PermissionChange.clear(assignmentId: _assignmentId)],
          reason: 'Remove the reviewed exception.',
          expectedRevision: 7,
        );

        expect(saved, isFalse);
        expect(controller.state.workspace?.revision, 9);
        expect(controller.state.isConflict, isTrue);
        controller.dispose();
      },
    );

    test(
      'stale current authority blocks workspace mutation attempts',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = _FakePermissionRepository(workspace: _workspace());
        final controller = YorksV1UserPermissionWorkspaceController(
          repository: repository,
          targetAppUserId: 'usr-engineer',
          commandKeys: YorksV1CriticalCommandKeyStore(
            preferences: await SharedPreferences.getInstance(),
            actorAuthUserId: 'actor-auth-id',
          ),
          canIssueCommands: () => false,
        );
        await controller.load();

        final saved = await controller.applyChanges(
          changes: [YorksV1PermissionChange.clear(assignmentId: _assignmentId)],
          reason: 'This command must remain blocked while authority is stale.',
          expectedRevision: 7,
        );

        expect(saved, isFalse);
        expect(repository.lastApplyInput, isNull);
        expect(
          controller.state.domainErrorCode,
          YorksV1DomainErrorCode.backendUnavailable,
        );
        controller.dispose();
      },
    );
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 20 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

const _projectId = '11111111-1111-4111-8111-111111111111';
const _assignmentId = '22222222-2222-4222-8222-222222222222';
const _idempotencyKey = '33333333-3333-4333-8333-333333333333';

final _isUuid = matches(
  RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ),
);

Matcher _domainError(YorksV1DomainErrorCode code) =>
    isA<YorksV1DomainException>().having((error) => error.code, 'code', code);

YorksV1SupabasePermissionRepository _repository({
  required YorksV1PermissionRpcClient? rpc,
  bool online = true,
}) => YorksV1SupabasePermissionRepository(
  featureFlags: const YorksV1FeatureFlags(foundation: true),
  connectivity: DefaultConnectivity(online: online),
  rpcClient: rpc,
);

Map<String, dynamic> _capabilityJson({
  String capabilityMode = 'enforced',
  bool authoritativeEffective = true,
  bool candidateEffective = true,
  bool parity = true,
}) => {
  'capability_key': YorksV1CapabilityKeys.projectsEdit,
  'module_key': 'projects',
  'action_key': 'edit',
  'label': 'Edit projects',
  'description': 'Edit an authorized project through versioned commands.',
  'risk_level': 'high',
  'allowed_scope_kinds': ['organization', 'project'],
  'requires_project_access': true,
  'dependencies': ['projects.view'],
  'runtime_status': 'operational',
  'is_assignable': true,
  'display_order': 13,
  'authorization_mode': capabilityMode,
  'role_default': true,
  'organization_summary_visible': true,
  'authoritative_effective': authoritativeEffective,
  'authoritative_source': 'role_default',
  'candidate_effective': candidateEffective,
  'candidate_source': candidateEffective == authoritativeEffective
      ? 'role_default'
      : 'explicit_grant',
  'parity': parity,
  'actor_can_delegate': true,
  'actor_delegable_scope_kinds': ['organization'],
  'project_overrides': [
    {
      'assignment_id': null,
      'project_id': _projectId,
      'project_ref': 'YRA-313',
      'project_name': 'Riyadh Substation',
      'effect': null,
      'has_project_access': true,
      'authoritative_effective': authoritativeEffective,
      'authoritative_source': 'role_default',
      'candidate_effective': candidateEffective,
      'candidate_source': candidateEffective == authoritativeEffective
          ? 'role_default'
          : 'explicit_grant',
      'parity': parity,
      'effective_from': null,
      'effective_until': null,
    },
  ],
};

Map<String, dynamic> _snapshotJson({
  int revision = 7,
  String authorizationMode = 'enforced',
  String capabilityMode = 'enforced',
  bool authoritativeEffective = true,
  bool candidateEffective = true,
  bool parity = true,
  String? nextTransitionAt,
}) => {
  'schema_version': 1,
  'authorization_mode': authorizationMode,
  'generated_at': '2026-08-24T09:00:00Z',
  'next_transition_at': nextTransitionAt,
  'user': {
    'app_user_id': 'usr-engineer',
    'display_name': 'Project Engineer',
    'exact_role': 'project_engineer',
    'is_active': true,
  },
  'revision': revision,
  'capabilities': [
    _capabilityJson(
      capabilityMode: capabilityMode,
      authoritativeEffective: authoritativeEffective,
      candidateEffective: candidateEffective,
      parity: parity,
    ),
  ],
  'project_access': [
    {
      'project_id': _projectId,
      'project_ref': 'YRA-313',
      'project_name': 'Riyadh Substation',
      'state': 'active',
      'has_access': true,
    },
  ],
};

Map<String, dynamic> _workspaceJson({int revision = 7}) => {
  'schema_version': 1,
  'authorization_mode': 'shadow',
  'generated_at': '2026-08-24T09:00:00Z',
  'actor': {
    'actor_kind': 'user',
    'app_user_id': 'usr-admin',
    'display_name': 'Owner',
    'exact_role': 'admin',
  },
  'target': {
    'app_user_id': 'usr-engineer',
    'display_name': 'Project Engineer',
    'exact_role': 'project_engineer',
    'is_active': true,
  },
  'revision': revision,
  'catalog': [_capabilityJson(capabilityMode: 'shadow')],
  'assignments': <Object?>[],
  'projects': [
    {
      'project_id': _projectId,
      'project_ref': 'YRA-313',
      'project_name': 'Riyadh Substation',
      'state': 'active',
      'has_access': true,
    },
  ],
  'recent_history': <Object?>[],
};

YorksV1CurrentPermissionSnapshot _snapshot({int revision = 7}) =>
    YorksV1CurrentPermissionSnapshot.fromRpcJson(
      _snapshotJson(revision: revision),
    );

YorksV1UserPermissionWorkspace _workspace({int revision = 7}) =>
    YorksV1UserPermissionWorkspace.fromRpcJson(
      _workspaceJson(revision: revision),
    );

class _RecordingPermissionRpc implements YorksV1PermissionRpcClient {
  _RecordingPermissionRpc(this.response);

  final Object? response;
  String? functionName;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.functionName = functionName;
    this.parameters = parameters;
    return response;
  }
}

class _ThrowingPermissionRpc implements YorksV1PermissionRpcClient {
  const _ThrowingPermissionRpc(this.error);

  final Object error;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) => Future<Object?>.error(error);
}

class _FakePermissionRepository implements YorksV1PermissionRepository {
  _FakePermissionRepository({
    this.currentSnapshot,
    this.nextSnapshot,
    this.workspace,
    this.applyResult,
  });

  YorksV1CurrentPermissionSnapshot? currentSnapshot;
  Future<YorksV1CurrentPermissionSnapshot> Function()? nextSnapshot;
  YorksV1UserPermissionWorkspace? workspace;
  Future<YorksV1UserPermissionWorkspace> Function()? applyResult;
  YorksV1ApplyPermissionChangesInput? lastApplyInput;
  var currentLoads = 0;

  @override
  Future<YorksV1CurrentPermissionSnapshot> getCurrentSnapshot() async {
    currentLoads++;
    if (currentLoads > 1 && nextSnapshot != null) return nextSnapshot!();
    return currentSnapshot!;
  }

  @override
  Future<YorksV1UserAdminOptions> getUserAdminOptions({
    String? targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> getUserWorkspace({
    required String targetAppUserId,
  }) async => workspace!;

  @override
  Future<YorksV1UserPermissionWorkspace> applyChanges(
    YorksV1ApplyPermissionChangesInput input,
  ) async {
    lastApplyInput = input;
    return applyResult == null ? workspace! : applyResult!();
  }

  @override
  Future<YorksV1UserPermissionWorkspace> setAssignment(
    YorksV1SetPermissionAssignmentInput input,
  ) async => workspace!;

  @override
  Future<YorksV1UserPermissionWorkspace> clearAssignment(
    YorksV1ClearPermissionAssignmentInput input,
  ) async => workspace!;

  @override
  Future<YorksV1PermissionHistoryPage> listHistory(
    YorksV1PermissionHistoryQuery query,
  ) => throw UnimplementedError();
}

YorksV1CurrentPermissionSnapshotController _currentController(
  YorksV1PermissionRepository repository, {
  DateTime Function()? now,
}) => YorksV1CurrentPermissionSnapshotController(
  enabled: true,
  authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  client: null,
  repository: repository,
  revisionSignalSubscription:
      ({required onSignal, required onUnavailable}) async => true,
  safetyRefreshInterval: const Duration(hours: 1),
  now: now,
);

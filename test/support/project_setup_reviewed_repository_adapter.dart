import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';

/// Test/demo fixtures retain the typed repository while exercising the exact
/// journal seam. Connected builds use the production raw reviewed RPC method.
class ProjectSetupReviewedRepositoryAdapter
    implements YorksV1ProjectReviewedCommandRepository {
  const ProjectSetupReviewedRepositoryAdapter(this.repository);
  final YorksV1ProjectRepository repository;

  @override
  Future<Map<String, dynamic>> executeReviewedCommand(
    YorksV1ProjectSetupCommand command,
  ) async {
    final payload = command.payload;
    switch (command.kind) {
      case YorksV1ProjectSetupCommandKind.create:
        final input = _creation(payload, command.idempotencyKey);
        _exact(command, input.toRpcPayload());
        final result = await repository.createProject(input);
        return {
          'project': projectSetupProjectJson(result.project),
          'scopes': [
            for (final scope in result.scopes)
              {
                'id': scope.id,
                'project_id': scope.projectId,
                'scope_kind': scope.kind.wireValue,
                'code': scope.code,
                'name': scope.name,
                'is_active': scope.active,
                'floors_levels': scope.floorsOrLevels,
                'flags': {...scope.flags, 'has_frp_room': scope.hasFrpRoom},
                'delivery_address': scope.deliveryAddress,
              },
          ],
          'members': [
            for (final member in result.members)
              {
                'id': member.id,
                'project_id': member.projectId,
                'member_auth_user_id': member.memberAuthUserId,
                'project_role': member.projectRole.wireValue,
                'effective_from': member.effectiveFrom.toIso8601String(),
                'effective_to': member.effectiveTo?.toIso8601String(),
                'created_at': member.createdAt.toIso8601String(),
              },
          ],
          'idempotency_key': command.idempotencyKey,
        };
      case YorksV1ProjectSetupCommandKind.update:
        final input = YorksV1ProjectUpdateInput(
          idempotencyKey: command.idempotencyKey,
          projectId: payload['project_id'] as String,
          expectedProjectVersion: payload['expected_version'] as int,
          project: _creation(payload, command.idempotencyKey),
        );
        _exact(command, input.toRpcPayload());
        return {
          'project': projectSetupProjectJson(
            await repository.updateProject(input),
          ),
        };
      case YorksV1ProjectSetupCommandKind.activate:
        final input = YorksV1SetProjectStateInput(
          idempotencyKey: command.idempotencyKey,
          projectId: payload['project_id'] as String,
          expectedProjectVersion: payload['expected_version'] as int,
          currentState: YorksV1ProjectLifecycle.draft,
          targetState: YorksV1ProjectLifecycle.fromWireValue(payload['state'])!,
          reason: payload['reason'] as String?,
        );
        _exact(command, input.toRpcPayload());
        return {
          'project': projectSetupProjectJson(
            await repository.setProjectState(input),
          ),
        };
    }
  }

  YorksV1ProjectCreationInput _creation(
    Map<String, dynamic> payload,
    String key,
  ) {
    final parties = Map<String, dynamic>.from(payload['parties'] as Map);
    final client = parties['client'] is Map
        ? Map<String, dynamic>.from(parties['client'] as Map)
        : const <String, dynamic>{};
    final input = YorksV1ProjectCreationInput(
      idempotencyKey: key,
      reference: payload['project_ref'] as String,
      name: payload['name'] as String,
      clientName: client['name'] as String?,
      clientContactName: client['contact_name'] as String?,
      clientContactPhone: client['contact_phone'] as String?,
      clientContactEmail: client['contact_email'] as String?,
      clientAddress: client['address'] as String?,
      jobOrContractReference: payload['job_contract_reference'] as String?,
      siteLocation: payload['project_site'] as String?,
      startDate: payload['start_date'] == null
          ? null
          : DateTime.parse(payload['start_date'] as String),
      endDate: payload['target_completion_date'] == null
          ? null
          : DateTime.parse(payload['target_completion_date'] as String),
      notes: payload['notes'] as String?,
      parties: [
        for (final kind in YorksV1ProjectPartyKind.values)
          if (kind != YorksV1ProjectPartyKind.client &&
              parties[kind.wireValue] is Map)
            YorksV1ProjectPartyInput.fromDraftJson({
              'kind': kind.wireValue,
              ...Map<String, dynamic>.from(parties[kind.wireValue] as Map),
            }),
        for (final group in const {
          'subcontractors': YorksV1ProjectPartyKind.subcontractor,
          'other_contractors': YorksV1ProjectPartyKind.otherContractor,
        }.entries)
          for (final party in (parties[group.key] as List?) ?? const [])
            YorksV1ProjectPartyInput.fromDraftJson({
              'kind': group.value.wireValue,
              ...Map<String, dynamic>.from(party as Map),
            }),
      ],
      initialMembers: [
        for (final member in (payload['initial_members'] as List?) ?? const [])
          YorksV1InitialProjectMemberInput.fromDraftJson(
            Map<String, dynamic>.from(member as Map),
          ),
      ],
      buildings: [
        for (final building in payload['buildings'] as List)
          YorksV1ProjectBuildingInput.fromDraftJson(
            Map<String, dynamic>.from(building as Map),
          ),
      ],
      attachments: [
        for (final attachment in (payload['attachments'] as List?) ?? const [])
          YorksV1ProjectAttachmentInput.fromDraftJson(
            Map<String, dynamic>.from(attachment as Map),
          ),
      ],
    );
    return input;
  }

  void _exact(
    YorksV1ProjectSetupCommand command,
    Map<String, dynamic> rebuilt,
  ) {
    if (command.canonicalPayload != yorksV1CanonicalSetupJson(rebuilt)) {
      throw StateError('Test fixture changed reviewed input');
    }
  }
}

Map<String, dynamic> projectSetupProjectJson(YorksV1Project project) => {
  'id': project.id,
  'reference': project.reference,
  'name': project.name,
  'state': project.state.wireValue,
  'record_version': project.recordVersion,
  'created_at': project.createdAt.toIso8601String(),
  'updated_at': project.updatedAt.toIso8601String(),
  'client_name': project.clientName,
  'job_contract_reference': project.jobOrContractReference,
  'project_site': project.siteLocation,
  'client_contact_name': project.clientContactName,
  'client_contact_phone': project.clientContactPhone,
  'city': project.city,
  'country_code': project.countryCode,
  'start_date': project.startDate?.toIso8601String(),
  'target_completion_date': project.endDate?.toIso8601String(),
  'notes': project.notes,
  'current_action_owner_profile_id': project.currentActionOwnerProfileId,
  'current_action_owner_role': project.currentActionOwnerRole,
  'current_action_code': project.currentActionCode,
  'created_by_auth_user_id': project.createdByAuthUserId,
};

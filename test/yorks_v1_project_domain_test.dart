import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_project_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Yorks V1 role claims', () {
    test('accepts only the ten exact server-controlled role claims', () {
      expect(
        YorksV1Role.fromServerClaim('project_engineer'),
        YorksV1Role.projectEngineer,
      );
      expect(
        YorksV1Role.fromServerClaim('site_engineer'),
        YorksV1Role.siteEngineer,
      );
      expect(
        YorksV1Role.fromServerClaim('senior_mechanical_engineer'),
        YorksV1Role.seniorMechanicalEngineer,
      );
      expect(YorksV1Role.fromServerClaim('pr'), YorksV1Role.pr);
      expect(YorksV1Role.pr.canConfigureUsers, isTrue);
      expect(YorksV1Role.pr.isEngineering, isFalse);
      expect(YorksV1Role.pr.canCreateProject, isFalse);
      expect(YorksV1Role.pr.canCreateMaterialRequest, isFalse);
      expect(YorksV1Role.pr.canBrowseInventory, isFalse);
      expect(
        YorksV1Role.fromServerClaim('project_manager'),
        YorksV1Role.projectManager,
      );
      expect(
        YorksV1Role.fromServerClaim('workshop_in_charge'),
        YorksV1Role.workshopInCharge,
      );
      expect(
        YorksV1Role.fromServerClaim('document_controller'),
        YorksV1Role.documentController,
      );
      expect(YorksV1Role.fromServerClaim('accountant'), YorksV1Role.accountant);
      expect(
        YorksV1Role.fromServerClaim('procurement'),
        YorksV1Role.procurement,
      );
      expect(YorksV1Role.fromServerClaim('admin'), YorksV1Role.admin);
      expect(
        YorksV1Role.seniorMechanicalEngineer.isGlobalProjectEngineer,
        isTrue,
      );
      expect(YorksV1Role.projectManager.isGlobalProjectEngineer, isTrue);
      expect(YorksV1Role.workshopInCharge.isGlobalProjectEngineer, isTrue);
      expect(YorksV1Role.documentController.isGlobalProjectEngineer, isTrue);
      expect(YorksV1Role.seniorMechanicalEngineer.isEngineering, isTrue);
      expect(YorksV1Role.seniorMechanicalEngineer.canBrowseInventory, isTrue);
      expect(YorksV1Role.seniorMechanicalEngineer.canManageInventory, isFalse);
      expect(YorksV1Role.accountant.isEngineering, isFalse);
      expect(YorksV1Role.accountant.isGlobalProjectEngineer, isFalse);
      expect(YorksV1Role.accountant.canCreateProject, isFalse);
      expect(YorksV1Role.accountant.canCreateMaterialRequest, isFalse);
      expect(YorksV1Role.accountant.canCreateMaterialReturn, isFalse);
      expect(YorksV1Role.accountant.canManageProjectMembers, isFalse);
      expect(YorksV1Role.accountant.canSetProjectState, isFalse);
      expect(YorksV1Role.accountant.canConfigureUsers, isFalse);
      expect(YorksV1Role.accountant.canBrowseInventory, isFalse);
      expect(YorksV1Role.accountant.canManageInventory, isFalse);
    });

    test('never promotes a legacy Engineer claim automatically', () {
      expect(YorksV1Role.fromServerClaim('engineer'), isNull);
      expect(YorksV1Role.fromServerClaim('Engineer'), isNull);
      expect(YorksV1Role.fromServerClaim(' project_engineer '), isNull);
      expect(YorksV1Role.fromServerClaim(null), isNull);
    });
  });

  group('Yorks V1 project lifecycle and memberships', () {
    test('permits only the frozen lifecycle transitions', () {
      expect(
        YorksV1ProjectLifecycle.draft.canTransitionTo(
          YorksV1ProjectLifecycle.active,
        ),
        isTrue,
      );
      expect(
        YorksV1ProjectLifecycle.draft.canTransitionTo(
          YorksV1ProjectLifecycle.completed,
        ),
        isFalse,
      );
      expect(
        YorksV1ProjectLifecycle.active.canTransitionTo(
          YorksV1ProjectLifecycle.onHold,
        ),
        isTrue,
      );
      expect(
        YorksV1ProjectLifecycle.onHold.canTransitionTo(
          YorksV1ProjectLifecycle.active,
        ),
        isTrue,
      );
      expect(
        YorksV1ProjectLifecycle.completed.canTransitionTo(
          YorksV1ProjectLifecycle.archived,
        ),
        isTrue,
      );
      expect(
        YorksV1ProjectLifecycle.archived.canTransitionTo(
          YorksV1ProjectLifecycle.active,
        ),
        isFalse,
      );
      expect(
        YorksV1ProjectLifecycle.active.requiresReasonFor(
          YorksV1ProjectLifecycle.onHold,
        ),
        isTrue,
      );
      expect(
        YorksV1ProjectLifecycle.active.requiresReasonFor(
          YorksV1ProjectLifecycle.completed,
        ),
        isFalse,
      );
    });

    test('Common scope is explicit and membership revocation is dated', () {
      final scope = YorksV1ProjectScope.fromRpcJson({
        'id': 'scope-common',
        'project_id': 'project-1',
        'scope_kind': 'common',
        'scope_code': 'COMMON',
        'name': 'Common',
        'is_active': true,
      });
      final member = YorksV1ProjectMember(
        id: 'member-1',
        projectId: 'project-1',
        memberAuthUserId: 'auth-site',
        projectRole: YorksV1ProjectMembershipRole.siteEngineer,
        effectiveFrom: DateTime.utc(2026, 8, 1),
        effectiveTo: DateTime.utc(2026, 8, 15),
        createdAt: DateTime.utc(2026, 8, 1),
        reason: 'assignment',
      );

      expect(scope.isCommon, isTrue);
      expect(scope.isImmutable, isTrue);
      expect(member.isActiveAt(DateTime.utc(2026, 8, 14, 23, 59)), isTrue);
      expect(member.isActiveAt(DateTime.utc(2026, 8, 15)), isFalse);
      expect(member.isActiveAt(DateTime.utc(2026, 7, 31, 23, 59)), isFalse);
    });

    test('retains the authoritative membership revocation projection', () {
      final member = YorksV1ProjectMember.fromRpcJson({
        'id': 'member-1',
        'project_id': 'project-1',
        'auth_user_id': 'auth-site',
        'display_name': 'Site Engineer',
        'project_role': 'site_engineer',
        'effective_from': '2026-08-01T00:00:00.000Z',
        'effective_to': '2026-08-15T12:30:00.000Z',
        'created_at': '2026-08-01T00:00:00.000Z',
        'reason': 'Initial site assignment',
        'assigned_by_auth_user_id': 'auth-project-engineer',
        'assigned_by_role': 'project_engineer',
        'revoked_by_auth_user_id': 'auth-project-engineer',
        'revoked_by_role': 'project_engineer',
        'revoked_reason': 'Access no longer required',
      });

      expect(member.displayName, 'Site Engineer');
      expect(member.effectiveTo, DateTime.utc(2026, 8, 15, 12, 30));
      expect(member.revokedByAuthUserId, 'auth-project-engineer');
      expect(member.revokedByRole, 'project_engineer');
      expect(member.revokedReason, 'Access no longer required');
    });

    test('keeps a database date value on its selected calendar day', () {
      final project = YorksV1Project.fromRpcJson({
        ..._projectJson(),
        'start_date': '2026-08-01',
        'target_completion_date': '2026-08-31',
      });

      expect(project.startDate, DateTime(2026, 8, 1));
      expect(project.endDate, DateTime(2026, 8, 31));
    });
  });

  group('Yorks V1 creation input', () {
    test('maps all approved five-stage fields to the exact RPC payload', () {
      final input = _validCreationInput();

      expect(input.validate(), isEmpty);
      expect(input.toRpcPayload(), {
        'project_ref': 'YRK-100',
        'name': 'Cooling Upgrade',
        'job_contract_reference': 'JOB-7',
        'project_site': 'Abu Dhabi',
        'start_date': '2026-08-01',
        'target_completion_date': '2026-10-01',
        'notes': 'Phase one',
        'parties': {
          'client': {
            'name': 'Client LLC',
            'contact_name': 'Client Contact',
            'contact_phone': '+9710000000',
            'contact_email': 'client@example.test',
            'address': 'Client address',
          },
          'consultant': {
            'name': 'Consultant LLC',
            'contact_name': null,
            'contact_phone': null,
            'contact_email': null,
            'address': null,
          },
          'main_contractor': {
            'name': 'Main Contractor LLC',
            'contact_name': null,
            'contact_phone': null,
            'contact_email': null,
            'address': null,
          },
          'subcontractors': [
            {
              'name': 'Duct Works LLC',
              'contact_name': null,
              'contact_phone': null,
              'contact_email': null,
              'address': null,
            },
          ],
          'other_contractors': [
            {
              'name': 'Civil Works LLC',
              'contact_name': null,
              'contact_phone': null,
              'contact_email': null,
              'address': null,
            },
          ],
        },
        'initial_members': [
          {
            'auth_user_id': 'auth-project-engineer',
            'project_role': 'project_engineer',
            'reason': 'initial_team',
          },
          {
            'auth_user_id': 'auth-site-engineer',
            'project_role': 'site_engineer',
            'reason': 'initial_team',
          },
        ],
        'buildings': [
          {
            'code': 'A01',
            'name': 'Tower A',
            'floors_levels': ['GF', 'Roof'],
            'flags': {'has_frp_room': true, 'requires_access_badge': true},
            'delivery_address': 'Tower A loading bay',
          },
        ],
        'attachments': [
          {
            'file_name': 'approved-drawing.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 42,
          },
        ],
      });
      expect(input.toRpcPayload().containsKey('actor_id'), isFalse);
      expect(input.toRpcPayload().containsKey('actor_role'), isFalse);
      expect(input.toRpcPayload().containsKey('state'), isFalse);
    });

    test('reports structural validation codes without presentation copy', () {
      final invalid = YorksV1ProjectCreationInput(
        idempotencyKey: '',
        reference: '',
        name: '',
        startDate: DateTime.utc(2026, 8, 2),
        endDate: DateTime.utc(2026, 8, 1),
        parties: const [
          YorksV1ProjectPartyInput(
            kind: YorksV1ProjectPartyKind.client,
            name: '',
          ),
          YorksV1ProjectPartyInput(
            kind: YorksV1ProjectPartyKind.client,
            name: 'Duplicate',
          ),
        ],
        initialMembers: const [
          YorksV1InitialProjectMemberInput(
            authUserId: 'auth-1',
            projectRole: YorksV1ProjectMembershipRole.siteEngineer,
          ),
          YorksV1InitialProjectMemberInput(
            authUserId: 'auth-1',
            projectRole: YorksV1ProjectMembershipRole.projectEngineer,
          ),
        ],
        buildings: const [
          YorksV1ProjectBuildingInput(name: 'A', code: 'B1'),
          YorksV1ProjectBuildingInput(name: 'B', code: 'b1'),
        ],
        attachments: const [YorksV1ProjectAttachmentInput(fileName: '')],
      );

      expect(invalid.validate(), {
        YorksV1ProjectValidationCode.missingIdempotencyKey,
        YorksV1ProjectValidationCode.missingProjectReference,
        YorksV1ProjectValidationCode.missingProjectName,
        YorksV1ProjectValidationCode.invalidDateRange,
        YorksV1ProjectValidationCode.duplicateBuildingCode,
        YorksV1ProjectValidationCode.duplicateMember,
        YorksV1ProjectValidationCode.invalidProjectParty,
        YorksV1ProjectValidationCode.duplicateProjectParty,
        YorksV1ProjectValidationCode.invalidAttachment,
      });
    });

    test('rejects accidental century-scale project dates', () {
      final referenceDate = DateTime(2026, 8, 5);
      expect(
        yorksV1ProjectDateIsSupported(
          DateTime(1976, 8, 5),
          referenceDate: referenceDate,
        ),
        isTrue,
      );
      expect(
        yorksV1ProjectDateIsSupported(
          DateTime(2077, 8, 5),
          referenceDate: referenceDate,
        ),
        isFalse,
      );

      final invalid = YorksV1ProjectCreationInput(
        idempotencyKey: 'date-window',
        reference: 'YRK-DATE-100',
        name: 'Date window test',
        startDate: DateTime(DateTime.now().year + 51, 1, 1),
        buildings: const [YorksV1ProjectBuildingInput(name: 'Building A')],
      );
      expect(
        invalid.validate(),
        contains(YorksV1ProjectValidationCode.unsupportedProjectDate),
      );
    });

    test(
      'applies the Site Engineer creation-time membership exception only',
      () {
        final input = _validCreationInput();
        expect(
          input.initialMembersAllowedFor(YorksV1Role.projectEngineer),
          isTrue,
        );
        expect(input.initialMembersAllowedFor(YorksV1Role.admin), isTrue);
        expect(
          input.initialMembersAllowedFor(YorksV1Role.siteEngineer),
          isFalse,
        );
        expect(
          const YorksV1ProjectCreationInput(
            idempotencyKey: 'site-create',
            reference: 'YRK-101',
            name: 'Site-created project',
            buildings: [YorksV1ProjectBuildingInput(name: 'A')],
            initialMembers: [
              YorksV1InitialProjectMemberInput(
                authUserId: 'auth-project-engineer',
                projectRole: YorksV1ProjectMembershipRole.projectEngineer,
              ),
            ],
          ).initialMembersAllowedFor(YorksV1Role.siteEngineer),
          isTrue,
        );
      },
    );

    test('uses the exact membership and state command payload keys', () {
      expect(_memberAssignmentInput().validate(), isEmpty);
      expect(_memberAssignmentInput().toRpcPayload(), {
        'project_id': 'project-1',
        'member_auth_user_id': 'auth-member',
        'project_role': 'site_engineer',
        'expected_version': 1,
        'reason': 'team_change',
      });

      expect(_memberRevocationInput().validate(), isEmpty);
      expect(_memberRevocationInput().toRpcPayload(), {
        'project_id': 'project-1',
        'member_auth_user_id': 'auth-member',
        'project_role': 'site_engineer',
        'expected_version': 2,
        'reason': 'access_removed',
      });

      const stateChange = YorksV1SetProjectStateInput(
        idempotencyKey: 'command-state',
        projectId: 'project-1',
        currentState: YorksV1ProjectLifecycle.draft,
        targetState: YorksV1ProjectLifecycle.active,
        expectedProjectVersion: 1,
      );
      expect(stateChange.validate(), isEmpty);
      expect(stateChange.toRpcPayload(), {
        'project_id': 'project-1',
        'state': 'active',
        'expected_version': 1,
        'reason': null,
      });
    });

    test(
      'builds a versioned project update without changing team authority',
      () {
        final input = _validCreationInput();
        final update = YorksV1ProjectUpdateInput(
          idempotencyKey: 'update-project-100',
          projectId: 'project-1',
          expectedProjectVersion: 4,
          project: input,
        );

        expect(update.validate(), isEmpty);
        expect(update.toRpcPayload(), {
          'project_id': 'project-1',
          'expected_version': 4,
          'project_ref': 'YRK-100',
          'name': 'Cooling Upgrade',
          'job_contract_reference': 'JOB-7',
          'project_site': 'Abu Dhabi',
          'start_date': '2026-08-01',
          'target_completion_date': '2026-10-01',
          'notes': 'Phase one',
          'parties': input.toRpcPayload()['parties'],
          'buildings': [
            {
              'code': 'A01',
              'name': 'Tower A',
              'floors_levels': ['GF', 'Roof'],
              'flags': {'has_frp_room': true, 'requires_access_badge': true},
              'delivery_address': 'Tower A loading bay',
            },
          ],
        });
        expect(update.toRpcPayload().containsKey('initial_members'), isFalse);
        expect(update.toRpcPayload().containsKey('attachments'), isFalse);
      },
    );

    test('requires a reason and a current version for safe archive', () {
      const archive = YorksV1ArchiveProjectInput(
        idempotencyKey: 'archive-project-100',
        projectId: 'project-1',
        expectedProjectVersion: 4,
        reason: 'Entered in error; no open material requests.',
      );

      expect(archive.validate(), isEmpty);
      expect(archive.toRpcPayload(), {
        'project_id': 'project-1',
        'expected_version': 4,
        'reason': 'Entered in error; no open material requests.',
      });
    });
  });

  group('Yorks V1 creation draft recovery', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );

    test(
      'keeps selected project dates as calendar values across timezones',
      () {
        final draft = YorksV1ProjectCreationDraft.fromJson({
          'ownerAuthUserId': 'auth-owner',
          'currentStage': 0,
          'creationIdempotencyKey': 'date-only-draft',
          'reference': 'YRK-DATE-001',
          'name': 'Calendar date project',
          // This is an older timestamp-shaped draft value from a UTC+05 device.
          // A date-only form field must retain its written calendar day.
          'startDate': '2026-08-01T00:00:00.000+05:00',
          'endDate': '2026-08-31T00:00:00.000+05:00',
          'updatedAt': '2026-08-01T00:00:00.000Z',
        });

        expect(draft.startDate, DateTime(2026, 8, 1));
        expect(draft.endDate, DateTime(2026, 8, 31));
        expect(draft.toJson()['startDate'], '2026-08-01');
        expect(draft.toJson()['endDate'], '2026-08-31');
      },
    );

    test(
      'recovers all five-stage input only for its authenticated owner',
      () async {
        var scope = container();
        final draft = scope
            .read(yorksV1ProjectCreationDraftProvider('auth-owner'))
            .copyWith(
              currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
              reference: 'YRK-200',
              name: 'Recovered project',
              initialMembers: const [
                YorksV1InitialProjectMemberInput(
                  authUserId: 'auth-pe',
                  projectRole: YorksV1ProjectMembershipRole.projectEngineer,
                  reason: 'initial_team',
                ),
              ],
              buildings: const [
                YorksV1ProjectBuildingInput(name: 'Building', code: 'B1'),
              ],
            );
        final key = draft.creationIdempotencyKey;
        await scope
            .read(yorksV1ProjectCreationDraftProvider('auth-owner').notifier)
            .save(draft);
        scope.dispose();

        scope = container();
        addTearDown(scope.dispose);
        final restored = scope.read(
          yorksV1ProjectCreationDraftProvider('auth-owner'),
        );
        final other = scope.read(
          yorksV1ProjectCreationDraftProvider('auth-other'),
        );

        expect(
          restored.currentStage,
          YorksV1ProjectCreationStage.reviewAndCreate,
        );
        expect(restored.reference, 'YRK-200');
        expect(restored.creationIdempotencyKey, key);
        expect(other.reference, isEmpty);
        expect(other.ownerAuthUserId, 'auth-other');
        expect(other.creationIdempotencyKey, isNot(key));
      },
    );
  });

  group('Yorks V1 repository and controller guards', () {
    test('fails closed while projects are disabled or offline', () async {
      final disabledRpc = _RecordingRpcClient(_createResponse());
      final disabled = YorksV1SupabaseProjectRepository(
        featureFlags: const YorksV1FeatureFlags(foundation: true),
        connectivity: DefaultConnectivity(),
        rpcClient: disabledRpc,
      );
      await expectLater(
        disabled.createProject(_validCreationInput()),
        throwsA(_domainCode(YorksV1DomainErrorCode.featureDisabled)),
      );
      expect(disabledRpc.calls, isEmpty);

      final offlineRpc = _RecordingRpcClient(_createResponse());
      final offline = YorksV1SupabaseProjectRepository(
        featureFlags: const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
        ),
        connectivity: DefaultConnectivity(online: false),
        rpcClient: offlineRpc,
      );
      await expectLater(
        offline.createProject(_validCreationInput()),
        throwsA(_domainCode(YorksV1DomainErrorCode.offline)),
      );
      expect(offlineRpc.calls, isEmpty);
    });

    test(
      'uses typed RPC conversion and keeps actor authority out of payload',
      () async {
        final rpc = _RecordingRpcClient(_createResponse());
        final repository = YorksV1SupabaseProjectRepository(
          featureFlags: const YorksV1FeatureFlags(
            foundation: true,
            projects: true,
          ),
          connectivity: DefaultConnectivity(),
          rpcClient: rpc,
        );

        final result = await repository.createProject(_validCreationInput());

        expect(result.project.id, 'project-1');
        expect(result.project.recordVersion, 1);
        expect(result.scopes.single.isCommon, isTrue);
        expect(result.scopes.single.floorsOrLevels, ['GF']);
        expect(result.scopes.single.hasFrpRoom, isTrue);
        expect(result.scopes.single.deliveryAddress, 'Common delivery point');
        expect(result.scopes.single.flags['has_frp_room'], isTrue);
        expect(result.members.single.memberAuthUserId, 'auth-creator');
        expect(result.members.single.assignedByAuthUserId, 'auth-admin');
        expect(result.members.single.assignedByRole, 'admin');
        expect(result.parties.single.kind, YorksV1ProjectPartyKind.client);
        expect(result.attachments.single.fileName, 'approved-drawing.pdf');
        expect(rpc.calls, hasLength(1));
        expect(rpc.calls.single.functionName, 'v1_create_project');
        expect(rpc.calls.single.parameters['p_idempotency_key'], 'command-100');
        final payload =
            rpc.calls.single.parameters['p_payload'] as Map<String, dynamic>;
        expect(payload['project_ref'], 'YRK-100');
        expect(payload.containsKey('actor_id'), isFalse);
        expect(payload.containsKey('actor_role'), isFalse);
        expect(payload.containsKey('created_at'), isFalse);
      },
    );

    test(
      'uses the typed revocation RPC and preserves server revocation history',
      () async {
        final rpc = _RecordingRpcClient(_revokedMemberResponse());
        final repository = YorksV1SupabaseProjectRepository(
          featureFlags: const YorksV1FeatureFlags(
            foundation: true,
            projects: true,
          ),
          connectivity: DefaultConnectivity(),
          rpcClient: rpc,
        );

        final result = await repository.revokeProjectMember(
          _memberRevocationInput(),
        );

        expect(result.member.effectiveTo, DateTime.utc(2026, 8, 15, 12, 30));
        expect(result.member.revokedByRole, 'project_engineer');
        expect(result.member.revokedReason, 'access_removed');
        expect(rpc.calls, hasLength(1));
        final call = rpc.calls.single;
        expect(call.functionName, 'v1_revoke_project_member');
        expect(call.parameters['p_idempotency_key'], 'command-revoke-member');
        expect(call.parameters['p_payload'], {
          'project_id': 'project-1',
          'member_auth_user_id': 'auth-member',
          'project_role': 'site_engineer',
          'expected_version': 2,
          'reason': 'access_removed',
        });
        final payload = call.parameters['p_payload'] as Map<String, dynamic>;
        expect(payload.containsKey('actor_id'), isFalse);
        expect(payload.containsKey('actor_role'), isFalse);
        expect(payload.containsKey('revoked_at'), isFalse);
      },
    );

    test('prevents Procurement from unauthorized project commands', () async {
      final repository = _FakeProjectRepository();
      final procurement = YorksV1ProjectCommandController(
        repository: repository,
        currentRole: () => YorksV1Role.procurement,
      );
      await expectLater(
        procurement.createProject(_validCreationInput()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unauthorized)),
      );
      await expectLater(
        procurement.revokeProjectMember(_memberRevocationInput()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unauthorized)),
      );
      expect(repository.createCalls, 0);
      expect(repository.revokeCalls, 0);
      expect(procurement.state.errorCode, YorksV1DomainErrorCode.unauthorized);
    });

    test(
      'defers a Site Engineer project-specific PE membership check to the RPC',
      () async {
        final repository = _FakeProjectRepository();
        final siteEngineer = YorksV1ProjectCommandController(
          repository: repository,
          currentRole: () => YorksV1Role.siteEngineer,
        );

        await siteEngineer.assignProjectMember(_memberAssignmentInput());
        await siteEngineer.revokeProjectMember(_memberRevocationInput());
        await siteEngineer.setProjectState(
          const YorksV1SetProjectStateInput(
            idempotencyKey: 'site-project-state',
            projectId: 'project-1',
            currentState: YorksV1ProjectLifecycle.draft,
            targetState: YorksV1ProjectLifecycle.active,
            expectedProjectVersion: 1,
          ),
        );

        // A base Site Engineer may hold a dated Project Engineer membership.
        // The server sees that membership and remains the authority; a generic
        // client role guard must not reject the command first.
        expect(repository.assignCalls, 1);
        expect(repository.revokeCalls, 1);
        expect(repository.stateCalls, 1);
        expect(
          siteEngineer.state.status,
          YorksV1ProjectCommandStatus.succeeded,
        );
      },
    );

    test(
      'keeps the revoke idempotency key on a retry after server failure',
      () async {
        final repository = _FakeProjectRepository(revokeFailuresRemaining: 1);
        final controller = YorksV1ProjectCommandController(
          repository: repository,
          currentRole: () => YorksV1Role.projectEngineer,
        );
        final input = _memberRevocationInput();

        await expectLater(
          controller.revokeProjectMember(input),
          throwsA(_domainCode(YorksV1DomainErrorCode.backendUnavailable)),
        );
        expect(
          controller.state.operation,
          YorksV1ProjectCommandOperation.revokeProjectMember,
        );
        expect(controller.state.status, YorksV1ProjectCommandStatus.failed);

        final result = await controller.revokeProjectMember(input);

        expect(repository.revokeCalls, 2);
        expect(
          repository.revocationInputs
              .map((received) => received.idempotencyKey)
              .toList(),
          ['command-revoke-member', 'command-revoke-member'],
        );
        expect(result.idempotencyKey, 'command-revoke-member');
        expect(result.member.revokedReason, 'access_removed');
        expect(
          controller.state.operation,
          YorksV1ProjectCommandOperation.revokeProjectMember,
        );
        expect(controller.state.status, YorksV1ProjectCommandStatus.succeeded);
      },
    );

    test('permits only Admin to archive a completed project', () async {
      final repository = _FakeProjectRepository();
      const archive = YorksV1SetProjectStateInput(
        idempotencyKey: 'command-archive',
        projectId: 'project-1',
        currentState: YorksV1ProjectLifecycle.completed,
        targetState: YorksV1ProjectLifecycle.archived,
        expectedProjectVersion: 2,
        reason: 'Closure records retained',
      );
      final projectEngineer = YorksV1ProjectCommandController(
        repository: repository,
        currentRole: () => YorksV1Role.projectEngineer,
      );

      await expectLater(
        projectEngineer.setProjectState(archive),
        throwsA(_domainCode(YorksV1DomainErrorCode.unauthorized)),
      );
      expect(repository.stateCalls, 0);

      final admin = YorksV1ProjectCommandController(
        repository: repository,
        currentRole: () => YorksV1Role.admin,
      );
      await admin.setProjectState(archive);
      expect(repository.stateCalls, 1);
    });
  });
}

YorksV1ProjectCreationInput _validCreationInput() {
  return YorksV1ProjectCreationInput(
    idempotencyKey: 'command-100',
    reference: 'YRK-100',
    name: 'Cooling Upgrade',
    clientName: 'Client LLC',
    clientContactName: 'Client Contact',
    clientContactPhone: '+9710000000',
    clientContactEmail: 'client@example.test',
    clientAddress: 'Client address',
    jobOrContractReference: 'JOB-7',
    siteLocation: 'Abu Dhabi',
    startDate: DateTime.utc(2026, 8, 1),
    endDate: DateTime.utc(2026, 10, 1),
    notes: 'Phase one',
    parties: const [
      YorksV1ProjectPartyInput(
        kind: YorksV1ProjectPartyKind.consultant,
        name: 'Consultant LLC',
      ),
      YorksV1ProjectPartyInput(
        kind: YorksV1ProjectPartyKind.mainContractor,
        name: 'Main Contractor LLC',
      ),
      YorksV1ProjectPartyInput(
        kind: YorksV1ProjectPartyKind.subcontractor,
        name: 'Duct Works LLC',
      ),
      YorksV1ProjectPartyInput(
        kind: YorksV1ProjectPartyKind.otherContractor,
        name: 'Civil Works LLC',
      ),
    ],
    initialMembers: const [
      YorksV1InitialProjectMemberInput(
        authUserId: 'auth-project-engineer',
        projectRole: YorksV1ProjectMembershipRole.projectEngineer,
        reason: 'initial_team',
      ),
      YorksV1InitialProjectMemberInput(
        authUserId: 'auth-site-engineer',
        projectRole: YorksV1ProjectMembershipRole.siteEngineer,
        reason: 'initial_team',
      ),
    ],
    buildings: const [
      YorksV1ProjectBuildingInput(
        name: 'Tower A',
        code: 'a01',
        floorsOrLevels: ['GF', 'Roof'],
        hasFrpRoom: true,
        flags: {'requires_access_badge': true},
        deliveryAddress: 'Tower A loading bay',
      ),
    ],
    attachments: const [
      YorksV1ProjectAttachmentInput(
        fileName: 'approved-drawing.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 42,
      ),
    ],
  );
}

YorksV1AssignProjectMemberInput _memberAssignmentInput() {
  return const YorksV1AssignProjectMemberInput(
    idempotencyKey: 'command-member',
    projectId: 'project-1',
    memberAuthUserId: 'auth-member',
    projectRole: YorksV1ProjectMembershipRole.siteEngineer,
    expectedProjectVersion: 1,
    reason: 'team_change',
  );
}

YorksV1RevokeProjectMemberInput _memberRevocationInput() {
  return const YorksV1RevokeProjectMemberInput(
    idempotencyKey: 'command-revoke-member',
    projectId: 'project-1',
    memberAuthUserId: 'auth-member',
    projectRole: YorksV1ProjectMembershipRole.siteEngineer,
    expectedProjectVersion: 2,
    reason: 'access_removed',
  );
}

Matcher _domainCode(YorksV1DomainErrorCode code) {
  return isA<YorksV1DomainException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

class _RpcCall {
  const _RpcCall({required this.functionName, required this.parameters});

  final String functionName;
  final Map<String, dynamic> parameters;
}

class _RecordingRpcClient implements YorksV1ProjectRpcClient {
  _RecordingRpcClient(this._response);

  final Map<String, dynamic> _response;
  final List<_RpcCall> calls = [];

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async {
    calls.add(_RpcCall(functionName: functionName, parameters: parameters));
    return _response;
  }
}

class _FakeProjectRepository implements YorksV1ProjectRepository {
  _FakeProjectRepository({this.revokeFailuresRemaining = 0});

  var createCalls = 0;
  var assignCalls = 0;
  var revokeCalls = 0;
  var stateCalls = 0;
  int revokeFailuresRemaining;
  final List<YorksV1RevokeProjectMemberInput> revocationInputs = [];

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    createCalls++;
    return YorksV1ProjectCreationResult.fromRpcJson(_createResponse());
  }

  @override
  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  ) async {
    assignCalls++;
    return YorksV1ProjectMembershipResult.fromRpcJson(_memberResponse());
  }

  @override
  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  ) async {
    revokeCalls++;
    revocationInputs.add(input);
    if (revokeFailuresRemaining > 0) {
      revokeFailuresRemaining--;
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return YorksV1ProjectMembershipResult.fromRpcJson(_revokedMemberResponse());
  }

  @override
  Future<YorksV1Project> setProjectState(
    YorksV1SetProjectStateInput input,
  ) async {
    stateCalls++;
    return YorksV1Project.fromRpcJson(_projectJson());
  }

  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) async {
    return YorksV1Project.fromRpcJson(_projectJson());
  }

  @override
  Future<YorksV1Project> archiveProject(
    YorksV1ArchiveProjectInput input,
  ) async {
    return YorksV1Project.fromRpcJson(_projectJson());
  }
}

Map<String, dynamic> _createResponse() => {
  'project_id': 'project-1',
  'project_ref': 'YRK-100',
  'state': 'draft',
  'record_version': 1,
  'common_scope_id': 'scope-common',
  'created_at': '2026-08-01T00:00:00.000Z',
  'idempotency_key': 'command-100',
  'project': _projectJson(),
  'parties': [
    {
      'id': 'party-client',
      'party_kind': 'client',
      'party_order': 0,
      'name': 'Client LLC',
      'contact_name': 'Client Contact',
      'contact_phone': '+9710000000',
      'contact_email': 'client@example.test',
      'address': 'Client address',
    },
  ],
  'scopes': [
    {
      'id': 'scope-common',
      'project_id': 'project-1',
      'scope_kind': 'common',
      'code': 'COMMON',
      'name': 'Common',
      'is_active': true,
      'floors_levels': ['GF'],
      'flags': {'has_frp_room': true},
      'delivery_address': 'Common delivery point',
    },
  ],
  'members': [
    {
      'id': 'member-creator',
      'project_id': 'project-1',
      'member_auth_user_id': 'auth-creator',
      'project_role': 'site_engineer',
      'effective_from': '2026-08-01T00:00:00.000Z',
      'created_at': '2026-08-01T00:00:00.000Z',
      'assigned_by_auth_user_id': 'auth-admin',
      'assigned_by_role': 'admin',
    },
  ],
  'attachments': [
    {
      'file_name': 'approved-drawing.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 42,
    },
  ],
};

Map<String, dynamic> _memberResponse() => {
  'project': _projectJson(),
  'member': {
    'id': 'member-1',
    'project_id': 'project-1',
    'member_auth_user_id': 'auth-member',
    'project_role': 'site_engineer',
    'effective_from': '2026-08-01T00:00:00.000Z',
    'created_at': '2026-08-01T00:00:00.000Z',
    'assigned_by_auth_user_id': 'auth-admin',
    'assigned_by_role': 'admin',
  },
};

Map<String, dynamic> _revokedMemberResponse() => {
  'idempotency_key': 'command-revoke-member',
  'project': _projectJson(),
  'member': {
    'id': 'member-1',
    'project_id': 'project-1',
    'auth_user_id': 'auth-member',
    'display_name': 'Site Engineer',
    'project_role': 'site_engineer',
    'effective_from': '2026-08-01T00:00:00.000Z',
    'effective_to': '2026-08-15T12:30:00.000Z',
    'created_at': '2026-08-01T00:00:00.000Z',
    'reason': 'team_change',
    'assigned_by_auth_user_id': 'auth-admin',
    'assigned_by_role': 'admin',
    'revoked_by_auth_user_id': 'auth-project-engineer',
    'revoked_by_role': 'project_engineer',
    'revoked_reason': 'access_removed',
  },
};

Map<String, dynamic> _projectJson() => {
  'id': 'project-1',
  'project_ref': 'YRK-100',
  'name': 'Cooling Upgrade',
  'state': 'draft',
  'record_version': 1,
  'created_at': '2026-08-01T00:00:00.000Z',
};

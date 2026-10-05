import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_local_draft_section.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_navigation_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_local_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';

/// Actual setup presentation with synthetic read context and browser storage.
/// No remote backend is configured and no live user/project write is possible.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final stageIndex =
      int.tryParse(Uri.base.queryParameters['stage'] ?? '0') ?? 0;
  final stage = YorksV1ProjectCreationStage.values[stageIndex.clamp(0, 4)];
  final session = Uri.base.queryParameters['session'] ?? 'review';
  final user = AppUser(
    id: 'setup-visual-person',
    fullName: 'Sarah Ahmed',
    email: 'fixture@example.invalid',
    role: UserRole.engineer,
    yorksV1RoleCache: YorksV1Role.projectEngineer,
    createdAt: DateTime.utc(2026),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => _FixturePermissionController(
          _fixturePermissionState(role: YorksV1Role.projectEngineer),
        ),
      ),
      currentUserProvider.overrideWithValue(user),
      yorksV1AuthUserIdProvider.overrideWithValue(user.id),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.projectEngineer),
      yorksV1FeatureFlagsProvider.overrideWithValue(
        const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          projectSetup: true,
        ),
      ),
      yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
        'local-visual-fixture-$session',
      ),
      yorksV1WorkspaceStatusProvider.overrideWithValue(
        const YorksV1WorkspaceStatus(
          state: YorksV1WorkspaceConnectionState.connected,
        ),
      ),
      yorksV1ActiveProjectTeamDirectoryProvider.overrideWith(
        (ref) async => const [
          YorksV1ProjectTeamDirectoryMember(
            authUserId: 'fixture-pe',
            displayName: 'Aaron Joseph',
            eligibleRole: YorksV1Role.projectEngineer,
          ),
          YorksV1ProjectTeamDirectoryMember(
            authUserId: 'fixture-se',
            displayName: 'Abdul Raheem',
            eligibleRole: YorksV1Role.siteEngineer,
          ),
        ],
      ),
    ],
  );
  await container
      .read(languageProvider.notifier)
      .setLanguage(
        Uri.base.queryParameters['language'] == 'ar'
            ? AppLanguage.arabic
            : AppLanguage.english,
      );
  final controller = container.read(
    yorksV1ProjectSetupCreationDraftProvider(user.id).notifier,
  );
  await controller.takeOver();
  await controller.save(
    container
        .read(yorksV1ProjectSetupCreationDraftProvider(user.id))
        .copyWith(
          reference: 'YRA-322',
          name: 'NEXUS — Four substations',
          clientName: 'TAQA Transmission',
          parties: const [
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.consultant,
              name: 'AtkinsRéalis',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.mainContractor,
              name: 'Balfour Beatty',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.subcontractor,
              name: 'Northfield Electrical Ltd',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.subcontractor,
              name: 'Delta Mechanical Services',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.otherContractor,
              name: 'Siteworks UK',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.otherContractor,
              name: 'Crane Hire Co.',
            ),
            YorksV1ProjectPartyInput(
              kind: YorksV1ProjectPartyKind.otherContractor,
              name: 'Safety Solutions',
            ),
          ],
          jobOrContractReference: 'C-4587',
          siteLocation: 'Al Dhafra, Abu Dhabi',
          startDate: DateTime.utc(2024, 3, 12),
          endDate: DateTime.utc(2024, 11, 30),
          notes: 'Four new substations as part of the Nexus programme.',
          attachments: [
            const YorksV1ProjectAttachmentInput(
              localId: 'fixture-file-1',
              fileName: 'DF3W_General_Arrangement.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 2400000,
            ),
            const YorksV1ProjectAttachmentInput(
              localId: 'fixture-file-2',
              fileName: 'Load_Calculations_DF3W.xlsx',
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              sizeBytes: 1100000,
            ),
            const YorksV1ProjectAttachmentInput(
              localId: 'fixture-file-3',
              fileName: 'Programme_DF3W.docx',
              mimeType:
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              sizeBytes: 856000,
            ),
            if (stage != YorksV1ProjectCreationStage.reviewAndCreate)
              const YorksV1ProjectAttachmentInput(
                localId: 'fixture-file-4',
                fileName: 'Electrical_Schematics.pdf',
                mimeType: 'application/pdf',
                sizeBytes: 1800000,
              ),
          ],
          rawEditorState: {
            'reviewedOperationalFiles': [
              'fixture-file-1:2400000',
              'fixture-file-2:1100000',
              'fixture-file-3:856000',
              'fixture-file-4:1800000',
            ],
            if (stage == YorksV1ProjectCreationStage.buildings) ...{
              'buildingLocalId': 'fixture-b1',
              'buildingCode': 'DF3W',
              'buildingName': 'DF3W substation',
              'buildingFloors': 'Ground, Roof',
              'buildingAddress': 'Al Dhafra, Abu Dhabi',
              'buildingFrp': true,
            },
          },
          currentStage: stage,
          visitedStages: YorksV1ProjectCreationStage.values
              .where((value) => value.index <= stage.index)
              .toSet(),
          buildings: const [
            YorksV1ProjectBuildingInput(
              localRowId: 'fixture-b1',
              code: 'DF3W',
              name: 'DF3W substation',
              floorsOrLevels: ['Ground', 'Roof'],
              deliveryAddress: 'Zone 1, metro depot',
              hasFrpRoom: true,
            ),
            YorksV1ProjectBuildingInput(
              localRowId: 'fixture-b2',
              code: 'DF4W',
              name: 'DF4W substation',
              floorsOrLevels: ['Ground'],
              deliveryAddress: 'Al Dhafra, Abu Dhabi',
              hasFrpRoom: false,
            ),
            YorksV1ProjectBuildingInput(
              localRowId: 'fixture-b3',
              code: 'DF6W',
              name: 'DF6W substation',
              floorsOrLevels: ['Ground', 'L1'],
            ),
            YorksV1ProjectBuildingInput(
              localRowId: 'fixture-b4',
              code: 'DF7W',
              name: 'DF7W substation',
              hasFrpRoom: true,
            ),
          ],
        ),
  );
  final router = GoRouter(
    initialLocation: stageIndex == 5
        ? '/yorks/projects/fixture-confirmed-project'
        : Uri.base.queryParameters['fresh'] == 'true'
        ? RoutePaths.engineerCreateProject
        : RoutePaths.yorksV1ProjectSetupDraftPath(
            container
                .read(yorksV1ProjectSetupCreationDraftProvider(user.id))
                .draftId,
          ),
    routes: [
      GoRoute(
        path: RoutePaths.engineerCreateProject,
        onExit: (context, state) => container
            .read(yorksV1ProjectSetupNavigationGuardProvider)
            .canLeave(),
        builder: (context, state) => YorksV1WorkspaceShell(
          featureOwnsBackNavigation: true,
          child: YorksV1ProjectCreateFlowScreen(
            resumeDraftId: state.uri.queryParameters['draft'],
            legacyRecovery: state.uri.queryParameters['recovery'] == 'legacy',
          ),
        ),
      ),
      GoRoute(
        path: '/yorks/projects/:projectId',
        builder: (context, state) => YorksV1WorkspaceShell(
          child: _VisualProjectDestination(
            projectId: state.pathParameters['projectId']!,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Projects,
        builder: (context, _) => YorksV1WorkspaceShell(
          child: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Local synthetic project setup fixture'),
                    FilledButton(
                      onPressed: () =>
                          context.go(RoutePaths.engineerCreateProject),
                      child: Text(
                        YorksV1ProjectStrings.createProject.active(
                          container.read(languageProvider),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: YorksV1ProjectLocalDraftSection(
                        draftState: ref.watch(
                          yorksV1ProjectLocalCreationDraftProvider,
                        ),
                        language: ref.watch(languageProvider),
                        scopeIdentity:
                            'local-visual-fixture-$session:${user.id}',
                        onResume: (id) => context.go(
                          RoutePaths.yorksV1ProjectSetupDraftPath(id),
                        ),
                        onLegacyRecovery: () => context.go(
                          RoutePaths.yorksV1ProjectSetupLegacyRecovery,
                        ),
                        onRetry: () => ref.invalidate(
                          yorksV1ProjectLocalCreationDraftProvider,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              (double.tryParse(Uri.base.queryParameters['scale'] ?? '1') ?? 1)
                  .clamp(1, 2),
            ),
          ),
          child: Directionality(
            textDirection: container.read(languageProvider).isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child!,
          ),
        ),
      ),
    ),
  );
}

/// Read-only synthetic navigation target, not a second project-created screen.
/// Actual authorized Create -> project navigation is covered by the flow tests;
/// this backend-free browser fixture does not issue or confirm server commands.
class _VisualProjectDestination extends ConsumerWidget {
  const _VisualProjectDestination({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Local synthetic project destination — no server command ran',
            ),
            const SizedBox(height: 24),
            Text(
              YorksV1ProjectStrings.projectDetails.active(language),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text('YRA-322 · NEXUS — Four substations'),
            const SizedBox(height: 12),
            Text(projectId),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.go(RoutePaths.yorksV1Projects),
              child: Text(
                YorksV1ProjectSetupShellStrings.returnToProjects.active(
                  language,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _fixtureCapabilities = <String>{
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
class _FixturePermissionController
    extends YorksV1CurrentPermissionSnapshotController {
  _FixturePermissionController(YorksV1CurrentPermissionSnapshotState value)
    : super(
        enabled: false,
        authUserId: null,
        client: null,
        repository: _UnusedPermissionRepository(),
      ) {
    state = value;
  }
}

YorksV1CurrentPermissionSnapshotState _fixturePermissionState({
  YorksV1Role role = YorksV1Role.admin,
  Iterable<String> capabilities = _fixtureCapabilities,
  bool stale = false,
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
          'requires_project_access': false,
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
          'project_overrides': <Object?>[],
        },
    ],
    'project_access': <Object?>[],
  }),
  isStale: stale,
  isRevisionSignalHealthy: true,
);

class _UnusedPermissionRepository implements YorksV1PermissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

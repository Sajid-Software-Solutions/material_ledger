import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/constants/constants.dart';
import 'package:material_ledger/features/admin/presentation/screens/yorks_v1_user_access_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'phone workspace is fail-closed while loading and shadow rows stay read only',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer = Completer<YorksV1UserPermissionWorkspace>();
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          active: false,
          authorizationMode: YorksV1PermissionAuthorizationMode.shadow,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.shadow,
        ),
        initialLoad: completer,
        canManage: false,
      );
      await _pumpScreen(tester, repository);

      expect(
        find.byKey(const Key('permission-initial-loading')),
        findsOneWidget,
      );

      completer.complete(repository.workspace);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission-deactivated-banner')),
        findsOneWidget,
      );
      // No rollout banner; the row itself says it follows the role.
      expect(find.byKey(const Key('permission-shadow-banner')), findsNothing);
      expect(find.byKey(const Key('permission-mixed-banner')), findsNothing);
      await _openProjectsModule(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('permission-role-managed-projects.view'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      final editFinder = find.byKey(
        const Key('permission-edit-projects.view'),
        skipOffstage: false,
      );
      final edit = tester.widget<IconButton>(editFinder);
      expect(edit.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone stages then atomically reviews a permission batch with a reason',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await _openProjectsModule(tester);
      await tester.pumpAndSettle();
      final editFinder = find.byKey(
        const Key('permission-edit-projects.view'),
        skipOffstage: false,
      );
      await _bringIntoView(tester, editFinder);
      await tester.tap(editFinder.hitTestable());
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('permission-stage-change')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission-review-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('permission-review-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission-review-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('permission-change-reason')),
        'short',
      );
      await tester.tap(find.byKey(const Key('permission-confirm-save')));
      await tester.pump();
      expect(
        find.text('Enter a meaningful reason of at least 8 characters.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('permission-change-reason')),
        'Temporary project coverage',
      );
      await tester.tap(find.byKey(const Key('permission-confirm-save')));
      await tester.pumpAndSettle();

      final input = repository.lastBatch;
      expect(input, isNotNull);
      expect(input!.expectedRevision, 7);
      expect(input.reason, 'Temporary project coverage');
      expect(input.changes, hasLength(1));
      expect(
        input.changes.single.operation,
        YorksV1PermissionChangeOperation.set,
      );
      expect(
        input.changes.single.effect,
        YorksV1PermissionAssignmentEffect.grant,
      );
      expect(
        input.changes.single.scope!.kind,
        YorksV1PermissionScopeKind.organization,
      );
      expect(find.byKey(const Key('permission-review-button')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed permission viewer can inspect enforced rows but cannot edit',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: false,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      expect(find.text('Scoped Access'), findsOneWidget);
      await _openProjectsModule(tester);
      await tester.pumpAndSettle();
      final editFinder = find.byKey(
        const Key('permission-edit-projects.view'),
        skipOffstage: false,
      );
      final edit = tester.widget<IconButton>(editFinder);
      expect(edit.onPressed, isNull);
      expect(repository.lastBatch, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Workforce grant review includes dependency and responsibility explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
          catalogAccess: [
            _workforceCapability(
              key: YorksV1CapabilityKeys.workforceView,
              action: 'view',
              dependencies: const [],
            ),
            _workforceCapability(
              key: YorksV1CapabilityKeys.workforceAttendanceMaintain,
              action: 'attendance_maintain',
              dependencies: const [YorksV1CapabilityKeys.workforceView],
            ),
          ],
          workforceAccess: YorksV1WorkforceAccessStatus(
            referenceDate: DateTime.utc(2026, 8, 31),
            hasOperationalAccess: false,
            canAssignOrganizationResponsibility: true,
            activeWorkerCount: 0,
            activeTeamCount: 0,
            scheduledTeamCount: 0,
          ),
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await _openModule(tester, 'workforce');
      await tester.pumpAndSettle();
      final edit = find.byKey(
        const Key('permission-edit-workforce.attendance.maintain'),
        skipOffstage: false,
      );
      await _bringIntoView(tester, edit);
      await tester.tap(edit.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('permission-stage-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('permission-review-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission-review-dialog')), findsOneWidget);
      expect(find.textContaining('Required prerequisite for'), findsOneWidget);
      final responsibility = tester.widget<CheckboxListTile>(
        find.byKey(const Key('permission-include-workforce-responsibility')),
      );
      expect(responsibility.value, isTrue);
      await tester.enterText(
        find.byKey(const Key('permission-change-reason')),
        'Enable Masaud attendance responsibility',
      );
      await tester.tap(find.byKey(const Key('permission-confirm-save')));
      await tester.pumpAndSettle();

      expect(repository.lastBatch, isNotNull);
      expect(
        repository.lastBatch!.changes
            .map((change) => change.capabilityKey)
            .toSet(),
        {
          YorksV1CapabilityKeys.workforceView,
          YorksV1CapabilityKeys.workforceAttendanceMaintain,
        },
      );
      expect(repository.lastAssignOrganizationResponsibility, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'half-enabled Workforce access exposes an audited responsibility recovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
          workforceAccess: YorksV1WorkforceAccessStatus(
            referenceDate: DateTime.utc(2026, 8, 31),
            hasOperationalAccess: true,
            canAssignOrganizationResponsibility: true,
            activeWorkerCount: 0,
            activeTeamCount: 0,
            scheduledTeamCount: 0,
          ),
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      final banner = find.byKey(
        const Key('permission-workforce-responsibility-banner'),
      );
      expect(banner, findsOneWidget);
      final action = find.text('Assign responsibility');
      await _bringIntoView(tester, action);
      await tester.tap(action.hitTestable());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('workforce-responsibility-reason')),
        'Restore retained Workforce responsibility',
      );
      await tester.tap(
        find.byKey(const Key('confirm-workforce-responsibility')),
      );
      await tester.pumpAndSettle();

      expect(
        repository.lastResponsibilityReason,
        'Restore retained Workforce responsibility',
      );
      expect(
        find.byKey(const Key('permission-workforce-empty-setup-banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'with attendance V2 the Workforce responsibility is neither warned about '
    'nor offered',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
          workforceAccess: YorksV1WorkforceAccessStatus(
            referenceDate: DateTime.utc(2026, 11, 14),
            hasOperationalAccess: true,
            canAssignOrganizationResponsibility: true,
            activeWorkerCount: 138,
            activeTeamCount: 2,
            scheduledTeamCount: 0,
          ),
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository, attendanceV2: true);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission-workforce-responsibility-banner')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('permission-workforce-empty-setup-banner')),
        findsNothing,
      );
      expect(find.text('Assign responsibility'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('matching rules show no comparison and no revision number', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final agreeing = _FakePermissionRepository(
      workspace: _workspace(
        authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
        capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
      ),
      canManage: true,
    );
    await _pumpScreen(tester, agreeing);
    await tester.pumpAndSettle();
    await _openProjectsModule(tester);
    await tester.pumpAndSettle();
    expect(find.text('Parity confirmed'), findsNothing);
    expect(find.text('Rules differ, check'), findsNothing);
    expect(find.text('Shadow mode'), findsNothing);
    expect(find.text('Revision 7'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('differing rules say so plainly, with the new rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final differing = _FakePermissionRepository(
      workspace: _workspace(
        authorizationMode: YorksV1PermissionAuthorizationMode.shadow,
        capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.shadow,
        parity: false,
        candidateEffective: false,
      ),
      canManage: true,
    );
    await _pumpScreen(tester, differing);
    await tester.pumpAndSettle();
    await _openProjectsModule(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('permission-rules-differ-projects.view'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('New rule: Denied', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuity permissions are immediate and open ended in the editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakePermissionRepository(
        workspace: _workspace(
          capabilityKey: YorksV1CapabilityKeys.usersView,
          module: 'users',
          action: 'view',
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await _openModule(tester, 'users');
      await tester.pumpAndSettle();
      final editFinder = find.byKey(
        const Key('permission-edit-users.view'),
        skipOffstage: false,
      );
      await _bringIntoView(tester, editFinder);
      await tester.tap(editFinder.hitTestable());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('permission-continuity-policy')),
        findsOneWidget,
      );
      expect(find.text('Set an expiry date'), findsNothing);
      await tester.tap(find.byKey(const Key('permission-stage-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('permission-review-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('permission-change-reason')),
        'Maintain directory access continuity',
      );
      await tester.tap(find.byKey(const Key('permission-confirm-save')));
      await tester.pumpAndSettle();

      expect(repository.lastBatch, isNotNull);
      expect(repository.lastBatch!.changes.single.effectiveFrom, isNull);
      expect(repository.lastBatch!.changes.single.effectiveUntil, isNull);
      expect(
        yorksV1PermissionRequiresImmediateOpenEnded(
          YorksV1CapabilityKeys.permissionsDelegate,
        ),
        isTrue,
      );
      expect(
        yorksV1PermissionRequiresImmediateOpenEnded(
          YorksV1CapabilityKeys.projectsView,
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('delegation scope uses server ceiling and project intersection', () {
    const targetProjects = [
      YorksV1PermissionProjectAccess(
        projectId: 'project-a',
        projectRef: 'YRA-A',
        projectName: 'Project A',
        state: 'active',
        hasAccess: true,
      ),
      YorksV1PermissionProjectAccess(
        projectId: 'project-b',
        projectRef: 'YRA-B',
        projectName: 'Project B',
        state: 'active',
        hasAccess: true,
      ),
    ];
    const actorProjectA = [
      YorksV1PermissionProjectAccess(
        projectId: 'project-a',
        projectRef: 'YRA-A',
        projectName: 'Project A',
        state: 'active',
        hasAccess: true,
      ),
    ];
    const allScopes = [
      YorksV1PermissionScopeKind.organization,
      YorksV1PermissionScopeKind.project,
    ];
    final boundedAccess = _workspace(
      authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
      capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
      allowedScopes: allScopes,
      requiresProjectAccess: true,
      actorDelegableScopes: const [YorksV1PermissionScopeKind.project],
      projects: targetProjects,
    ).catalog.single;
    final bounded = yorksV1DelegableScopeContext(
      access: boundedAccess,
      targetProjects: targetProjects,
      actorProjects: actorProjectA,
    );

    expect(bounded.allowedScopes, {YorksV1PermissionScopeKind.project});
    expect(bounded.projects.map((project) => project.projectId), ['project-a']);
    expect(
      bounded.allows(
        YorksV1PermissionScope(
          kind: YorksV1PermissionScopeKind.project,
          projectIds: const ['project-b'],
        ),
      ),
      isFalse,
    );

    final organizationAccess = _workspace(
      authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
      capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
      allowedScopes: allScopes,
      requiresProjectAccess: true,
      actorDelegableScopes: allScopes,
      projects: targetProjects,
    ).catalog.single;
    final organization = yorksV1DelegableScopeContext(
      access: organizationAccess,
      targetProjects: targetProjects,
      actorProjects: targetProjects,
    );
    expect(organization.allowedScopes, allScopes.toSet());
    expect(organization.projects, hasLength(2));

    final absentProjection = _workspace(
      authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
      capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
      allowedScopes: allScopes,
      requiresProjectAccess: true,
      actorDelegableScopes: const [],
      projects: targetProjects,
    ).catalog.single;
    expect(
      yorksV1DelegableScopeContext(
        access: absentProjection,
        targetProjects: targetProjects,
        actorProjects: targetProjects,
      ).allowedScopes,
      isEmpty,
    );
  });

  testWidgets('resolution-only project rows render as effective decisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _FakePermissionRepository(
      workspace: _workspace(
        authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
        capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        projectOverrides: const [
          YorksV1PermissionProjectEffectiveAccess(
            projectId: 'project-a',
            projectRef: 'YRA-A',
            projectName: 'Project A',
            effect: null,
            hasProjectAccess: true,
            authoritativeEffective: true,
            authoritativeSource: YorksV1PermissionEffectiveSource.roleDefault,
            candidateEffective: true,
            candidateSource: YorksV1PermissionEffectiveSource.roleDefault,
            hasParity: true,
            effectiveFrom: null,
            assignmentId: null,
          ),
        ],
      ),
      canManage: true,
    );

    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await _openProjectsModule(tester);
    await tester.pumpAndSettle();

    expect(find.text('Allowed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission history renders before and after assignment arrays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    YorksV1PermissionAssignmentValue value(
      YorksV1PermissionAssignmentEffect effect,
    ) => YorksV1PermissionAssignmentValue(
      capabilityKey: YorksV1CapabilityKeys.projectsView,
      effect: effect,
      scope: YorksV1PermissionScope(
        kind: YorksV1PermissionScopeKind.organization,
      ),
      effectiveFrom: DateTime.utc(2026, 8, 24),
    );
    final repository = _FakePermissionRepository(
      workspace: _workspace(
        authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
        capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        recentHistory: [
          YorksV1PermissionHistoryEvent(
            id: 'history-1',
            kind: YorksV1PermissionHistoryEventKind.set,
            capabilityKey: YorksV1CapabilityKeys.projectsView,
            effect: YorksV1PermissionAssignmentEffect.grant,
            scope: YorksV1PermissionScope(
              kind: YorksV1PermissionScopeKind.organization,
            ),
            before: [value(YorksV1PermissionAssignmentEffect.deny)],
            after: [value(YorksV1PermissionAssignmentEffect.grant)],
            reason: 'Project coverage changed',
            actor: const YorksV1PermissionActor.user(
              appUserId: 'actor-app-user',
              displayName: 'Access Admin',
              exactRole: YorksV1Role.admin,
            ),
            occurredAt: DateTime.utc(2026, 8, 24, 9),
            idempotencyKey: 'history-key',
            eventOrdinal: 1,
            revision: 8,
          ),
        ],
      ),
      canManage: true,
    );

    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();

    expect(find.textContaining('Before: Deny'), findsOneWidget);
    expect(find.textContaining('After: Grant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({String name, Size size})>[
    (name: 'desktop 1366', size: const Size(1366, 900)),
    (name: 'tablet 1024', size: const Size(1024, 768)),
    (name: 'mobile 390', size: const Size(390, 844)),
    (name: 'mobile 360', size: const Size(360, 800)),
  ]) {
    testWidgets('${scenario.name} access workspace has no layout overflow', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: true,
      );

      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission-access-screen')), findsOneWidget);
      expect(find.byKey(const Key('permission-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'phone supports 200 percent text, semantics and 44px edit target',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: true,
      );

      await _pumpScreen(
        tester,
        repository,
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();
      await _openProjectsModule(tester);
      await tester.pumpAndSettle();
      final editFinder = find.byKey(
        const Key('permission-edit-projects.view'),
        skipOffstage: false,
      );
      await _bringIntoView(tester, editFinder);

      final editSize = tester.getSize(editFinder);
      expect(editSize.width, greaterThanOrEqualTo(44));
      expect(editSize.height, greaterThanOrEqualTo(44));
      expect(
        tester.widget<IconButton>(editFinder).tooltip,
        equals('Edit access'),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').contains('View, Allowed'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final scenario in <({String name, Size size, String golden})>[
    (
      name: 'desktop',
      size: const Size(1366, 900),
      golden: 'goldens/r35/scoped_access_1366x900.png',
    ),
    (
      name: 'mobile',
      size: const Size(360, 800),
      golden: 'goldens/r35/scoped_access_360x800.png',
    ),
  ]) {
    testWidgets('${scenario.name} scoped access visual evidence', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _FakePermissionRepository(
        workspace: _workspace(
          authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
          capabilityMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
        ),
        canManage: true,
      );
      await _pumpScreen(tester, repository);
      await tester.pumpAndSettle();
      if (scenario.size.width < AppSpacing.wideBreakpoint) {
        await _openProjectsModule(tester);
        await tester.pumpAndSettle();
      }

      await expectLater(
        find.byKey(const Key('permission-access-evidence')),
        matchesGoldenFile(scenario.golden),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pump();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _openProjectsModule(WidgetTester tester) async {
  await _openModule(tester, 'projects');
}

Future<void> _openModule(WidgetTester tester, String moduleKey) async {
  final module = find.byKey(
    Key('permission-module-$moduleKey'),
    skipOffstage: false,
  );
  for (var attempt = 0; attempt < 6; attempt++) {
    if (module.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(find.byType(ListView).first, const Offset(0, -280));
    await tester.pump();
  }
  expect(module.hitTestable(), findsOneWidget);
  await tester.tap(module.hitTestable());
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakePermissionRepository repository, {
  TextScaler? textScaler,
  bool attendanceV2 = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final provider = yorksV1UserPermissionWorkspaceControllerProvider(
    'target-app-user',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (attendanceV2)
          yorksV1FeatureFlagsProvider.overrideWithValue(
            const YorksV1FeatureFlags(
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
            ),
          ),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith((ref) {
          final controller = YorksV1CurrentPermissionSnapshotController(
            enabled: true,
            authUserId: 'actor-auth-user',
            client: null,
            repository: repository,
            revisionSignalSubscription:
                ({
                  required Future<void> Function() onSignal,
                  required void Function(Object? error) onUnavailable,
                }) async => true,
          );
          unawaited(controller.start());
          return controller;
        }),
        provider.overrideWith((ref) {
          final controller = YorksV1UserPermissionWorkspaceController(
            repository: repository,
            targetAppUserId: 'target-app-user',
            commandKeys: YorksV1CriticalCommandKeyStore(
              preferences: preferences,
              actorAuthUserId: 'actor-auth-user',
            ),
            canIssueCommands: () => ref
                .read(yorksV1CurrentPermissionSnapshotProvider)
                .isTrustedForWrites,
          );
          scheduleMicrotask(controller.load);
          return controller;
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: const RepaintBoundary(
          key: Key('permission-access-evidence'),
          child: YorksV1UserAccessScreen(targetAppUserId: 'target-app-user'),
        ),
      ),
    ),
  );
  await tester.pump();
}

YorksV1UserPermissionWorkspace _workspace({
  bool active = true,
  int revision = 7,
  String capabilityKey = YorksV1CapabilityKeys.projectsView,
  String module = 'projects',
  String action = 'view',
  Iterable<YorksV1PermissionScopeKind> allowedScopes = const [
    YorksV1PermissionScopeKind.organization,
  ],
  bool requiresProjectAccess = false,
  Iterable<YorksV1PermissionScopeKind>? actorDelegableScopes,
  List<YorksV1PermissionProjectAccess> projects = const [],
  List<YorksV1PermissionProjectEffectiveAccess> projectOverrides = const [],
  List<YorksV1PermissionHistoryEvent> recentHistory = const [],
  List<YorksV1PermissionCapabilityAccess>? catalogAccess,
  YorksV1WorkforceAccessStatus? workforceAccess,
  bool parity = true,
  bool candidateEffective = true,
  required YorksV1PermissionAuthorizationMode authorizationMode,
  required YorksV1PermissionCapabilityAuthorizationMode capabilityMode,
}) {
  final role = active ? YorksV1Role.projectEngineer : null;
  final catalog = YorksV1PermissionCatalogEntry(
    key: capabilityKey,
    module: module,
    action: action,
    label: 'View projects',
    description: 'Read an otherwise authorized project.',
    riskLevel: YorksV1PermissionRiskLevel.low,
    allowedScopes: allowedScopes,
    requiresProjectAccess: requiresProjectAccess,
    dependencies: const [],
    runtimeStatus: YorksV1PermissionRuntimeStatus.operational,
    isAssignable: true,
    displayOrder: 10,
  );
  return YorksV1UserPermissionWorkspace(
    schemaVersion: 1,
    authorizationMode: authorizationMode,
    generatedAt: DateTime.utc(2026, 8, 24),
    actor: const YorksV1PermissionActor.user(
      appUserId: 'actor-app-user',
      displayName: 'Access Admin',
      exactRole: YorksV1Role.admin,
    ),
    target: YorksV1PermissionUser(
      appUserId: 'target-app-user',
      displayName: 'Project User',
      exactRole: role,
      isActive: active,
    ),
    revision: revision,
    catalog:
        catalogAccess ??
        [
          YorksV1PermissionCapabilityAccess(
            catalog: catalog,
            authorizationMode: capabilityMode,
            roleDefault: YorksV1PermissionRoleDefault(
              capabilityKey: catalog.key,
              role: role,
              isGranted: true,
            ),
            organizationSummaryVisible: true,
            authoritativeEffective: true,
            authoritativeSource: active
                ? YorksV1PermissionEffectiveSource.roleDefault
                : YorksV1PermissionEffectiveSource.inactive,
            candidateEffective: candidateEffective,
            candidateSource: YorksV1PermissionEffectiveSource.roleDefault,
            hasParity: parity,
            actorCanDelegate: true,
            actorDelegableScopes: actorDelegableScopes ?? catalog.allowedScopes,
            projectOverrides: projectOverrides,
          ),
        ],
    assignments: const [],
    projects: projects,
    recentHistory: recentHistory,
    workforceAccess: workforceAccess,
  );
}

YorksV1UserPermissionWorkspace _workspaceCopy(
  YorksV1UserPermissionWorkspace source, {
  int? revision,
  YorksV1WorkforceAccessStatus? workforceAccess,
}) => YorksV1UserPermissionWorkspace(
  schemaVersion: source.schemaVersion,
  authorizationMode: source.authorizationMode,
  generatedAt: source.generatedAt,
  actor: source.actor,
  target: source.target,
  revision: revision ?? source.revision,
  catalog: source.catalog,
  assignments: source.assignments,
  projects: source.projects,
  recentHistory: source.recentHistory,
  workforceAccess: workforceAccess ?? source.workforceAccess,
);

YorksV1PermissionCapabilityAccess _workforceCapability({
  required String key,
  required String action,
  required List<String> dependencies,
  bool effective = false,
}) {
  final catalog = YorksV1PermissionCatalogEntry(
    key: key,
    module: 'workforce',
    action: action,
    label: action,
    description: 'Protected Workforce capability.',
    riskLevel: YorksV1PermissionRiskLevel.critical,
    allowedScopes: const [YorksV1PermissionScopeKind.organization],
    requiresProjectAccess: false,
    dependencies: dependencies,
    runtimeStatus: YorksV1PermissionRuntimeStatus.operational,
    isAssignable: true,
    displayOrder: 410,
  );
  return YorksV1PermissionCapabilityAccess(
    catalog: catalog,
    authorizationMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
    roleDefault: YorksV1PermissionRoleDefault(
      capabilityKey: key,
      role: YorksV1Role.projectEngineer,
      isGranted: false,
    ),
    organizationSummaryVisible: true,
    authoritativeEffective: effective,
    authoritativeSource: effective
        ? YorksV1PermissionEffectiveSource.explicitGrant
        : YorksV1PermissionEffectiveSource.none,
    candidateEffective: effective,
    candidateSource: effective
        ? YorksV1PermissionEffectiveSource.explicitGrant
        : YorksV1PermissionEffectiveSource.none,
    hasParity: true,
    actorCanDelegate: true,
    actorDelegableScopes: const [YorksV1PermissionScopeKind.organization],
    projectOverrides: const [],
  );
}

class _FakePermissionRepository
    implements
        YorksV1PermissionRepository,
        YorksV1WorkforceAccessPermissionRepository {
  _FakePermissionRepository({
    required this.workspace,
    required this.canManage,
    this.initialLoad,
  });

  YorksV1UserPermissionWorkspace workspace;
  final bool canManage;
  final Completer<YorksV1UserPermissionWorkspace>? initialLoad;
  YorksV1ApplyPermissionChangesInput? lastBatch;
  bool? lastAssignOrganizationResponsibility;
  String? lastResponsibilityReason;
  var _initialReturned = false;

  @override
  Future<YorksV1UserPermissionWorkspace> getUserWorkspace({
    required String targetAppUserId,
  }) {
    if (!_initialReturned && initialLoad != null) {
      _initialReturned = true;
      return initialLoad!.future;
    }
    return Future.value(workspace);
  }

  @override
  Future<YorksV1UserPermissionWorkspace> applyChanges(
    YorksV1ApplyPermissionChangesInput input,
  ) async {
    lastBatch = input;
    workspace = _workspace(
      revision: workspace.revision + 1,
      authorizationMode: workspace.authorizationMode,
      capabilityMode: workspace.catalog.single.authorizationMode,
    );
    return workspace;
  }

  @override
  Future<YorksV1UserPermissionWorkspace> applyChangesWithWorkforce({
    required YorksV1ApplyPermissionChangesInput input,
    required bool assignOrganizationResponsibility,
  }) async {
    lastBatch = input;
    lastAssignOrganizationResponsibility = assignOrganizationResponsibility;
    workspace = _workspaceCopy(
      workspace,
      revision: workspace.revision + 1,
      workforceAccess: YorksV1WorkforceAccessStatus(
        referenceDate: DateTime.utc(2026, 8, 31),
        hasOperationalAccess: true,
        canAssignOrganizationResponsibility: true,
        activeWorkerCount: 0,
        activeTeamCount: 0,
        scheduledTeamCount: 0,
        organizationResponsibilityId: '5ae50000-0000-4000-8000-000000000001',
        organizationResponsibilityValidFrom: DateTime.utc(2026, 8, 31),
        organizationResponsibilityRecordVersion: 1,
      ),
    );
    return workspace;
  }

  @override
  Future<YorksV1UserPermissionWorkspace>
  assignWorkforceOrganizationResponsibility({
    required String targetAppUserId,
    required String reason,
    required String idempotencyKey,
  }) async {
    lastResponsibilityReason = reason;
    workspace = _workspaceCopy(
      workspace,
      workforceAccess: YorksV1WorkforceAccessStatus(
        referenceDate: DateTime.utc(2026, 8, 31),
        hasOperationalAccess: true,
        canAssignOrganizationResponsibility: true,
        activeWorkerCount: 0,
        activeTeamCount: 0,
        scheduledTeamCount: 0,
        organizationResponsibilityId: '5ae50000-0000-4000-8000-000000000002',
        organizationResponsibilityValidFrom: DateTime.utc(2026, 8, 31),
        organizationResponsibilityRecordVersion: 1,
      ),
    );
    return workspace;
  }

  @override
  Future<YorksV1UserPermissionWorkspace> clearAssignment(
    YorksV1ClearPermissionAssignmentInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1CurrentPermissionSnapshot> getCurrentSnapshot() async =>
      _currentSnapshot(canManage: canManage);

  @override
  Future<YorksV1UserAdminOptions> getUserAdminOptions({
    String? targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1PermissionHistoryPage> listHistory(
    YorksV1PermissionHistoryQuery query,
  ) async => YorksV1PermissionHistoryPage(
    schemaVersion: 1,
    targetAppUserId: query.targetAppUserId,
    items: const [],
  );

  @override
  Future<YorksV1UserPermissionWorkspace> setAssignment(
    YorksV1SetPermissionAssignmentInput input,
  ) => throw UnimplementedError();
}

YorksV1CurrentPermissionSnapshot _currentSnapshot({required bool canManage}) {
  YorksV1PermissionCapabilityAccess capability({
    required String key,
    required String action,
    required bool effective,
  }) {
    final catalog = YorksV1PermissionCatalogEntry(
      key: key,
      module: 'permissions',
      action: action,
      label: action == 'view' ? 'View permissions' : 'Manage permissions',
      description: 'Protected permission workspace authority.',
      riskLevel: YorksV1PermissionRiskLevel.critical,
      allowedScopes: const [YorksV1PermissionScopeKind.organization],
      requiresProjectAccess: false,
      dependencies: action == 'view'
          ? const []
          : const [YorksV1CapabilityKeys.permissionsView],
      runtimeStatus: YorksV1PermissionRuntimeStatus.operational,
      isAssignable: true,
      displayOrder: action == 'view' ? 330 : 331,
    );
    return YorksV1PermissionCapabilityAccess(
      catalog: catalog,
      authorizationMode: YorksV1PermissionCapabilityAuthorizationMode.enforced,
      roleDefault: YorksV1PermissionRoleDefault(
        capabilityKey: key,
        role: YorksV1Role.admin,
        isGranted: effective,
      ),
      organizationSummaryVisible: true,
      authoritativeEffective: effective,
      authoritativeSource: YorksV1PermissionEffectiveSource.roleDefault,
      candidateEffective: effective,
      candidateSource: YorksV1PermissionEffectiveSource.roleDefault,
      hasParity: true,
      actorCanDelegate: true,
      actorDelegableScopes: catalog.allowedScopes,
      projectOverrides: const [],
    );
  }

  return YorksV1CurrentPermissionSnapshot(
    schemaVersion: 1,
    authorizationMode: YorksV1PermissionAuthorizationMode.enforced,
    generatedAt: DateTime.utc(2026, 8, 24),
    user: YorksV1PermissionUser(
      appUserId: 'actor-app-user',
      displayName: 'Access Admin',
      exactRole: YorksV1Role.admin,
      isActive: true,
    ),
    revision: 3,
    capabilities: [
      capability(
        key: YorksV1CapabilityKeys.permissionsView,
        action: 'view',
        effective: true,
      ),
      capability(
        key: YorksV1CapabilityKeys.permissionsManage,
        action: 'manage',
        effective: canManage,
      ),
    ],
    projectAccess: const [],
  );
}

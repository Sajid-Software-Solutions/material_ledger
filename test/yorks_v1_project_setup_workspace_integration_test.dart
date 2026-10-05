import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_navigation_history.dart';
import 'package:material_ledger/app/yorks_v1_workspace_search.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/constants/app_spacing.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/core/widgets/yorks_mobile_ui.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_setup_entry_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_project_creation_draft_controller.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_search.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/notification_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_navigation_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_search_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_creation_draft_catalogue.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/widgets/notification_bell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _owner = 'workspace-setup-test-owner';
const _navigationKey = ValueKey('project-setup-workspace-navigation');
const _searchKey = ValueKey('project-setup-workspace-search');
const _drawerKey = ValueKey('yorks-workspace-navigation-drawer');
const _sidebarToggleKey = ValueKey('yorks-workspace-sidebar-toggle');
const _saveDraftKey = ValueKey('project-setup-save-draft');
const _engineerCapabilities = <String>{
  YorksV1CapabilityKeys.projectsView,
  YorksV1CapabilityKeys.projectsCreate,
  YorksV1CapabilityKeys.projectsEdit,
  YorksV1CapabilityKeys.materialRequestsView,
};
const _canonicalEngineerPaths = <String>{
  RoutePaths.engineerHome,
  RoutePaths.yorksV1Projects,
  RoutePaths.yorksV1MaterialRequests,
  RoutePaths.yorksV1DuctSizer,
  RoutePaths.yorksV1EspCalculator,
};

void main() {
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await font.load();
    // Native deferred library I/O completes outside each widgettest FakeAsync
    // zone; route tests still use the real entry and its FutureBuilder loader.
    await loadYorksV1ProjectSetupLibrary();
  });

  for (final size in [
    const Size(1536, 1024),
    const Size(1366, 768),
    const Size(1280, 800),
    const Size(360, 800),
  ]) {
    final desktop = size.width >= AppSpacing.yorksV1ShellDesktopBreakpoint;
    final wideContent = size.width - AppSpacing.sidebarWidth >= 1100;
    final platform = desktop
        ? 'desktop ${size.width.toInt()}x${size.height.toInt()}'
        : 'phone ${size.width.toInt()}x${size.height.toInt()}';

    testWidgets(
      '$platform Projects opens setup inside the original workspace chrome',
      (tester) async {
        final fixture = await _pumpWorkspace(
          tester,
          size: size,
          initialLocation: RoutePaths.yorksV1Projects,
        );
        final originalHeader = desktop
            ? tester.getRect(find.byKey(_sidebarToggleKey))
            : tester.getRect(find.byType(YorksMobileAppBar));
        await _openCreateProject(tester);
        final shell = find.byKey(
          ValueKey('project-setup-${wideContent ? 'desktop' : 'mobile'}-shell'),
        );
        expect(find.byType(YorksV1ProjectCreateFlowScreen), findsOneWidget);
        expect(find.byKey(_navigationKey), findsNothing);
        expect(find.byKey(_searchKey), findsNothing);
        expect(
          find.byKey(const ValueKey('project-setup-mobile-header')),
          findsNothing,
        );
        expect(find.byKey(_drawerKey), findsNothing);
        expect(find.byKey(_saveDraftKey), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);
        if (desktop) {
          expect(find.byKey(_sidebarToggleKey), findsOneWidget);
          expect(tester.getRect(find.byKey(_sidebarToggleKey)), originalHeader);
          expect(find.byType(NotificationBell), findsOneWidget);
          expect(
            find.text(YorksV1ShellStrings.companyName.primary),
            findsNWidgets(2),
          );
          expect(
            find.text(YorksV1ShellStrings.companyLegalName.primary),
            findsOneWidget,
          );
          _expectEngineerNavigation(_sidebarSurface());
          expect(
            tester.getRect(shell),
            Rect.fromLTWH(
              AppSpacing.sidebarWidth,
              AppSpacing.topBarHeight,
              size.width - AppSpacing.sidebarWidth,
              size.height - AppSpacing.topBarHeight,
            ),
          );
          if (wideContent) {
            final rail = tester.getRect(
              find.byKey(const ValueKey('project-setup-desktop-rail')),
            );
            expect(rail.left, AppSpacing.sidebarWidth);
            expect(rail.top, AppSpacing.topBarHeight);
            expect(rail.right, lessThan(tester.getRect(shell).right));
          } else {
            expect(
              find.byKey(const ValueKey('project-setup-desktop-rail')),
              findsNothing,
            );
          }
          // Collapsing the universal sidebar changes its own width. The
          // project stage rail stays inside the work area and never takes over
          // the application's left edge.
          await tester.tap(find.byKey(_sidebarToggleKey));
          await tester.pumpAndSettle();
          expect(fixture.container.read(yorksV1SidebarExpandedProvider), false);
          final collapsedContent = find.byKey(
            const ValueKey('project-setup-desktop-shell'),
          );
          expect(
            tester.getRect(collapsedContent).left,
            AppSpacing.sidebarCollapsedWidth,
          );
          expect(
            tester
                .getRect(
                  find.byKey(const ValueKey('project-setup-desktop-rail')),
                )
                .left,
            AppSpacing.sidebarCollapsedWidth,
          );
          expect(find.byKey(_sidebarToggleKey), findsOneWidget);
          expect(find.byType(NotificationBell), findsOneWidget);
          await tester.tap(find.byKey(_sidebarToggleKey));
          await tester.pumpAndSettle();
          expect(fixture.container.read(yorksV1SidebarExpandedProvider), true);
          _expectEngineerNavigation(_sidebarSurface());
        } else {
          expect(find.byKey(_sidebarToggleKey), findsNothing);
          expect(find.byType(YorksMobileAppBar), findsOneWidget);
          expect(
            tester.getRect(find.byType(YorksMobileAppBar)),
            originalHeader,
          );
          final header = tester.getRect(find.byType(YorksMobileAppBar));
          expect(tester.getRect(shell).top, header.bottom);
          expect(tester.getRect(shell).width, size.width);
          // The canonical workspace intentionally omits bottom navigation for
          // focused setup routes so it cannot cover the feature's fixed actions.
          expect(
            find.byKey(const ValueKey('yorks-mobile-navigation')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('yorks-compact-navigation-legacy')),
            findsNothing,
          );
        }
        expect(
          fixture.container
              .read(yorksNavigationHistoryProvider)
              .locations
              .map((location) => Uri.parse(location).path)
              .toList(),
          [RoutePaths.yorksV1Projects, RoutePaths.engineerCreateProject],
        );
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$platform shared search retains permitted canonical destinations',
      (tester) async {
        final fixture = await _pumpWorkspace(tester, size: size);
        // Ctrl+K belongs to the universal shell on every viewport, not a
        // replacement search widget built by project setup.
        await _openWorkspaceSearch(tester);
        final dialog = tester.widget<YorksV1WorkspaceSearchDialog>(
          find.byType(YorksV1WorkspaceSearchDialog),
        );
        expect(
          dialog.targets.map((target) => target.path).toSet(),
          _canonicalEngineerPaths,
        );
        expect(
          dialog.targets.map((target) => target.path),
          isNot(contains(RoutePaths.users)),
        );
        _expectEngineerNavigation(find.byType(YorksV1WorkspaceSearchDialog));
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$platform workspace navigation guards automatic-only draft and resumes it',
      (tester) async {
        final fixture = await _pumpWorkspace(tester, size: size);
        final originalDraftId = fixture.container
            .read(_activeProvider(fixture))
            .draftId;
        const proposedName =
            'Unpublished proposal preserved through navigation';
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          proposedName,
        );
        if (desktop) {
          await tester.tap(
            find.descendant(
              of: _sidebarSurface(),
              matching: find.text(YorksV1ShellStrings.projects.primary),
            ),
          );
        } else {
          await tester.tap(
            find
                .text(YorksV1ProjectSetupShellStrings.returnToProjects.primary)
                .first,
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
          findsOneWidget,
        );
        expect(
          fixture.router.routerDelegate.currentConfiguration.uri.path,
          RoutePaths.engineerCreateProject,
        );
        await tester.tap(find.text(YorksV1ProjectStrings.keepWorking.primary));
        await tester.pumpAndSettle();
        expect(find.byType(YorksV1ProjectCreateFlowScreen), findsOneWidget);
        expect(
          fixture.router.routerDelegate.currentConfiguration.uri.path,
          RoutePaths.engineerCreateProject,
        );
        if (desktop) {
          await tester.tap(
            find.descendant(
              of: _sidebarSurface(),
              matching: find.text(YorksV1ShellStrings.projects.primary),
            ),
          );
        } else {
          await tester.tap(
            find
                .text(YorksV1ProjectSetupShellStrings.returnToProjects.primary)
                .first,
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(YorksV1ProjectStrings.leaveWithSavedDraft.primary),
        );
        await tester.pumpAndSettle();
        _expectPortfolio(fixture);
        final draft = fixture.container.read(_activeProvider(fixture));
        expect(draft.name, proposedName);
        expect(draft.storageState, YorksV1ProjectDraftStorageState.saved);
        expect(draft.acknowledgedRevision, draft.revision);

        await _resumeDraft(tester, originalDraftId);
        _expectResumedDraft(tester, fixture, originalDraftId, proposedName);
        expect(
          fixture.container
              .read(yorksNavigationHistoryProvider)
              .locations
              .map((location) => Uri.parse(location).path)
              .toList(),
          [
            RoutePaths.engineerCreateProject,
            RoutePaths.yorksV1Projects,
            RoutePaths.engineerCreateProject,
          ],
        );
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$platform explicit Save draft acknowledges storage and Back resumes that draft',
      (tester) async {
        final fixture = await _pumpWorkspace(
          tester,
          size: size,
          initialLocation: RoutePaths.yorksV1Projects,
        );
        expect(_allDraftCards(), findsNothing);
        await _openCreateProject(tester);
        final originalDraftId = fixture.container
            .read(_activeProvider(fixture))
            .draftId;
        const proposedName = 'Explicitly saved inside Yorks workspace';
        const proposedReference = 'YRA-WORKSPACE-LOCAL';
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-reference')),
          proposedReference,
        );
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          proposedName,
        );
        await tester.ensureVisible(find.byKey(_saveDraftKey));
        await tester.pumpAndSettle();
        expect(find.byKey(_saveDraftKey).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.byKey(_saveDraftKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_saveDraftKey));
        await tester.pumpAndSettle();
        final saved = fixture.container.read(_activeProvider(fixture));
        expect(saved.storageState, YorksV1ProjectDraftStorageState.saved);
        expect(saved.acknowledgedRevision, saved.revision);
        expect(
          find.text(YorksV1ProjectStrings.draftSaved.primary),
          findsOneWidget,
        );
        final storageKey = fixture.container
            .read(_activeProvider(fixture).notifier)
            .storageKey;
        final stored = fixture.preferences.getString(storageKey);
        expect(stored, isNotNull);
        final envelope = jsonDecode(stored!) as Map<String, dynamic>;
        final restored = YorksV1ProjectCreationDraft.fromJson(
          Map<String, dynamic>.from(envelope['draft'] as Map),
        );
        expect(restored.draftId, originalDraftId);
        expect(restored.name, proposedName);

        // Match the reported Save draft -> Back to projects sequence. A
        // confirmed explicit save of unchanged input needs no leave warning.
        final footerExit = find.text(
          YorksV1ProjectSetupShellStrings.returnToProjects.primary,
        );
        expect(footerExit, findsOneWidget);
        await tester.tap(footerExit);
        await tester.pumpAndSettle();
        expect(
          find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
          findsNothing,
        );
        _expectPortfolio(fixture);
        final localCard = _allDraftCards();
        expect(localCard, findsOneWidget);
        expect(
          find.descendant(
            of: localCard,
            matching: find.textContaining(proposedReference),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: localCard,
            matching: find.textContaining(proposedName),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: localCard,
            matching: find.textContaining(
              YorksV1ProjectStrings.projectDetails.primary,
            ),
          ),
          findsOneWidget,
        );
        final resume = _allDraftResumes();
        expect(resume, findsOneWidget);
        expect(tester.getSize(resume).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(resume).width, greaterThanOrEqualTo(44));
        final beforeSummaryRead = fixture.preferences.getString(storageKey);
        await tester.pumpAndSettle();
        expect(fixture.preferences.getString(storageKey), beforeSummaryRead);
        await Scrollable.ensureVisible(tester.element(resume), alignment: .5);
        await tester.pumpAndSettle();
        expect(resume.hitTestable(), findsOneWidget);
        await tester.tap(resume);
        await tester.pumpAndSettle();
        _expectResumedDraft(tester, fixture, originalDraftId, proposedName);
        expect(
          fixture.container.read(_activeProvider(fixture)).reference,
          proposedReference,
        );
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(1536, 1024), const Size(360, 800)]) {
    testWidgets(
      '${size.width} saved A and new B stay independent and explicitly resumable',
      (tester) async {
        final fixture = await _pumpWorkspace(
          tester,
          size: size,
          initialLocation: RoutePaths.yorksV1Projects,
        );
        await _openCreateProject(tester);
        final aProvider = _activeProvider(fixture);
        final aWriter = fixture.container.read(aProvider.notifier);
        final aId = fixture.container.read(aProvider).draftId;
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-reference')),
          'LOCAL-A',
        );
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          'Saved project Alpha',
        );
        final date = find.byKey(
          ValueKey(
            'yorks-v1-project-date-${YorksV1ProjectStrings.startDate.en}',
          ),
        );
        await tester.ensureVisible(date);
        await tester.enterText(date, '12/');
        await _tapSaveDraft(tester);
        await aWriter.save(
          fixture.container
              .read(aProvider)
              .copyWith(
                attachments: const [
                  YorksV1ProjectAttachmentInput(
                    localId: 'alpha-local-file',
                    fileName: 'alpha-plan.pdf',
                    mimeType: 'application/pdf',
                    sizeBytes: 3,
                    contentHash: 'alpha-exact-hash',
                    categoryKey: 'drawing',
                  ),
                ],
              ),
        );
        await tester.pumpAndSettle();
        await _tapSaveDraft(tester);
        expect(fixture.container.read(aProvider).isAcknowledged, true);
        await tester.tap(
          find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
        );
        await tester.pumpAndSettle();
        _expectPortfolio(fixture);
        expect(_draftCard(aId), findsOneWidget);
        final exactA = fixture.preferences.getString(aWriter.storageKey);

        await _openCreateProject(tester);
        final bProvider = _activeProvider(fixture);
        final bId = fixture.container.read(bProvider).draftId;
        final b = fixture.container.read(bProvider);
        expect(bId, isNot(aId));
        expect(
          b.creationIdempotencyKey,
          isNot(fixture.container.read(aProvider).creationIdempotencyKey),
        );
        expect(b.reference, isEmpty);
        expect(b.name, isEmpty);
        expect(b.notes, isNull);
        expect(b.attachments, isEmpty);
        expect(b.buildings, isEmpty);
        expect(b.rawEditorState['dateStartText'] ?? '', isEmpty);
        expect(fixture.preferences.getString(aWriter.storageKey), exactA);
        for (final field in [
          'yorks-v1-project-reference',
          'yorks-v1-project-name',
        ]) {
          final input = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey(field)),
              matching: find.byType(EditableText),
            ),
          );
          expect(input.controller.text, isEmpty);
        }
        expect(
          fixture
              .router
              .routeInformationProvider
              .value
              .uri
              .queryParameters['draft'],
          bId,
        );
        // The URL identifies this exact proposal. Independent restoration is
        // exercised by the storage/provider tests and live browser verification.
        expect(fixture.container.read(_activeProvider(fixture)).draftId, bId);
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-reference')),
          'LOCAL-B',
        );
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          'Saved project Beta',
        );
        await _tapSaveDraft(tester);
        await tester.tap(
          find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
        );
        await tester.pumpAndSettle();
        _expectPortfolio(fixture);
        expect(_allDraftCards(), findsNWidgets(2));
        expect(_draftCard(aId), findsOneWidget);
        expect(_draftCard(bId), findsOneWidget);
        expect(fixture.preferences.getString(aWriter.storageKey), exactA);

        await _resumeDraft(tester, aId);
        _expectResumedDraft(tester, fixture, aId, 'Saved project Alpha');
        final resumedA = fixture.container.read(_activeProvider(fixture));
        expect(resumedA.reference, 'LOCAL-A');
        expect(resumedA.rawEditorState['dateStartText'], '12/');
        expect(resumedA.attachments.single.localId, 'alpha-local-file');
        expect(resumedA.attachments.single.contentHash, 'alpha-exact-hash');
        expect(
          resumedA.attachments.single.category,
          YorksV1ProjectAttachmentCategory.drawing,
        );
        await _tapSaveDraft(tester);
        await tester.tap(
          find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
        );
        await tester.pumpAndSettle();
        expect(_allDraftCards(), findsNWidgets(2));
        await _resumeDraft(tester, bId);
        _expectResumedDraft(tester, fixture, bId, 'Saved project Beta');
        final resumedB = fixture.container.read(_activeProvider(fixture));
        expect(resumedB.reference, 'LOCAL-B');
        expect(resumedB.attachments, isEmpty);
        expect(resumedB.rawEditorState['dateStartText'] ?? '', isEmpty);
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(1536, 1024), const Size(360, 800)]) {
    for (final retained in [true, false]) {
      testWidgets(
        '${size.width} Resume edits latest A without Take over, retained=$retained',
        (tester) async {
          final fixture = await _pumpWorkspace(
            tester,
            size: size,
            initialLocation: RoutePaths.yorksV1Projects,
          );
          final storage = fixture.container.read(
            yorksV1ProjectDraftAtomicStorageProvider,
          );
          final backend = fixture.container.read(
            yorksV1ProjectDraftBackendIdentityProvider,
          );
          YorksV1ProjectCreationDraftController? cached;
          ValueChanged<String>? staleInput;
          late YorksV1ProjectCreationDraft originalA;
          late String aKey;
          if (retained) {
            await _openCreateProject(tester);
            final aProvider = _activeProvider(fixture);
            cached = fixture.container.read(aProvider.notifier);
            await tester.enterText(
              find.byKey(const ValueKey('yorks-v1-project-reference')),
              'DIRECT-RESUME-A',
            );
            await tester.enterText(
              find.byKey(const ValueKey('yorks-v1-project-name')),
              'First saved Alpha',
            );
            final field = find
                .ancestor(
                  of: find.descendant(
                    of: find.byKey(const ValueKey('yorks-v1-project-name')),
                    matching: find.byType(EditableText),
                  ),
                  matching: find.byType(TextFormField),
                )
                .first;
            staleInput = tester.widget<TextFormField>(field).onChanged;
            await _tapSaveDraft(tester);
            originalA = cached!.state;
            aKey = cached.storageKey;
            await tester.tap(
              find.text(
                YorksV1ProjectSetupShellStrings.returnToProjects.primary,
              ),
            );
            await tester.pumpAndSettle();
            _expectPortfolio(fixture);
          } else {
            final root = yorksV1ProjectDraftStorageKey(
              backendIdentity: backend,
              ownerAuthUserId: _owner,
              mode: YorksV1ProjectDraftMode.create,
            );
            var sequence = 0;
            final installed = YorksV1ProjectCreationDraftController(
              ownerAuthUserId: _owner,
              backendIdentity: backend,
              storageKey: '$root:draft:installed-resume-a',
              storage: storage,
              idempotencyKeyFactory: () => 'installed-${sequence++}',
              initialDraftId: 'installed-resume-a',
              catalogue: YorksV1ProjectCreationDraftCatalogue(
                scopeKey: root,
                ownerAuthUserId: _owner,
                backendIdentity: backend,
              ),
              journalScopeKey: root,
            );
            addTearDown(installed.dispose);
            await installed.initialized;
            await installed.save(
              installed.state.copyWith(
                reference: 'DIRECT-RESUME-A',
                name: 'First saved Alpha',
              ),
            );
            originalA = installed.state;
            aKey = installed.storageKey;
            // Keep the installed lease to reproduce a browser reload's existing writer.
          }
          await _openCreateProject(tester);
          final bProvider = _activeProvider(fixture);
          await tester.enterText(
            find.byKey(const ValueKey('yorks-v1-project-name')),
            'Independent saved Beta',
          );
          await _tapSaveDraft(tester);
          final bWriter = fixture.container.read(bProvider.notifier);
          await tester.tap(
            find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
          );
          await tester.pumpAndSettle();
          _expectPortfolio(fixture);
          await bWriter.flush();
          final exactB = fixture.preferences.getString(bWriter.storageKey);
          var ids = 0;
          final foreign = YorksV1ProjectCreationDraftController(
            ownerAuthUserId: _owner,
            backendIdentity: backend,
            storageKey: aKey,
            storage: storage,
            idempotencyKeyFactory: () => 'foreign-resume-${ids++}',
            initialDraftId: originalA.draftId,
            requireExistingRecord: true,
            journalScopeKey: bWriter.journalScopeKey,
          );
          addTearDown(foreign.dispose);
          await foreign.initialized;
          await foreign.takeOver();
          await foreign.save(
            foreign.state.copyWith(
              name: 'Latest Alpha from another tab',
              notes: 'Latest exact notes   ',
              parties: const [
                YorksV1ProjectPartyInput(
                  kind: YorksV1ProjectPartyKind.consultant,
                  name: 'Retained consultant',
                ),
              ],
              buildings: const [
                YorksV1ProjectBuildingInput(
                  localRowId: 'resume-building',
                  code: 'R1',
                  name: 'Retained building',
                  floorsOrLevels: ['Ground', 'Roof'],
                  hasFrpRoom: false,
                ),
              ],
              rawEditorState: {
                ...foreign.state.rawEditorState,
                'dateStartText': '12/',
              },
              attachments: const [
                YorksV1ProjectAttachmentInput(
                  localId: 'latest-file',
                  fileName: 'latest.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 3,
                  categoryKey: 'drawing',
                ),
              ],
            ),
          );
          final latest = foreign.state;
          if (cached != null) {
            await expectLater(
              cached.verifyOwnership(),
              throwsA(isA<ProjectDraftStorageException>()),
            );
            expect(cached.state.isReadOnly, true);
          }
          await tester.pumpAndSettle();
          await _resumeDraft(tester, originalA.draftId);
          _expectResumedDraft(tester, fixture, originalA.draftId, latest.name);
          expect(
            find.text(YorksV1ProjectStrings.takeOverDraft.primary),
            findsNothing,
          );
          final provider = _activeProvider(fixture);
          final resumed = fixture.container.read(provider);
          expect(resumed.isReadOnly, false);
          expect(resumed.writerEpoch, greaterThan(latest.writerEpoch));
          expect(resumed.notes, latest.notes);
          expect(resumed.rawEditorState['dateStartText'], '12/');
          expect(
            resumed.attachments.single.toDraftJson(),
            latest.attachments.single.toDraftJson(),
          );
          if (cached != null) {
            expect(fixture.container.read(provider.notifier), same(cached));
          }
          final beforeLate = fixture.preferences.getString(aKey);
          staleInput?.call(
            'Old form callback must not overwrite resumed Alpha',
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(fixture.preferences.getString(aKey), beforeLate);
          await tester.enterText(
            find.byKey(const ValueKey('yorks-v1-project-name')),
            'Immediately editable Alpha',
          );
          await _tapSaveDraft(tester);
          expect(
            find.text(YorksV1ProjectStrings.changedDuringLocalSave.primary),
            findsNothing,
          );
          expect(
            fixture.container.read(provider).name,
            'Immediately editable Alpha',
          );
          expect(fixture.container.read(provider).isAcknowledged, true);
          await expectLater(
            foreign.save(latest.copyWith(name: 'Former tab stale overwrite')),
            throwsA(isA<ProjectDraftStorageException>()),
          );
          expect(fixture.preferences.getString(bWriter.storageKey), exactB);
          await tester.tap(
            find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
            findsNothing,
          );
          _expectPortfolio(fixture);
          expect(fixture.commands.calls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [const Size(1536, 1024), const Size(360, 800)]) {
    testWidgets(
      '${size.width} fenced old tab keeps pending frontend text and cannot overwrite resumed data',
      (tester) async {
        final fixture = await _pumpWorkspace(
          tester,
          size: size,
          initialLocation: RoutePaths.yorksV1Projects,
        );
        await _openCreateProject(tester);
        final provider = _activeProvider(fixture);
        final old = fixture.container.read(provider.notifier);
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          'Original acknowledged Alpha',
        );
        await _tapSaveDraft(tester);
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          'Private pending old-tab typing',
        );
        await tester.pump(); // Stay inside the real draft debounce window.
        final storage = fixture.container.read(
          yorksV1ProjectDraftAtomicStorageProvider,
        );
        var keys = 0;
        final resumed = YorksV1ProjectCreationDraftController(
          ownerAuthUserId: _owner,
          backendIdentity: old.state.backendIdentity,
          storageKey: old.storageKey,
          storage: storage,
          initialDraftId: old.state.draftId,
          requireExistingRecord: true,
          journalScopeKey: old.journalScopeKey,
          idempotencyKeyFactory: () => 'other-pending-tab-${keys++}',
        );
        addTearDown(resumed.dispose);
        await resumed.initialized;
        expect(
          await resumed.resumeEditing(
            expectedDraftId: old.state.draftId,
            canAcquire: () => true,
          ),
          true,
        );
        await resumed.save(
          resumed.state.copyWith(name: 'Acknowledged resumed winner'),
        );
        final exactWinner = fixture.preferences.getString(resumed.storageKey);
        await expectLater(
          old.verifyOwnership(),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('yorks-v1-project-name'));
        final editor = tester.widget<EditableText>(
          find.descendant(of: name, matching: find.byType(EditableText)),
        );
        expect(editor.controller.text, 'Private pending old-tab typing');
        expect(editor.readOnly, true);
        expect(old.state.isReadOnly, true);
        expect(fixture.preferences.getString(resumed.storageKey), exactWinner);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: name, matching: find.byType(EditableText)),
              )
              .controller
              .text,
          'Private pending old-tab typing',
        );
        expect(fixture.preferences.getString(resumed.storageKey), exactWinner);
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'backend-unavailable Resume preserves local editing while remote Create stays disabled',
    (tester) async {
      const id = 'unavailable-resume';
      final context = YorksV1ProjectCreationDraftContext(
        ownerAuthUserId: _owner,
        draftId: id,
        entry: YorksV1ProjectCreationDraftEntry.newProposal,
      );
      final provider = yorksV1ProjectSetupCreationDraftByIdProvider(context);
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1ProjectSetupDraftPath(id),
        permission:
            yorksV1TrustedFeaturePermissionState(
              role: YorksV1Role.projectEngineer,
              capabilities: _engineerCapabilities,
              stale: true,
            ).copyWith(
              error: const YorksV1DomainException(
                YorksV1DomainErrorCode.backendUnavailable,
              ),
            ),
        seed: (container, preferences) async {
          final writer = container.read(provider.notifier);
          await writer.initialized;
          await writer.save(
            writer.state.copyWith(
              reference: 'OFFLINE-RESUME',
              name: 'Retained local proposal',
              buildings: const [
                YorksV1ProjectBuildingInput(name: 'Known physical building'),
              ],
            ),
          );
        },
      );
      expect(
        find.text(YorksV1ProjectStrings.takeOverDraft.primary),
        findsNothing,
      );
      expect(fixture.container.read(provider).isReadOnly, false);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Local progress during backend outage',
      );
      await _tapSaveDraft(tester);
      expect(
        fixture.container.read(provider).name,
        'Local progress during backend outage',
      );
      expect(fixture.container.read(provider).isAcknowledged, true);
      for (var stage = 0; stage < 4; stage++) {
        final next = find.byKey(const ValueKey('yorks-v1-project-continue'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(
        fixture.container.read(provider).currentStage,
        YorksV1ProjectCreationStage.reviewAndCreate,
      );
      final create = tester.widget<FilledButton>(
        find.byKey(const ValueKey('yorks-v1-project-create')),
      );
      expect(create.onPressed, isNull);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared deferred Edit loads the authorized existing version without creating a proposal',
    (tester) async {
      const projectId = '61000000-0000-4000-8000-000000000001';
      final known = YorksV1ProjectPortfolioItem(
        project: YorksV1Project(
          id: projectId,
          reference: 'KNOWN-EDIT',
          name: 'Authorized existing project',
          state: YorksV1ProjectLifecycle.active,
          version: 9,
          createdAt: DateTime.utc(2026, 10, 5),
          updatedAt: DateTime.utc(2026, 10, 5),
        ),
        activeBuildingCount: 1,
        activeProjectEngineerCount: 1,
        activeSiteEngineerCount: 0,
        buildings: const [
          YorksV1ProjectBuildingInput(
            sourceScopeId: 'retained-building-scope',
            code: 'E1',
            name: 'Existing building',
            hasFrpRoom: false,
          ),
        ],
      );
      final release = Completer<void>();
      Future<void> loader() async {
        await release.future;
        await loadYorksV1ProjectSetupLibrary();
      }

      late _ReadSpyDraftStorage storage;
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1ProjectEditPath(projectId),
        setupLoader: loader,
        portfolio: [known],
        settle: false,
        draftStorageFactory: (preferences) =>
            storage = _ReadSpyDraftStorage(preferences),
      );
      expect(
        find.byKey(const ValueKey('yorks-v1-project-setup-loading')),
        findsOneWidget,
      );
      expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
      expect(storage.transactions, 0);
      release.complete();
      await _settleDeferredSetup(tester);
      expect(find.byType(YorksV1ProjectEditFlowScreen), findsOneWidget);
      expect(find.byType(YorksV1ProjectCreateFlowScreen), findsOneWidget);
      final provider = yorksV1ProjectEditDraftProvider(
        const YorksV1ProjectEditDraftContext(
          ownerAuthUserId: _owner,
          projectId: projectId,
        ),
      );
      await fixture.container.read(provider.notifier).initialized;
      await tester.pumpAndSettle();
      final proposal = fixture.container.read(provider);
      expect(proposal.mode, YorksV1ProjectDraftMode.edit);
      expect(proposal.projectId, projectId);
      expect(proposal.baseVersion, 9);
      expect(proposal.reference, 'KNOWN-EDIT');
      expect(proposal.name, 'Authorized existing project');
      expect(
        proposal.buildings.single.sourceScopeId,
        'retained-building-scope',
      );
      expect(proposal.buildings.single.hasFrpRoom, false);
      final name = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('yorks-v1-project-name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.controller.text, known.project.name);
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1ProjectEditPath(projectId),
      );
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deferred load Retry rechecks logout before exposing or claiming any draft',
    (tester) async {
      var owner = _owner as String?;
      var attempts = 0;
      final release = Completer<void>();
      Future<void> loader() async {
        attempts++;
        if (attempts == 1) throw StateError('Synthetic asset load failure');
        await release.future;
        await loadYorksV1ProjectSetupLibrary();
      }

      late _ReadSpyDraftStorage storage;
      final fixture = await _pumpWorkspace(
        tester,
        setupLoader: loader,
        currentOwner: () => owner,
        draftStorageFactory: (preferences) =>
            storage = _ReadSpyDraftStorage(preferences),
      );
      expect(
        find.byKey(const ValueKey('yorks-v1-project-setup-load-failed')),
        findsOneWidget,
      );
      expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
      expect(storage.transactions, 0);
      final retry = find.byKey(
        const ValueKey('yorks-v1-project-setup-load-retry'),
      );
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
      await tester.tap(retry);
      await tester.pump();
      expect(attempts, 2);
      expect(
        find.byKey(const ValueKey('yorks-v1-project-setup-loading')),
        findsOneWidget,
      );
      owner = null;
      fixture.container.invalidate(yorksV1AuthUserIdProvider);
      await tester.pump();
      release.complete();
      await _settleDeferredSetup(tester);
      expect(find.byKey(const ValueKey('yorks-v1-project-name')), findsNothing);
      expect(
        find.byKey(const ValueKey('project-setup-save-draft')),
        findsNothing,
      );
      expect(storage.transactions, 0);
      expect(fixture.preferences.getKeys(), isEmpty);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canonical same-ID anchor retains the mounted editor and its input controllers',
    (tester) async {
      final fixture = await _pumpWorkspace(tester, settle: false);
      await _settleDeferredSetup(tester);
      final feature = find.byType(YorksV1ProjectCreateFlowScreen);
      final originalState = tester.state(feature);
      final name = find.byKey(const ValueKey('yorks-v1-project-name'));
      final originalController = tester
          .widget<EditableText>(
            find.descendant(of: name, matching: find.byType(EditableText)),
          )
          .controller;
      await _settleFreshAnchor(tester);
      expect(tester.state(feature), same(originalState));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: name, matching: find.byType(EditableText)),
            )
            .controller,
        same(originalController),
      );
      final aId = fixture.container.read(_activeProvider(fixture)).draftId;
      expect(
        fixture
            .router
            .routeInformationProvider
            .value
            .uri
            .queryParameters['draft'],
        aId,
      );
      await tester.enterText(name, 'Retained editor Alpha');
      await _tapSaveDraft(tester);
      await tester.tap(
        find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
      );
      await tester.pumpAndSettle();
      await _openCreateProject(tester);
      expect(tester.state(feature), isNot(same(originalState)));
      expect(
        fixture.container.read(_activeProvider(fixture)).draftId,
        isNot(aId),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: name, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'captured A input and category callbacks cannot write after B opens',
    (tester) async {
      final aContext = YorksV1ProjectCreationDraftContext(
        ownerAuthUserId: _owner,
        draftId: 'callback-alpha',
        entry: YorksV1ProjectCreationDraftEntry.newProposal,
      );
      final aProvider = yorksV1ProjectSetupCreationDraftByIdProvider(aContext);
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1ProjectSetupDraftPath(
          aContext.draftId,
        ),
        seed: (container, preferences) async {
          final writer = container.read(aProvider.notifier);
          await writer.initialized;
          await writer.save(
            writer.state.copyWith(
              reference: 'CALLBACK-A',
              name: 'Captured Alpha',
              visitedStages: YorksV1ProjectCreationStage.values.toSet(),
              attachments: const [
                YorksV1ProjectAttachmentInput(
                  localId: 'callback-file',
                  fileName: 'alpha.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 3,
                ),
              ],
            ),
          );
        },
      );
      final nameField = find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const ValueKey('yorks-v1-project-name')),
              matching: find.byType(EditableText),
            ),
            matching: find.byType(TextFormField),
          )
          .first;
      final capturedName = tester.widget<TextFormField>(nameField).onChanged!;
      final aWriter = fixture.container.read(aProvider.notifier);
      await aWriter.save(
        aWriter.state.copyWith(
          currentStage: YorksV1ProjectCreationStage.attachments,
        ),
      );
      await tester.pumpAndSettle();
      // Capture the product callback, rather than Flutter FormField.didChange,
      // which is correctly invalid once its own widget has been disposed.
      final picker = tester.widget<Widget>(
        find.byKey(
          const ValueKey('yorks-v1-desktop-file-category-callback-file'),
        ),
      );
      final capturedCategory =
          (picker as dynamic).onChanged
              as ValueChanged<YorksV1ProjectAttachmentCategory>;
      await _tapSaveDraft(tester);
      await tester.tap(
        find.descendant(
          of: _sidebarSurface(),
          matching: find.text(YorksV1ShellStrings.projects.primary),
        ),
      );
      await tester.pumpAndSettle();
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await tester.tap(
          find.text(YorksV1ProjectStrings.leaveWithSavedDraft.primary),
        );
        await tester.pumpAndSettle();
      }
      _expectPortfolio(fixture);
      await _openCreateProject(tester);
      final bProvider = _activeProvider(fixture);
      final b = fixture.container.read(bProvider);
      expect(b.draftId, isNot(aContext.draftId));
      await aWriter.flush();
      final exactA = fixture.preferences.getString(aWriter.storageKey);
      final exactB = b.toJson();
      capturedName('Stale captured Alpha text');
      capturedCategory(YorksV1ProjectAttachmentCategory.drawing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fixture.container.read(bProvider).toJson(), exactB);
      expect(fixture.preferences.getString(aWriter.storageKey), exactA);
      expect(
        fixture.container.read(aProvider).attachments.single.category,
        YorksV1ProjectAttachmentCategory.general,
      );
      final currentName = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('yorks-v1-project-name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(currentName.controller.text, isEmpty);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed unanchored B save blocks a query switch to saved A and retains typed B',
    (tester) async {
      late _ClaimGateDraftStorage storage;
      late YorksV1ProjectCreationDraft a;
      late String aKey;
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
        draftStorageFactory: (preferences) =>
            storage = _ClaimGateDraftStorage(preferences),
        seed: (container, preferences) async {
          final provider = yorksV1ProjectSetupCreationDraftProvider(_owner);
          final writer = container.read(provider.notifier);
          await writer.initialized;
          await writer.save(
            writer.state.copyWith(
              reference: 'RETAINED-A',
              name: 'Acknowledged Alpha',
            ),
          );
          a = writer.state;
          aKey = writer.storageKey;
          storage.failNewEnvelopeWrites = true;
        },
      );
      final exactA = fixture.preferences.getString(aKey);
      await _openCreateProject(tester);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'B unsaved progress',
      );
      await _tapSaveDraft(tester);
      expect(
        find.text(YorksV1ProjectStrings.localSaveFailed.primary),
        findsWidgets,
      );
      fixture.router.go(RoutePaths.yorksV1ProjectSetupDraftPath(a.draftId));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('yorks-v1-project-name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editor.controller.text, 'B unsaved progress');
      expect(
        GoRouterState.of(
          tester.element(find.byType(YorksV1ProjectCreateFlowScreen)),
        ).uri.queryParameters['draft'],
        isNot(a.draftId),
      );
      expect(fixture.preferences.getString(aKey), exactA);
      storage.failNewEnvelopeWrites = false;
      await _tapSaveDraft(tester);
      await _settleFreshAnchor(tester);
      final b = fixture.container.read(_activeProvider(fixture));
      expect(b.name, 'B unsaved progress');
      expect(b.isAcknowledged, true);
      expect(b.draftId, isNot(a.draftId));
      fixture.router.go(RoutePaths.yorksV1ProjectSetupDraftPath(a.draftId));
      await tester.pumpAndSettle();
      _expectResumedDraft(tester, fixture, a.draftId, 'Acknowledged Alpha');
      expect(
        fixture.container
            .read(
              yorksV1ProjectSetupCreationDraftByIdProvider(
                YorksV1ProjectCreationDraftContext(
                  ownerAuthUserId: _owner,
                  draftId: b.draftId,
                ),
              ),
            )
            .name,
        'B unsaved progress',
      );
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'untouched Create checkpoint stays hidden while a saved unfinished date resumes from Projects',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
      );
      expect(_allDraftCards(), findsNothing);
      await _openCreateProject(tester);
      final untouchedProvider = _activeProvider(fixture);
      await tester.tap(
        find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
      );
      await tester.pumpAndSettle();
      _expectPortfolio(fixture);
      final untouched = fixture.container.read(untouchedProvider);
      expect(untouched.rawEditorState['sectionContext'], isNotNull);
      expect(untouched.reference, isEmpty);
      expect(untouched.name, isEmpty);
      expect(_allDraftCards(), findsNothing);

      await _openCreateProject(tester);
      final provider = _activeProvider(fixture);
      final originalDraftId = fixture.container.read(provider).draftId;
      final date = find.byKey(
        ValueKey('yorks-v1-project-date-${YorksV1ProjectStrings.startDate.en}'),
      );
      await tester.ensureVisible(date);
      await tester.enterText(date, '12/');
      await tester.ensureVisible(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(YorksV1ProjectSetupShellStrings.returnToProjects.primary),
      );
      await tester.pumpAndSettle();
      _expectPortfolio(fixture);
      expect(_allDraftCards(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yorks-v1-local-draft-reference')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('yorks-v1-local-draft-name')),
        findsNothing,
      );
      await tester.tap(_allDraftResumes());
      await tester.pumpAndSettle();
      expect(fixture.container.read(provider).draftId, originalDraftId);
      expect(
        fixture.container.read(provider).rawEditorState['dateStartText'],
        '12/',
      );
      final input = tester.widget<EditableText>(
        find.descendant(of: date, matching: find.byType(EditableText)),
      );
      expect(input.controller.text, '12/');
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved unfinished building resumes its actual stage from the Projects card',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
      );
      await _openCreateProject(tester);
      final provider = _activeProvider(fixture);
      final writer = fixture.container.read(provider.notifier);
      final originalDraftId = fixture.container.read(provider).draftId;
      await writer.save(
        fixture.container
            .read(provider)
            .copyWith(
              reference: 'YRA-BUILDING-LOCAL',
              name: 'Unfinished building setup',
              siteLocation: 'Local setup test site',
              startDate: DateTime(2026, 10, 5),
            ),
      );
      await tester.pumpAndSettle();
      final continueButton = find.byKey(
        const ValueKey('yorks-v1-project-continue'),
      );
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(
        fixture.container.read(provider).currentStage,
        YorksV1ProjectCreationStage.buildings,
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-building-name')),
        'Unapplied roof building',
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-building-floors')),
        'Ground, Roof,',
      );
      await tester.ensureVisible(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      final saved = fixture.container.read(provider);
      expect(saved.buildings, isEmpty);
      expect(saved.rawEditorState['buildingName'], 'Unapplied roof building');
      expect(saved.rawEditorState['buildingFloors'], 'Ground, Roof,');
      expect(saved.acknowledgedRevision, saved.revision);
      await tester.tap(
        find.descendant(
          of: _sidebarSurface(),
          matching: find.text(YorksV1ShellStrings.projects.primary),
        ),
      );
      await tester.pumpAndSettle();
      _expectPortfolio(fixture);
      expect(
        find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
        findsNothing,
      );
      final card = _allDraftCards();
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            YorksV1ProjectStrings.buildings.primary,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(_allDraftResumes());
      await tester.pumpAndSettle();
      final resumed = fixture.container.read(provider);
      expect(resumed.draftId, originalDraftId);
      expect(resumed.currentStage, YorksV1ProjectCreationStage.buildings);
      for (final field in {
        'yorks-v1-building-name': 'Unapplied roof building',
        'yorks-v1-building-floors': 'Ground, Roof,',
      }.entries) {
        final input = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey(field.key)),
            matching: find.byType(EditableText),
          ),
        );
        expect(input.controller.text, field.value);
      }
      expect(resumed.buildings, isEmpty);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final boundary in [
    'flag-off',
    'role-denied',
    'capability-denied',
    'stale-permission',
    'different-owner',
    'different-backend',
  ]) {
    testWidgets(
      'Projects local setup card respects $boundary before private reads',
      (tester) async {
        late _ReadSpyDraftStorage storage;
        final originalKey = yorksV1ProjectDraftStorageKey(
          backendIdentity: 'local',
          ownerAuthUserId: _owner,
          mode: YorksV1ProjectDraftMode.create,
        );
        final role = boundary == 'role-denied'
            ? YorksV1Role.procurement
            : YorksV1Role.projectEngineer;
        final privateDraft =
            YorksV1ProjectCreationDraft.empty(
              ownerAuthUserId: _owner,
              creationIdempotencyKey: 'private-local-draft',
            ).copyWith(
              reference: 'PRIVATE-LOCAL-REF',
              name: 'Private saved local setup',
              revision: 7,
              acknowledgedRevision: 7,
              writerEpoch: 2,
              updatedAt: DateTime.utc(2026, 10, 5),
              storageState: YorksV1ProjectDraftStorageState.saved,
            );
        final envelope = jsonEncode({
          'recordVersion': 1,
          'ownerWriterId': 'retained-foreign-lease',
          'writerEpoch': 2,
          'retired': false,
          'draft': privateDraft.toJson(),
        });
        final fixture = await _pumpWorkspace(
          tester,
          initialLocation: RoutePaths.yorksV1Projects,
          role: role,
          ownerAuthUserId: boundary == 'different-owner'
              ? 'different-auth-owner'
              : _owner,
          backendIdentity: boundary == 'different-backend'
              ? 'https://isolated-other-project.invalid'
              : 'local',
          projectSetup: boundary != 'flag-off',
          permission: yorksV1TrustedFeaturePermissionState(
            role: role,
            capabilities: boundary == 'capability-denied'
                ? const {YorksV1CapabilityKeys.projectsView}
                : _engineerCapabilities,
            stale: boundary == 'stale-permission',
          ),
          draftStorageFactory: (preferences) =>
              storage = _ReadSpyDraftStorage(preferences),
          seed: (_, preferences) async {
            await preferences.setString(originalKey, envelope);
          },
        );
        expect(_allDraftCards(), findsNothing);
        expect(_allDraftResumes(), findsNothing);
        expect(find.textContaining(privateDraft.reference), findsNothing);
        expect(find.textContaining(privateDraft.name), findsNothing);
        expect(storage.readKeys, isNot(contains(originalKey)));
        if (!boundary.startsWith('different-')) {
          expect(storage.readKeys, isEmpty);
        }
        expect(storage.transactions, 0);
        expect(fixture.preferences.getString(originalKey), envelope);
        expect(fixture.commands.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '360px Arabic saved setup card keeps readable text and 44px Resume without acquiring its lease',
    (tester) async {
      late _ReadSpyDraftStorage storage;
      late String storageKey;
      late String envelope;
      final fixture = await _pumpWorkspace(
        tester,
        size: const Size(360, 800),
        initialLocation: RoutePaths.yorksV1Projects,
        language: AppLanguage.arabic,
        textScaler: const TextScaler.linear(2),
        draftStorageFactory: (preferences) =>
            storage = _ReadSpyDraftStorage(preferences),
        seed: (container, preferences) async {
          final draft =
              YorksV1ProjectCreationDraft.empty(
                ownerAuthUserId: _owner,
                creationIdempotencyKey: 'rtl-persisted-draft',
              ).copyWith(
                reference: 'YRA-RTL-LOCAL',
                name: 'مسودة مشروع محفوظة على هذا الجهاز لاختبار الاستئناف',
                currentStage: YorksV1ProjectCreationStage.buildings,
                revision: 3,
                acknowledgedRevision: 3,
                writerEpoch: 1,
                updatedAt: DateTime.utc(2026, 10, 5),
                storageState: YorksV1ProjectDraftStorageState.saved,
              );
          storageKey = yorksV1ProjectDraftStorageKey(
            backendIdentity: draft.backendIdentity,
            ownerAuthUserId: _owner,
            mode: YorksV1ProjectDraftMode.create,
          );
          envelope = jsonEncode({
            'recordVersion': 1,
            'ownerWriterId': 'other-browser-tab-writer',
            'writerEpoch': 1,
            'retired': false,
            'draft': draft.toJson(),
          });
          await preferences.setString(storageKey, envelope);
        },
      );
      final card = _allDraftCards();
      expect(card, findsOneWidget);
      expect(Directionality.of(tester.element(card)), TextDirection.rtl);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('YRA-RTL-LOCAL'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            YorksV1ProjectStrings.buildings.active(AppLanguage.arabic),
          ),
        ),
        findsOneWidget,
      );
      final resume = _allDraftResumes();
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      final rect = tester.getRect(resume);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(storage.transactions, 0);
      expect(fixture.preferences.getString(storageKey), envelope);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop setup exits only from its first-stage footer and later footer Back keeps the draft',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
      );
      await _openCreateProject(tester);
      final universalBack = find.byKey(const ValueKey('yorks-workspace-back'));
      final headerBackRect = tester.getRect(universalBack);
      final rail = find.byKey(const ValueKey('project-setup-desktop-rail'));
      final returnLabel =
          YorksV1ProjectSetupShellStrings.returnToProjects.primary;
      expect(
        find.descendant(of: rail, matching: find.text(returnLabel)),
        findsNothing,
      );
      expect(find.text(returnLabel), findsOneWidget);
      final footerExit = find.ancestor(
        of: find.text(returnLabel),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(footerExit, findsOneWidget);
      expect(
        tester.getRect(footerExit).top,
        greaterThanOrEqualTo(tester.getRect(rail).bottom),
      );
      expect(find.byKey(_sidebarToggleKey), findsOneWidget);
      await tester.tap(footerExit);
      await tester.pumpAndSettle();
      _expectPortfolio(fixture);
      expect(
        find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
        findsNothing,
      );

      await _openCreateProject(tester);
      final provider = _activeProvider(fixture);
      final writer = fixture.container.read(provider.notifier);
      final draftId = fixture.container.read(provider).draftId;
      await writer.save(
        fixture.container
            .read(provider)
            .copyWith(
              reference: 'FOOTER-NAVIGATION',
              name: 'Retain this proposal through previous-step navigation',
              siteLocation: 'Desktop footer test site',
              startDate: DateTime(2026, 10, 4),
            ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-continue')));
      await tester.pumpAndSettle();
      expect(
        fixture.container.read(provider).currentStage,
        YorksV1ProjectCreationStage.partiesAndAccess,
      );
      expect(find.text(returnLabel), findsNothing);
      final previous = find.ancestor(
        of: find.text(YorksV1ProjectStrings.back.primary),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(previous, findsOneWidget);
      expect(
        tester.getRect(previous).top,
        greaterThanOrEqualTo(tester.getRect(rail).bottom),
      );
      expect(tester.getRect(universalBack), headerBackRect);
      expect(find.byKey(_sidebarToggleKey), findsOneWidget);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      final resumed = fixture.container.read(provider);
      expect(resumed.currentStage, YorksV1ProjectCreationStage.projectDetails);
      expect(resumed.draftId, draftId);
      expect(resumed.reference, 'FOOTER-NAVIGATION');
      expect(
        resumed.name,
        'Retain this proposal through previous-step navigation',
      );
      expect(
        fixture.router.routerDelegate.currentConfiguration.last.matchedLocation,
        RoutePaths.engineerCreateProject,
      );
      expect(find.text(returnLabel), findsOneWidget);
      expect(
        find.descendant(of: rail, matching: find.text(returnLabel)),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
        findsNothing,
      );
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual save and unfinished input survive desktop phone and transient viewport resize',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
      );
      await _openCreateProject(tester);
      final flowState = tester.state(
        find.byType(YorksV1ProjectCreateFlowScreen),
      );
      final draftId = fixture.container.read(_activeProvider(fixture)).draftId;
      const proposedName = 'Viewport recovery preserves the saved proposal';
      const partialDate = '12/10/';
      const notes = 'Unpublished notes remain local through every layout.';
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        proposedName,
      );
      final date = find.byKey(
        ValueKey('yorks-v1-project-date-${YorksV1ProjectStrings.startDate.en}'),
      );
      await tester.ensureVisible(date);
      await tester.enterText(date, partialDate);
      final notesField = find.byKey(const ValueKey('yorks-v1-project-notes'));
      await tester.ensureVisible(notesField);
      await tester.enterText(notesField, notes);
      await tester.ensureVisible(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_saveDraftKey));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.draftSaved.primary),
        findsOneWidget,
      );
      final saved = fixture.container.read(_activeProvider(fixture));
      expect(saved.isAcknowledged, true);
      expect(saved.rawEditorState['dateStartText'], partialDate);
      final notesEditor = tester.widget<EditableText>(
        find.descendant(of: notesField, matching: find.byType(EditableText)),
      );
      final controller = notesEditor.controller;
      final focusNode = notesEditor.focusNode;
      const selection = TextSelection(baseOffset: 4, extentOffset: 15);
      controller.selection = selection;
      focusNode.requestFocus();
      await tester.pump();

      for (final size in const [Size(360, 800), Size(1, 1), Size(1536, 1024)]) {
        await _resizeWorkspace(tester, size);
        expect(
          tester.state(find.byType(YorksV1ProjectCreateFlowScreen)),
          same(flowState),
        );
        final current = fixture.container.read(_activeProvider(fixture));
        expect(current.draftId, draftId);
        expect(current.name, proposedName);
        expect(current.notes, notes);
        expect(current.rawEditorState['dateStartText'], partialDate);
        expect(current.isAcknowledged, true);
        expect(tester.takeException(), isNull);
      }
      final resumedEditor = tester.widget<EditableText>(
        find.descendant(of: notesField, matching: find.byType(EditableText)),
      );
      expect(resumedEditor.controller, same(controller));
      expect(resumedEditor.focusNode, same(focusNode));
      expect(controller.selection, selection);
      expect(controller.text, notes);
      // The temporarily hidden 1×1 body has no keyboard target. Its original
      // focus node remains usable once the real viewport returns.
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, true);

      await tester.tap(
        find
            .text(YorksV1ProjectSetupShellStrings.returnToProjects.primary)
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
        findsNothing,
      );
      _expectPortfolio(fixture);
      await _resumeDraft(tester, draftId);
      _expectResumedDraft(tester, fixture, draftId, proposedName);
      final restored = fixture.container.read(_activeProvider(fixture));
      expect(restored.rawEditorState['dateStartText'], partialDate);
      expect(restored.notes, notes);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'universal desktop Back keeps rejected draft exit history and resumes with Forward',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
      );
      await _openCreateProject(tester);
      final originalDraftId = fixture.container
          .read(_activeProvider(fixture))
          .draftId;
      const proposedName = 'Guarded universal history proposal';
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        proposedName,
      );
      final before = fixture.container.read(yorksNavigationHistoryProvider);
      await tester.tap(find.byKey(const ValueKey('yorks-workspace-back')));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.leaveSetupTitle.primary),
        findsOneWidget,
      );
      await tester.tap(find.text(YorksV1ProjectStrings.keepWorking.primary));
      await tester.pumpAndSettle();
      expect(
        fixture.router.routerDelegate.currentConfiguration.last.matchedLocation,
        RoutePaths.engineerCreateProject,
      );
      final retained = fixture.container.read(yorksNavigationHistoryProvider);
      expect(retained.locations, before.locations);
      expect(retained.cursor, before.cursor);
      expect(
        find.byKey(const ValueKey('yorks-workspace-sidebar-toggle')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('yorks-workspace-back')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(YorksV1ProjectStrings.leaveWithSavedDraft.primary),
      );
      await tester.pumpAndSettle();
      _expectPortfolio(fixture);
      await tester.tap(find.byKey(const ValueKey('yorks-workspace-forward')));
      await tester.pumpAndSettle();
      _expectResumedDraft(tester, fixture, originalDraftId, proposedName);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connected loading permissions expose only verification, never the setup feature',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        permission: const YorksV1CurrentPermissionSnapshotState(
          isInitialLoading: true,
        ),
        settle: false,
      );
      expect(
        find.byKey(const ValueKey('yorks-permission-verification-shell')),
        findsOneWidget,
      );
      expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
      expect(find.byKey(const ValueKey('yorks-v1-project-name')), findsNothing);
      expect(find.byKey(_navigationKey), findsNothing);
      expect(find.byKey(_searchKey), findsNothing);
      expect(find.byKey(_drawerKey), findsNothing);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed history storage failure stays recoverable and Retry respects a later foreign writer',
    (tester) async {
      late _ClaimGateDraftStorage storage;
      late YorksV1ProjectCreationDraft oldDraft;
      late String storageKey;
      late String originalJournal;
      var callbacks = 0;
      final fixture = await _pumpWorkspace(
        tester,
        initialLocation: RoutePaths.yorksV1Projects,
        onProjectCreated: (_) => callbacks++,
        draftStorageFactory: (preferences) =>
            storage = _ClaimGateDraftStorage(preferences),
        seed: (container, preferences) async {
          final provider = yorksV1ProjectSetupCreationDraftProvider(_owner);
          final writer = container.read(provider.notifier);
          await writer.initialized;
          await writer.save(
            container
                .read(provider)
                .copyWith(
                  reference: 'RETAIN-ON-LOCAL-FAILURE',
                  name: 'Confirmed project whose local retirement failed',
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                ),
          );
          oldDraft = container.read(provider);
          storageKey = writer.storageKey;
          final operation = YorksV1ProjectSetupOperation(
            backendIdentity: oldDraft.backendIdentity,
            ownerAuthUserId: _owner,
            draftId: oldDraft.draftId,
            mode: YorksV1ProjectSetupMode.create,
            core: YorksV1ProjectSetupCommand(
              kind: YorksV1ProjectSetupCommandKind.create,
              idempotencyKey: oldDraft.creationIdempotencyKey,
              payload: oldDraft.toCreationInput().toRpcPayload(),
              status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
              attempts: 1,
              result: {
                'project': {
                  'id': 'local-retirement-failure-project',
                  'reference': oldDraft.reference,
                  'name': oldDraft.name,
                  'state': 'draft',
                  'record_version': 0,
                  'created_at': '2026-10-04T00:00:00Z',
                },
                'idempotency_key': oldDraft.creationIdempotencyKey,
              },
            ),
            files: const [
              YorksV1ProjectSetupFile(
                localId: 'failure-retained-file',
                idempotencyKey: 'failure-retained-file-intent',
                fileName: 'retained-on-failure.pdf',
                mimeType: 'application/pdf',
                sizeBytes: 4,
                classification: YorksV1DocumentClassification.operational,
              ),
            ],
          );
          originalJournal = jsonEncode(operation.toJson());
          await preferences.setString(
            '$storageKey:journal:${oldDraft.draftId}',
            originalJournal,
          );
          storage.failRetirementKey = storageKey;
        },
      );
      fixture.router.go(
        RoutePaths.yorksV1ProjectSetupDraftPath(oldDraft.draftId),
      );
      await tester.pumpAndSettle();
      expect(storage.failedRetirements, 1);
      expect(
        find.text(YorksV1ProjectStrings.localSaveFailed.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ProjectStrings.localRecoveryUnavailable.primary),
        findsNothing,
      );
      expect(find.text(YorksV1ProjectStrings.retry.primary), findsOneWidget);
      expect(fixture.commands.calls, 0);
      expect(callbacks, 0);
      expect(
        fixture.preferences.getString(
          '$storageKey:journal:${oldDraft.draftId}',
        ),
        originalJournal,
      );
      expect(
        fixture.preferences.getString(
          '$storageKey:retired:${oldDraft.draftId}',
        ),
        isNull,
      );

      var keys = 0;
      final foreignWriter = YorksV1ProjectCreationDraftController(
        ownerAuthUserId: _owner,
        backendIdentity: oldDraft.backendIdentity,
        storageKey: storageKey,
        storage: storage,
        idempotencyKeyFactory: () => 'retry-other-writer-${keys++}',
      );
      addTearDown(foreignWriter.dispose);
      await foreignWriter.initialized;
      await foreignWriter.takeOver();
      final foreignEnvelope = fixture.preferences.getString(storageKey);
      expect(
        foreignWriter.state.writerEpoch,
        greaterThan(oldDraft.writerEpoch),
      );
      await tester.tap(find.text(YorksV1ProjectStrings.retry.primary));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.takeOverDraft.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectStrings.localRecoveryUnavailable.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectStrings.localSaveFailed.primary),
        findsNothing,
      );
      expect(
        fixture.container.read(_activeProvider(fixture)).storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      expect(fixture.preferences.getString(storageKey), foreignEnvelope);
      expect(
        fixture.preferences.getString(
          '$storageKey:journal:${oldDraft.draftId}',
        ),
        originalJournal,
      );
      expect(
        fixture.preferences.getString(
          '$storageKey:retired:${oldDraft.draftId}',
        ),
        isNull,
      );
      expect(storage.failedRetirements, 1);
      expect(fixture.commands.calls, 0);
      expect(callbacks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1536, 1024), const Size(360, 800)]) {
    testWidgets(
      '${size.width} fresh Create waits for its own acknowledgement and preserves a foreign confirmed A',
      (tester) async {
        late _ClaimGateDraftStorage storage;
        late YorksV1ProjectCreationDraftController oldWriter;
        late YorksV1ProjectCreationDraft oldDraft;
        late String oldEnvelope;
        late String originalJournal;
        final claim = Completer<void>();
        var callbacks = 0;
        final fixture = await _pumpWorkspace(
          tester,
          size: size,
          initialLocation: RoutePaths.yorksV1Projects,
          onProjectCreated: (_) => callbacks++,
          draftStorageFactory: (preferences) =>
              storage = _ClaimGateDraftStorage(preferences),
          seed: (container, preferences) async {
            final backend = container.read(
              yorksV1ProjectDraftBackendIdentityProvider,
            );
            var keys = 0;
            oldWriter = YorksV1ProjectCreationDraftController(
              ownerAuthUserId: _owner,
              backendIdentity: backend,
              storageKey: yorksV1ProjectDraftStorageKey(
                backendIdentity: backend,
                ownerAuthUserId: _owner,
                mode: YorksV1ProjectDraftMode.create,
              ),
              storage: storage,
              idempotencyKeyFactory: () => 'prior-live-writer-${keys++}',
            );
            addTearDown(oldWriter.dispose);
            await oldWriter.initialized;
            await oldWriter.save(
              oldWriter.state.copyWith(
                reference: 'OLD-CONFIRMED-LEASE',
                name: 'Confirmed project with retained writer lease',
                currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                attachments: const [
                  YorksV1ProjectAttachmentInput(
                    localId: 'leased-old-file',
                    fileName: 'retained-private-plan.pdf',
                    mimeType: 'application/pdf',
                    sizeBytes: 4,
                    contentHash:
                        '0000000000000000000000000000000000000000000000000000000000000000',
                  ),
                ],
                rawEditorState: const {
                  'private_unfinished_text': 'Preserve the original recovery',
                },
              ),
            );
            oldDraft = oldWriter.state;
            final operation = YorksV1ProjectSetupOperation(
              backendIdentity: backend,
              ownerAuthUserId: _owner,
              draftId: oldDraft.draftId,
              mode: YorksV1ProjectSetupMode.create,
              core: YorksV1ProjectSetupCommand(
                kind: YorksV1ProjectSetupCommandKind.create,
                idempotencyKey: oldDraft.creationIdempotencyKey,
                payload: oldDraft.toCreationInput().toRpcPayload(),
                status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
                attempts: 1,
                result: {
                  'project': {
                    'id': 'old-confirmed-lease-project',
                    'reference': oldDraft.reference,
                    'name': oldDraft.name,
                    'state': 'draft',
                    'record_version': 0,
                    'created_at': '2026-10-04T00:00:00Z',
                  },
                  'idempotency_key': oldDraft.creationIdempotencyKey,
                },
              ),
              files: const [
                YorksV1ProjectSetupFile(
                  localId: 'leased-old-file',
                  idempotencyKey: 'leased-old-file-intent',
                  fileName: 'retained-private-plan.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 4,
                  contentHash:
                      '0000000000000000000000000000000000000000000000000000000000000000',
                  classification: YorksV1DocumentClassification.operational,
                ),
              ],
            );
            originalJournal = jsonEncode(operation.toJson());
            await preferences.setString(
              '${oldWriter.storageKey}:journal:${oldDraft.draftId}',
              originalJournal,
            );
            await preferences.setString(
              '${oldWriter.storageKey}:latest_operation',
              jsonEncode({
                'journal_key':
                    '${oldWriter.storageKey}:journal:${oldDraft.draftId}',
              }),
            );
            oldEnvelope = preferences.getString(oldWriter.storageKey)!;
            expect(oldDraft.writerEpoch, 1);
            expect((jsonDecode(oldEnvelope) as Map)['retired'], false);
            storage.nextTransaction = claim;
          },
        );
        fixture.router.go(RoutePaths.engineerCreateProject);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          fixture.preferences.getString(oldWriter.storageKey),
          oldEnvelope,
        );
        expect(fixture.commands.calls, 0);
        expect(callbacks, 0);
        expect(
          find.text(YorksV1ProjectStrings.takeOverDraft.primary),
          findsNothing,
        );
        claim.complete();
        await _settleFreshAnchor(tester);
        final provider = _activeProvider(fixture);
        final fresh = fixture.container.read(provider);
        final freshWriter = fixture.container.read(provider.notifier);
        expect(fresh.draftId, isNot(oldDraft.draftId));
        expect(
          fresh.creationIdempotencyKey,
          isNot(oldDraft.creationIdempotencyKey),
        );
        expect(fresh.currentStage, YorksV1ProjectCreationStage.projectDetails);
        _expectEmptyProposal(fresh);
        expect(fresh.attachments, isEmpty);
        expect(freshWriter.writable, true);
        expect(oldWriter.state.writerEpoch, oldDraft.writerEpoch);
        expect(
          find.text(YorksV1ProjectStrings.takeOverDraft.primary),
          findsNothing,
        );
        expect(
          fixture.preferences.getString(oldWriter.storageKey),
          oldEnvelope,
        );
        final journalKey =
            '${oldWriter.storageKey}:journal:${oldDraft.draftId}';
        expect(fixture.preferences.getString(journalKey), originalJournal);
        expect(
          fixture.preferences.getString(
            '${oldWriter.storageKey}:retired:${oldDraft.draftId}',
          ),
          isNull,
        );
        final exactB = fixture.preferences.getString(freshWriter.storageKey);
        await oldWriter.save(
          oldWriter.state.copyWith(name: 'Independent owner still retains A'),
        );
        expect(fixture.preferences.getString(freshWriter.storageKey), exactB);
        expect(fixture.preferences.getString(journalKey), originalJournal);
        expect(fixture.commands.calls, 0);
        expect(callbacks, 0);
        expect(tester.takeException(), isNull);
      },
    );

    for (final historical in ['files', 'activation', 'pointer', 'uncertain']) {
      testWidgets(
        historical == 'uncertain'
            ? '${size.width} Projects Create retains uncertain core intent without replay'
            : '${size.width} Projects Create starts fresh after historical confirmed $historical recovery',
        (tester) async {
          late YorksV1ProjectCreationDraft oldDraft;
          late String storageKey;
          late String originalJournal;
          late String retiredJson;
          final fixture = await _pumpWorkspace(
            tester,
            size: size,
            initialLocation: RoutePaths.yorksV1Projects,
            seed: (container, preferences) async {
              final provider = yorksV1ProjectSetupCreationDraftProvider(_owner);
              final notifier = container.read(provider.notifier);
              await notifier.initialized;
              await notifier.save(
                container
                    .read(provider)
                    .copyWith(
                      reference: 'OLD-CONFIRMED',
                      name: 'Old created project',
                      currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                      buildings: const [
                        YorksV1ProjectBuildingInput(
                          name: 'Old physical building',
                        ),
                      ],
                      attachments: const [
                        YorksV1ProjectAttachmentInput(
                          localId: 'old-file',
                          fileName: 'private-old-plan.pdf',
                          mimeType: 'application/pdf',
                          sizeBytes: 4,
                        ),
                      ],
                      rawEditorState: const {
                        'private_unfinished_text':
                            'Retain original private recovery',
                      },
                    ),
              );
              oldDraft = container.read(provider);
              storageKey = notifier.storageKey;
              final core = YorksV1ProjectSetupCommand(
                kind: YorksV1ProjectSetupCommandKind.create,
                idempotencyKey: oldDraft.creationIdempotencyKey,
                payload: oldDraft.toCreationInput().toRpcPayload(),
                status: historical == 'uncertain'
                    ? YorksV1ProjectSetupCommandStatus.outcomeUncertain
                    : YorksV1ProjectSetupCommandStatus.confirmedSuccess,
                attempts: 1,
                result: historical == 'uncertain'
                    ? null
                    : {
                        'project': {
                          'id': 'old-confirmed-project',
                          'reference': oldDraft.reference,
                          'name': oldDraft.name,
                          'state': 'draft',
                          'record_version': 0,
                          'created_at': '2026-10-04T00:00:00Z',
                        },
                        'idempotency_key': oldDraft.creationIdempotencyKey,
                      },
              );
              final operation = YorksV1ProjectSetupOperation(
                backendIdentity: oldDraft.backendIdentity,
                ownerAuthUserId: _owner,
                draftId: oldDraft.draftId,
                mode: YorksV1ProjectSetupMode.create,
                core: core,
                activation: historical == 'activation'
                    ? YorksV1ProjectSetupCommand(
                        kind: YorksV1ProjectSetupCommandKind.activate,
                        idempotencyKey: 'old-activation-intent',
                        payload: {
                          'project_id': 'old-confirmed-project',
                          'expected_version': 0,
                          'target_state': 'active',
                        },
                        status:
                            YorksV1ProjectSetupCommandStatus.outcomeUncertain,
                        attempts: 1,
                      )
                    : null,
                files: const [
                  YorksV1ProjectSetupFile(
                    localId: 'old-file',
                    idempotencyKey: 'old-file-intent',
                    fileName: 'private-old-plan.pdf',
                    mimeType: 'application/pdf',
                    sizeBytes: 4,
                    classification: YorksV1DocumentClassification.operational,
                  ),
                ],
              );
              originalJournal = jsonEncode(operation.toJson());
              await preferences.setString(
                '$storageKey:journal:${oldDraft.draftId}',
                originalJournal,
              );
              await preferences.setString(
                '$storageKey:latest_operation',
                jsonEncode({
                  'journal_key': '$storageKey:journal:${oldDraft.draftId}',
                }),
              );
              if (historical == 'pointer') {
                await notifier.retire(resultProjectId: 'old-confirmed-project');
                container.invalidate(provider);
                await container.read(provider.notifier).initialized;
                retiredJson = preferences.getString(
                  '$storageKey:retired:${oldDraft.draftId}',
                )!;
              }
            },
          );
          if (historical != 'uncertain') {
            expect(_allDraftCards(), findsNothing);
          }
          final oldEnvelope = fixture.preferences.getString(storageKey);
          final oldTombstone = fixture.preferences.getString(
            '$storageKey:retired:${oldDraft.draftId}',
          );
          await _openCreateProject(tester);
          final provider = _activeProvider(fixture);
          final fresh = fixture.container.read(provider);
          expect(fresh.draftId, isNot(oldDraft.draftId));
          expect(
            fresh.creationIdempotencyKey,
            isNot(oldDraft.creationIdempotencyKey),
          );
          expect(
            fresh.currentStage,
            YorksV1ProjectCreationStage.projectDetails,
          );
          _expectEmptyProposal(fresh);
          expect(fresh.reference, isEmpty);
          expect(fresh.name, isEmpty);
          expect(fresh.buildings, isEmpty);
          expect(fresh.attachments, isEmpty);
          expect(find.textContaining('Old created project'), findsNothing);
          expect(
            find.byKey(const ValueKey('yorks-v1-project-operation-outcome')),
            findsNothing,
          );
          expect(
            find.text(YorksV1ProjectStrings.projectCreated.primary),
            findsNothing,
          );
          expect(fixture.preferences.getString(storageKey), oldEnvelope);
          expect(
            fixture.preferences.getString(
              '$storageKey:journal:${oldDraft.draftId}',
            ),
            originalJournal,
          );
          expect(
            fixture.preferences.getString(
              '$storageKey:retired:${oldDraft.draftId}',
            ),
            oldTombstone,
          );
          if (historical == 'pointer') expect(oldTombstone, retiredJson);
          expect(fixture.commands.calls, 0);
          await tester.tap(
            find
                .text(YorksV1ProjectSetupShellStrings.returnToProjects.primary)
                .first,
          );
          await tester.pumpAndSettle();
          _expectPortfolio(fixture);
          if (historical == 'uncertain') {
            await _resumeDraft(tester, oldDraft.draftId);
            expect(
              fixture.container.read(_activeProvider(fixture)).draftId,
              oldDraft.draftId,
            );
            expect(
              find.byKey(const ValueKey('yorks-v1-project-operation-outcome')),
              findsOneWidget,
            );
            expect(
              find.text(YorksV1ProjectStrings.checkSavedStatus.primary),
              findsWidgets,
            );
          } else {
            await _openCreateProject(tester);
            expect(
              fixture.container.read(_activeProvider(fixture)).draftId,
              isNot(fresh.draftId),
            );
            _expectEmptyProposal(
              fixture.container.read(_activeProvider(fixture)),
            );
          }
          expect(
            fixture.preferences.getString(
              '$storageKey:journal:${oldDraft.draftId}',
            ),
            originalJournal,
          );
          expect(fixture.commands.calls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'confirmed create denial cannot expose an editor inside the universal workspace',
    (tester) async {
      final fixture = await _pumpWorkspace(
        tester,
        permission: yorksV1TrustedFeaturePermissionState(
          role: YorksV1Role.projectEngineer,
          capabilities: const {YorksV1CapabilityKeys.projectsView},
        ),
      );
      expect(
        find.text(YorksV1ProjectStrings.noPermission.primary),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('yorks-v1-project-name')), findsNothing);
      expect(
        find.byKey(const ValueKey('yorks-v1-project-create')),
        findsNothing,
      );
      expect(find.byKey(_navigationKey), findsNothing);
      expect(find.byKey(_searchKey), findsNothing);
      expect(fixture.commands.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectEmptyProposal(YorksV1ProjectCreationDraft draft) {
  expect(draft.reference, isEmpty);
  expect(draft.name, isEmpty);
  expect(draft.clientName, isNull);
  expect(draft.jobOrContractReference, isNull);
  expect(draft.siteLocation, isNull);
  expect(draft.notes, isNull);
  expect(draft.startDate, isNull);
  expect(draft.endDate, isNull);
  expect(draft.parties, isEmpty);
  expect(draft.initialMembers, isEmpty);
  expect(draft.buildings, isEmpty);
  expect(draft.attachments, isEmpty);
  expect(draft.retainedFields, isEmpty);
  for (final field in [
    'buildingCode',
    'buildingName',
    'buildingFloors',
    'buildingAddress',
    'subcontractorText',
    'otherContractorText',
    'dateStartText',
    'dateEndText',
  ]) {
    expect(draft.rawEditorState[field] ?? '', isEmpty, reason: field);
  }
  expect(draft.rawEditorState['buildingFrp'] ?? false, false);
}

Future<void> _tapSaveDraft(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final save = find.byKey(_saveDraftKey);
  await Scrollable.ensureVisible(tester.element(save), alignment: .5);
  await tester.pumpAndSettle();
  expect(save.hitTestable(), findsOneWidget);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

StateNotifierProvider<
  YorksV1ProjectCreationDraftController,
  YorksV1ProjectCreationDraft
>
_activeProvider(_WorkspaceFixture fixture) {
  final mounted = find.byType(YorksV1ProjectCreateFlowScreen).evaluate();
  final uri = mounted.isNotEmpty
      ? GoRouterState.of(mounted.single).uri
      : fixture.router.routeInformationProvider.value.uri;
  final draftId = uri.queryParameters['draft'] ?? fixture.lastActiveDraftId;
  if (uri.queryParameters['draft'] != null) fixture.lastActiveDraftId = draftId;
  if (uri.queryParameters['recovery'] == 'legacy') {
    return yorksV1ProjectSetupCreationDraftProvider(_owner);
  }
  expect(
    draftId,
    isNotNull,
    reason:
        'Mounted setup must anchor its exact proposal ID; router=$uri; storedKeys=${fixture.preferences.getKeys()}',
  );
  final scope = YorksV1ProjectCreationDraftContext(
    ownerAuthUserId: _owner,
    draftId: draftId!,
  );
  return fixture.container.read(
        yorksV1ProjectSelectedDraftUsesLegacyProvider(scope),
      )
      ? yorksV1ProjectSetupCreationDraftProvider(_owner)
      : yorksV1ProjectSetupCreationDraftByIdProvider(scope);
}

Finder _draftCard(String id) =>
    find.byKey(ValueKey('yorks-v1-project-saved-local-draft-$id'));
Finder _draftResume(String id) =>
    find.byKey(ValueKey('yorks-v1-project-resume-local-draft-$id'));
Finder _allDraftResumes() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith(
        'yorks-v1-project-resume-local-draft-',
      ),
);
Finder _allDraftCards() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith(
        'yorks-v1-project-saved-local-draft-',
      ),
);

Future<void> _resumeDraft(WidgetTester tester, String id) async {
  final resume = _draftResume(id);
  await tester.ensureVisible(resume);
  await tester.pumpAndSettle();
  await tester.tap(resume);
  await tester.pumpAndSettle();
}

Finder _sidebarSurface() => find
    .ancestor(
      of: find.text(YorksV1ShellStrings.companyLegalName.primary),
      matching: find.byType(SafeArea),
    )
    .first;

Future<void> _openCreateProject(WidgetTester tester) async {
  final create = find
      .descendant(
        of: find.byType(YorksV1ProjectsScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is FilledButton && widget.onPressed != null,
        ),
      )
      .first;
  await Scrollable.ensureVisible(tester.element(create), alignment: .5);
  await tester.pumpAndSettle();
  expect(create.hitTestable(), findsOneWidget);
  await tester.tap(create);
  await tester.pumpAndSettle();
  await _settleFreshAnchor(tester);
}

Future<void> _settleFreshAnchor(WidgetTester tester) async {
  await _settleDeferredSetup(tester);
  // pumpAndSettle does not await an async post-frame storage flush. Let the
  // acknowledged URI anchor finish before reading its selected draft scope.
  for (var frame = 0; frame < 20; frame++) {
    final mounted = find.byType(YorksV1ProjectCreateFlowScreen);
    if (mounted.evaluate().isEmpty ||
        GoRouterState.of(
          tester.element(mounted),
        ).uri.queryParameters.containsKey('draft')) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _settleDeferredSetup(WidgetTester tester) async {
  for (var frame = 0; frame < 40; frame++) {
    if (find
        .byKey(const ValueKey('yorks-v1-project-setup-loading'))
        .evaluate()
        .isEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pumpAndSettle();
}

Future<void> _resizeWorkspace(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  await tester.pumpAndSettle();
}

Future<void> _openWorkspaceSearch(WidgetTester tester) async {
  // The universal launcher resolves its native deferred asset outside fake
  // widget time. Preserve the exact no-click Ctrl+K event sequence.
  await tester.runAsync(() async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  expect(find.byType(YorksV1WorkspaceSearchDialog), findsOneWidget);
}

void _expectPortfolio(_WorkspaceFixture fixture) {
  expect(
    fixture.router.routeInformationProvider.value.uri.path,
    RoutePaths.yorksV1Projects,
  );
  expect(find.byType(YorksV1ProjectsScreen), findsOneWidget);
  expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
}

void _expectResumedDraft(
  WidgetTester tester,
  _WorkspaceFixture fixture,
  String originalDraftId,
  String proposedName,
) {
  expect(
    fixture.router.routerDelegate.currentConfiguration.last.matchedLocation,
    RoutePaths.engineerCreateProject,
  );
  expect(find.byType(YorksV1ProjectCreateFlowScreen), findsOneWidget);
  expect(find.byKey(_navigationKey), findsNothing);
  expect(find.byKey(_searchKey), findsNothing);
  final name = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(const ValueKey('yorks-v1-project-name')),
      matching: find.byType(EditableText),
    ),
  );
  expect(name.controller.text, proposedName);
  final resumed = fixture.container.read(_activeProvider(fixture));
  expect(resumed.draftId, originalDraftId);
  expect(resumed.name, proposedName);
  expect(resumed.acknowledgedRevision, resumed.revision);
}

void _expectEngineerNavigation(Finder surface) {
  for (final label in [
    YorksV1ShellStrings.overview,
    YorksV1ShellStrings.projects,
    YorksV1ShellStrings.materialRequests,
    YorksV1ShellStrings.ductSizer,
    YorksV1ShellStrings.espCalculator,
  ]) {
    expect(
      find.descendant(of: surface, matching: find.text(label.primary)),
      findsOneWidget,
    );
  }
  for (final label in [
    YorksV1ShellStrings.configuration,
    YorksV1ShellStrings.userManagement,
    YorksV1ShellStrings.auditTrail,
  ]) {
    expect(
      find.descendant(of: surface, matching: find.text(label.primary)),
      findsNothing,
    );
  }
}

Future<_WorkspaceFixture> _pumpWorkspace(
  WidgetTester tester, {
  Size size = const Size(1536, 1024),
  YorksV1CurrentPermissionSnapshotState? permission,
  bool settle = true,
  String initialLocation = RoutePaths.engineerCreateProject,
  Future<void> Function(ProviderContainer, SharedPreferences)? seed,
  ProjectDraftAtomicStorage Function(SharedPreferences)? draftStorageFactory,
  ValueChanged<YorksV1Project>? onProjectCreated,
  YorksV1Role role = YorksV1Role.projectEngineer,
  String? ownerAuthUserId = _owner,
  String backendIdentity = 'local',
  bool projectSetup = true,
  AppLanguage language = AppLanguage.english,
  TextScaler textScaler = TextScaler.noScaling,
  YorksV1ProjectSetupLibraryLoader? setupLoader,
  String? Function()? currentOwner,
  List<YorksV1ProjectPortfolioItem> portfolio = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final client = _NoNetworkSupabaseClient();
  final commands = _NoProjectCommands();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      supabaseClientProvider.overrideWithValue(client),
      currentUserProvider.overrideWithValue(null),
      unreadNotificationCountProvider.overrideWithValue(0),
      yorksV1WorkspaceStatusProvider.overrideWithValue(
        const YorksV1WorkspaceStatus(
          state: YorksV1WorkspaceConnectionState.connected,
        ),
      ),
      yorksV1FeatureFlagsProvider.overrideWithValue(
        YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          projectSetup: projectSetup,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          documents: true,
        ),
      ),
      if (currentOwner == null)
        yorksV1AuthUserIdProvider.overrideWithValue(ownerAuthUserId)
      else
        yorksV1AuthUserIdProvider.overrideWith((ref) => currentOwner()),
      yorksV1ProjectSetupLibraryLoaderProvider.overrideWithValue(
        setupLoader ?? () => loadYorksV1ProjectSetupLibrary(),
      ),
      yorksV1CurrentRoleProvider.overrideWithValue(role),
      yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
        backendIdentity,
      ),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          permission ??
              yorksV1TrustedFeaturePermissionState(
                role: role,
                capabilities: _engineerCapabilities,
              ),
        ),
      ),
      yorksV1ProjectRepositoryProvider.overrideWithValue(commands),
      yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(
        draftStorageFactory?.call(preferences) ??
            _SupportedDraftStorage(preferences),
      ),
      yorksV1ProjectReferenceAdvisoryProvider.overrideWith(
        (ref, query) async => YorksV1ProjectReferenceAdvisory.unavailable,
      ),
      yorksV1ActiveProjectTeamDirectoryProvider.overrideWith((ref) async => []),
      yorksV1ProjectPortfolioProvider.overrideWith((ref) async => portfolio),
      yorksV1WorkspaceSearchResultsProvider.overrideWith(
        (ref, query) async => const YorksV1WorkspaceSearchResponse(results: []),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (seed != null) await seed(container, preferences);
  if (language != AppLanguage.english) {
    await container.read(languageProvider.notifier).setLanguage(language);
  }

  // Keep VM workspace composition while exercising the production route's
  // real selection redirect/onExit callbacks, including query-only switches.
  final productionRouter = createAppRouter(
    isOnboarded: true,
    isLoggedIn: true,
    role: UserRole.engineer,
    yorksV1Role: role,
    yorksV1ProjectsEnabled: true,
    yorksV1ProjectSetupEnabled: projectSetup,
    onLeaveYorksProjectSetup: () =>
        container.read(yorksV1ProjectSetupNavigationGuardProvider).canLeave(),
    onSelectYorksProjectSetup: (draftId, legacyRecovery) => container
        .read(yorksV1ProjectSetupNavigationGuardProvider)
        .canSelectCreation(draftId, legacyRecovery: legacyRecovery),
  );
  addTearDown(productionRouter.dispose);
  final setupRoute = productionRouter.configuration.routes
      .whereType<GoRoute>()
      .singleWhere((route) => route.path == RoutePaths.engineerCreateProject);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: RoutePaths.engineerCreateProject,
        redirect: setupRoute.redirect,
        onExit: setupRoute.onExit,
        pageBuilder: (context, state) {
          final prototype = setupRoute.pageBuilder!(context, state);
          return NoTransitionPage<void>(
            key: prototype.key,
            child: YorksV1WorkspaceShell(
              featureOwnsBackNavigation: true,
              child: YorksV1ProjectSetupEntryScreen(
                onProjectCreated: onProjectCreated,
                resumeDraftId: state.uri.queryParameters['draft'],
                legacyRecovery:
                    state.uri.queryParameters['recovery'] == 'legacy',
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectEdit,
        onExit: productionRouter.configuration.routes
            .whereType<GoRoute>()
            .singleWhere((route) => route.path == RoutePaths.yorksV1ProjectEdit)
            .onExit,
        pageBuilder: (context, state) {
          final actual = productionRouter.configuration.routes
              .whereType<GoRoute>()
              .singleWhere(
                (route) => route.path == RoutePaths.yorksV1ProjectEdit,
              );
          final prototype = actual.pageBuilder!(context, state);
          return NoTransitionPage<void>(
            key: prototype.key,
            child: YorksV1WorkspaceShell(
              featureOwnsBackNavigation: true,
              child: YorksV1ProjectSetupEntryScreen(
                editProjectId: state.pathParameters['projectId']!,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.yorksV1Projects,
        builder: (_, _) =>
            const YorksV1WorkspaceShell(child: YorksV1ProjectsScreen()),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Directionality(
            textDirection: language == AppLanguage.arabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    await _settleDeferredSetup(tester);
    if (Uri.parse(initialLocation).path == RoutePaths.engineerCreateProject &&
        find.byType(YorksV1ProjectCreateFlowScreen).evaluate().isNotEmpty) {
      await _settleFreshAnchor(tester);
    }
  } else {
    await tester.pump();
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  addTearDown(() => expect(client.calls, 0));
  return _WorkspaceFixture(container, router, commands, preferences);
}

class _WorkspaceFixture {
  _WorkspaceFixture(
    this.container,
    this.router,
    this.commands,
    this.preferences,
  );
  String? lastActiveDraftId;
  final ProviderContainer container;
  final GoRouter router;
  final _NoProjectCommands commands;
  final SharedPreferences preferences;
}

class _NoProjectCommands
    implements
        YorksV1ProjectRepository,
        YorksV1ProjectReviewedCommandRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Navigation must not dispatch a project command');
  }
}

/// A configured client activates the real connected permission gate, while
/// every transport access fails loudly. These UI tests override only reads
/// and local storage; navigation must never contact a shared backend.
class _NoNetworkSupabaseClient extends Fake implements SupabaseClient {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Workspace navigation must not access remote transport');
  }
}

class _SupportedDraftStorage extends SharedPreferencesProjectDraftStorage {
  _SupportedDraftStorage(super.preferences);
  @override
  bool get supportsAtomicOwnership => true;
}

class _ReadSpyDraftStorage extends _SupportedDraftStorage {
  _ReadSpyDraftStorage(super.preferences);
  final List<String> readKeys = [];
  int transactions = 0;

  @override
  String? read(String key) {
    readKeys.add(key);
    return super.read(key);
  }

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) {
    transactions++;
    return super.transaction(lockKey, work);
  }
}

class _ClaimGateDraftStorage extends _SupportedDraftStorage {
  _ClaimGateDraftStorage(super.preferences);
  Completer<void>? nextTransaction;
  String? failRetirementKey;
  bool failNewEnvelopeWrites = false;
  int failedRetirements = 0;

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) async {
    final gate = nextTransaction;
    nextTransaction = null;
    if (gate != null) await gate.future;
    return super.transaction(
      lockKey,
      (tx) => work(
        _InterceptDraftTransaction(
          tx,
          beforeWrite: (key, value) {
            if (failNewEnvelopeWrites && key.contains(':draft:')) {
              throw const ProjectDraftStorageException(
                'write_not_acknowledged',
              );
            }
            if (key == failRetirementKey &&
                (jsonDecode(value) as Map)['retired'] == true) {
              failRetirementKey = null;
              failedRetirements++;
              throw const ProjectDraftStorageException(
                'write_not_acknowledged',
              );
            }
          },
        ),
      ),
    );
  }
}

class _InterceptDraftTransaction implements ProjectDraftAtomicTransaction {
  const _InterceptDraftTransaction(this.inner, {required this.beforeWrite});
  final ProjectDraftAtomicTransaction inner;
  final void Function(String, String) beforeWrite;

  @override
  String? read(String key) => inner.read(key);

  @override
  void write(String key, String value) {
    beforeWrite(key, value);
    inner.write(key, value);
  }

  @override
  void remove(String key) => inner.remove(key);
}

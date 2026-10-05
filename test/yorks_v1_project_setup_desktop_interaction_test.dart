import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_setup_desktop_shell.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_completion.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_desktop_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_team_directory_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/project_setup_completion_fixture.dart';
import 'support/project_setup_reviewed_repository_adapter.dart';
import 'support/yorks_v1_permission_test_support.dart';

const _owner = 'desktop-test-owner';
const _viewport = Size(1536, 1024);

void main() {
  setUpAll(() async {
    final nexus = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final iconBytes = await File(
      '${_flutterCacheDirectory().path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([nexus.load(), arabic.load(), icons.load()]);
  });

  testWidgets(
    'desktop Details uses the form width without the information panel',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.projectDetails,
      );
      await _pump(tester, fixture.container);
      expect(
        find.text(YorksV1ProjectSetupDesktopStrings.toContinue.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectSetupDesktopStrings.otherDetailsLater.primary),
        findsNothing,
      );
      final reference = _key('yorks-v1-project-reference');
      expect(tester.getSize(reference).width, greaterThan(500));
      await tester.enterText(reference, '');
      await tester.enterText(_key('yorks-v1-project-name'), '');
      await tester.tap(_key('yorks-v1-project-continue'));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.requiredField.primary),
        findsWidgets,
      );
      expect(
        fixture.draft.currentStage,
        YorksV1ProjectCreationStage.projectDetails,
      );
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop new building says Add and editing says Save without duplicating rows',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.buildings,
        buildings: const [],
      );
      await _pump(tester, fixture.container);
      final apply = _key('yorks-v1-desktop-apply-building');
      expect(
        find.descendant(
          of: apply,
          matching: find.text(YorksV1ProjectStrings.addBuilding.primary),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        _key('yorks-v1-building-name'),
        'New physical building',
      );
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      final created = fixture.draft.buildings.single;
      expect(created.name, 'New physical building');
      expect(created.localRowId, isNotEmpty);
      await tester.tap(_key('yorks-v1-desktop-building-${created.localRowId}'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: apply,
          matching: find.text(
            YorksV1ProjectSetupDesktopStrings.saveBuilding.primary,
          ),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        _key('yorks-v1-building-name'),
        'Renamed physical building',
      );
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(fixture.draft.buildings, hasLength(1));
      expect(fixture.draft.buildings.single.localRowId, created.localRowId);
      expect(fixture.draft.buildings.single.name, 'Renamed physical building');
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop filtered building Apply preserves the original stable scope and false FRP',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.buildings,
        buildings: const [
          YorksV1ProjectBuildingInput(
            localRowId: 'first-row',
            sourceScopeId: 'first-scope',
            code: 'A',
            name: 'First building',
          ),
          YorksV1ProjectBuildingInput(
            localRowId: 'second-row',
            sourceScopeId: 'second-scope',
            code: 'B',
            name: 'Second building',
            hasFrpRoom: true,
            flags: {'has_frp_room': true, 'future_flag': 'retain'},
            retainedFields: {'future_source': 'retain'},
            deliveryAddress: 'Second address',
          ),
        ],
      );
      await _pump(tester, fixture.container);
      await tester.enterText(
        _key('yorks-v1-desktop-building-search'),
        'Second',
      );
      await tester.pumpAndSettle();
      expect(_key('yorks-v1-desktop-building-first-row'), findsNothing);
      final rowName = find.descendant(
        of: _key('yorks-v1-desktop-building-second-row'),
        matching: find.text('Second building'),
      );
      Focus.of(tester.element(rowName)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_inputText(tester, 'yorks-v1-building-name'), 'Second building');
      await tester.enterText(_key('yorks-v1-building-name'), 'Second renamed');
      await tester.tap(_key('yorks-v1-desktop-building-frp'));
      await tester.pumpAndSettle();

      // An unapplied field is recoverable editor input, not an applied row.
      expect(fixture.draft.buildings[1].name, 'Second building');
      await tester.tap(_key('yorks-v1-desktop-apply-building'));
      await tester.pumpAndSettle();
      expect(fixture.draft.buildings[0].name, 'First building');
      final changed = fixture.draft.buildings[1];
      expect(changed.name, 'Second renamed');
      expect(changed.localRowId, 'second-row');
      expect(changed.sourceScopeId, 'second-scope');
      expect(changed.hasFrpRoom, isFalse);
      expect(changed.toUpdateRpcJson()['flags'], {
        'has_frp_room': false,
        'future_flag': 'retain',
      });
      expect(changed.retainedFields['future_source'], 'retain');
      expect(changed.deliveryAddress, 'Second address');
      expect(fixture.draft.isAcknowledged, isTrue);
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop building Cancel keeps the applied row unchanged', (
    tester,
  ) async {
    final fixture = await _fixture(YorksV1ProjectCreationStage.buildings);
    await _pump(tester, fixture.container);
    final original = fixture.draft.buildings.first.toDraftJson();
    await tester.tap(_key('yorks-v1-desktop-building-building-df3w'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('yorks-v1-building-name'), 'Unapplied name');
    await tester.enterText(
      _key('yorks-v1-building-delivery-address'),
      'Unapplied address',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(fixture.draft.buildings.first.toDraftJson(), original);
    await tester.tap(_key('yorks-v1-desktop-cancel-building'));
    await tester.pumpAndSettle();
    expect(fixture.draft.buildings.first.toDraftJson(), original);
    expect(_inputText(tester, 'yorks-v1-building-name'), isEmpty);
    expect(fixture.repository.commandCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop team filtering selects opaque identities and retains earlier selections',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.partiesAndAccess,
        selectedMembers: const [],
        directory: const [
          YorksV1ProjectTeamDirectoryMember(
            authUserId: 'engineer-jane-one',
            displayName: 'Jane One',
            eligibleRole: YorksV1Role.projectEngineer,
          ),
          YorksV1ProjectTeamDirectoryMember(
            authUserId: 'engineer-jane-two',
            displayName: 'Jane Two',
            eligibleRole: YorksV1Role.siteEngineer,
          ),
        ],
      );
      await _pump(tester, fixture.container);
      await tester.enterText(_key('yorks-v1-project-team-search'), 'Jane Two');
      await tester.pumpAndSettle();
      expect(
        _key('yorks-v1-desktop-directory-engineer-jane-one'),
        findsNothing,
      );
      await tester.tap(
        _key('yorks-v1-desktop-directory-add-engineer-jane-two'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_key('yorks-v1-project-team-search'), 'Jane One');
      await tester.pumpAndSettle();
      await tester.tap(
        _key('yorks-v1-desktop-directory-add-engineer-jane-one'),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.draft.initialMembers.map((member) => member.authUserId),
        unorderedEquals(['engineer-jane-one', 'engineer-jane-two']),
      );
      expect(find.text('engineer-jane-one'), findsNothing);
      expect(find.text('engineer-jane-two'), findsNothing);
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop same-name file menu removes only its stable local identity',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.attachments,
        attachments: const [
          YorksV1ProjectAttachmentInput(
            localId: 'file-first',
            fileName: 'same-name.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 1,
            contentHash: 'first-content-hash',
          ),
          YorksV1ProjectAttachmentInput(
            localId: 'file-second',
            fileName: 'same-name.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 2,
            contentHash: 'second-content-hash',
            categoryKey: 'drawing',
          ),
        ],
      );
      await _pump(tester, fixture.container);
      await tester.enterText(_key('yorks-v1-desktop-file-search'), 'same-name');
      await tester.pumpAndSettle();
      expect(_key('yorks-v1-desktop-file-file-first'), findsOneWidget);
      expect(_key('yorks-v1-desktop-file-file-second'), findsOneWidget);
      await tester.tap(_key('yorks-v1-desktop-file-category-filter'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(YorksV1ProjectSetupDesktopStrings.categoryDrawing.primary)
            .last,
      );
      await tester.pumpAndSettle();
      expect(_key('yorks-v1-desktop-file-file-first'), findsNothing);
      expect(_key('yorks-v1-desktop-file-file-second'), findsOneWidget);
      await tester.tap(_key('yorks-v1-desktop-file-menu-file-second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(YorksV1ProjectStrings.remove.primary).last);
      await tester.pumpAndSettle();
      expect(fixture.draft.attachments, hasLength(1));
      expect(fixture.draft.attachments.single.localId, 'file-first');
      expect(
        fixture.draft.attachments.single.contentHash,
        'first-content-hash',
      );
      expect(fixture.draft.isAcknowledged, isTrue);
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop optional categories and missing bytes do not block core creation',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.reviewAndCreate,
      );
      await _pump(tester, fixture.container);
      expect(
        find.text(YorksV1ProjectStrings.readyToCreateWorkspace.primary),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(_key('yorks-v1-project-create')).onPressed,
        isNotNull,
      );
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in YorksV1ProjectCreationStage.values) {
    testWidgets('desktop content reference ${stage.name} — 1536×1024', (
      tester,
    ) async {
      final fixture = await _fixture(
        stage,
        filesReviewed: true,
        // The supplied review reference contains three files. The dedicated
        // Attachments fixture and behavior tests continue to exercise four.
        attachments: stage == YorksV1ProjectCreationStage.reviewAndCreate
            ? _attachments.take(3).toList()
            : null,
      );
      await _pump(tester, fixture.container);
      if (stage == YorksV1ProjectCreationStage.buildings) {
        await tester.tap(_key('yorks-v1-desktop-building-building-df3w'));
        await tester.pumpAndSettle();
        await tester.tap(_key('yorks-v1-building-name'));
        // Capture the canonical acknowledged editor state after its coalesced
        // device checkpoint, rather than a transient save indicator.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }
      final shell = _key('project-setup-desktop-shell');
      expect(shell, findsOneWidget);
      expect(tester.getSize(shell), _viewport);
      _expectContentOnlyChrome();
      final rail = tester.getRect(_key('project-setup-desktop-rail'));
      expect(rail.left, 0);
      expect(rail.top, 0);
      expect(rail.width, 196);
      final footerHeight = switch (stage) {
        YorksV1ProjectCreationStage.projectDetails => 86.0,
        YorksV1ProjectCreationStage.partiesAndAccess => 66.0,
        YorksV1ProjectCreationStage.buildings => 92.0,
        YorksV1ProjectCreationStage.attachments => 86.0,
        YorksV1ProjectCreationStage.reviewAndCreate => 74.0,
      };
      expect(rail.bottom, _viewport.height - footerHeight);
      if (stage == YorksV1ProjectCreationStage.attachments) {
        final dropzone = tester.getRect(_key('yorks-v1-attachment-dropzone'));
        // Render-object bounds include the panel's border inset. Keep the
        // tolerance small enough to reject a platform-only intrinsic width.
        expect(dropzone.left, closeTo(240, 2));
        expect(dropzone.top, closeTo(238, 2));
        expect(dropzone.width, closeTo(1258, 2));
        expect(dropzone.height, 233);
      }
      if (stage == YorksV1ProjectCreationStage.buildings ||
          stage == YorksV1ProjectCreationStage.reviewAndCreate) {
        // Both hints exercise the footer's flex layout. A visible hint must
        // not leave a loose flex allocation after the primary action.
        final review = stage == YorksV1ProjectCreationStage.reviewAndCreate;
        expect(
          find.text(
            (review
                    ? YorksV1ProjectSetupShellStrings.reviewHint
                    : YorksV1ProjectSetupShellStrings.buildingEditPending)
                .primary,
          ),
          findsOneWidget,
        );
        final action = tester.getRect(
          _key('yorks-v1-project-${review ? 'create' : 'continue'}'),
        );
        expect(action.bottom, lessThanOrEqualTo(_viewport.height));
        expect(action.top, greaterThanOrEqualTo(rail.bottom));
        expect(
          _viewport.width - action.right,
          inInclusiveRange(0.0, 26.0),
          reason: '${stage.name} hint must keep the primary at the right inset',
        );
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        shell,
        matchesGoldenFile(
          'goldens/project_setup_desktop/${stage.name}_1536x1024.png',
        ),
      );
      expect(fixture.repository.commandCalls, 0);
    });
  }

  testWidgets('desktop content reference confirmed result — 1536×1024', (
    tester,
  ) async {
    final fixture = await _fixture(YorksV1ProjectCreationStage.reviewAndCreate);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _pump(
      tester,
      fixture.container,
      child: YorksV1ProjectSetupDesktopShell(
        language: AppLanguage.english,
        stage: YorksV1ProjectCreationStage.reviewAndCreate,
        visitedStages: YorksV1ProjectCreationStage.values.toSet(),
        completeStages: YorksV1ProjectCreationStage.values.toSet(),
        reference: 'YRA-322',
        projectName: 'NEXUS — Four substations',
        localStatus: '',
        saving: false,
        readOnly: false,
        completed: true,
        body: buildProjectSetupCompletionFixture(onDismissBanner: () {}),
        scrollController: scrollController,
        onSelectStage: (_) {},
        onSaveDraft: null,
        onBack: () {},
        onReturnToProjects: () {},
        onContinue: null,
        onSkip: null,
        onFinalAction: null,
        primaryLabel: YorksV1ProjectStrings.createProject,
      ),
    );
    final shell = _key('project-setup-desktop-shell');
    final rail = tester.getRect(_key('project-setup-desktop-rail'));
    expect(tester.getSize(shell), _viewport);
    _expectContentOnlyChrome();
    expect(rail.top, 0);
    expect(rail.width, 196);
    expect(rail.bottom, _viewport.height);
    expect(_key('yorks-v1-project-create'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      shell,
      matchesGoldenFile(
        'goldens/project_setup_desktop/confirmed_result_1536x1024.png',
      ),
    );
    expect(fixture.repository.commandCalls, 0);
  });

  testWidgets('large text on a wide viewport uses the readable compact flow', (
    tester,
  ) async {
    final fixture = await _fixture(YorksV1ProjectCreationStage.projectDetails);
    await _pump(
      tester,
      fixture.container,
      textScaler: const TextScaler.linear(2),
    );
    expect(_key('project-setup-desktop-shell'), findsNothing);
    expect(_key('yorks-v1-project-reference'), findsOneWidget);
    expect(_key('yorks-v1-project-continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(fixture.repository.commandCalls, 0);
  });

  testWidgets(
    'intermediate text scaling preserves readable fields and actions',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.projectDetails,
      );
      await _pump(
        tester,
        fixture.container,
        textScaler: const TextScaler.linear(1.4),
      );
      expect(_key('yorks-v1-project-reference'), findsOneWidget);
      expect(_key('yorks-v1-project-continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(fixture.repository.commandCalls, 0);
    },
  );

  testWidgets(
    'confirmed desktop create opens once and releases the next creation form',
    (tester) async {
      final repository = _RecordingProjectRepository();
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.reviewAndCreate,
        attachments: const [],
        repositoryOverride: repository,
      );
      final draftId = fixture.draft.draftId;
      final opened = <YorksV1Project>[];
      await _pump(tester, fixture.container, onProjectCreated: opened.add);
      await tester.tap(_key('yorks-v1-project-create'));
      await tester.pumpAndSettle();

      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(opened.single.id, 'created-desktop-project');
      expect(opened.single.state, YorksV1ProjectLifecycle.active);
      final completed = _operationForDraft(fixture, draftId);
      expect(completed.cleanupComplete, isTrue);
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));
      expect(_key('yorks-v1-project-create'), findsNothing);

      final controller = fixture.container.read(
        yorksV1ProjectSetupCreationDraftProvider(_owner).notifier,
      );
      final preferences = fixture.container.read(sharedPreferencesProvider);
      final retired =
          jsonDecode(
                preferences.getString(
                  '${controller.storageKey}:retired:$draftId',
                )!,
              )
              as Map<String, dynamic>;
      expect(retired['retired'], isTrue);
      expect(retired['resultProjectId'], 'created-desktop-project');
      expect(
        preferences.getString('${controller.storageKey}:retired:$draftId'),
        isNotNull,
      );
      expect(
        preferences.getString('${controller.storageKey}:journal:$draftId'),
        isNotNull,
      );

      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));

      // Returning to New project in the same Riverpod container must consume
      // the acknowledged retirement. No caller manually invalidates providers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pump(tester, fixture.container, onProjectCreated: opened.add);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(_inputText(tester, 'yorks-v1-project-reference'), isEmpty);
      expect(_inputText(tester, 'yorks-v1-project-name'), isEmpty);
      expect(fixture.draft.draftId, isNot(draftId));
      expect(
        fixture.draft.currentStage,
        YorksV1ProjectCreationStage.projectDetails,
      );
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));
      expect(opened, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed desktop create returns to the portfolio without protected view capability',
    (tester) async {
      final repository = _RecordingProjectRepository();
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.reviewAndCreate,
        attachments: const [],
        repositoryOverride: repository,
        capabilities: yorksV1EnforcedFeatureActionCapabilities.where(
          (key) => key != YorksV1CapabilityKeys.projectsView,
        ),
      );
      final opened = <YorksV1Project>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => YorksV1ProjectCreateFlowScreen(
              resumeDraftId: fixture.draft.draftId,
              onProjectCreated: opened.add,
            ),
          ),
          GoRoute(
            path: '/yorks/projects',
            builder: (_, _) =>
                const Scaffold(body: Text('Authorized portfolio fallback')),
          ),
          GoRoute(
            path: '/yorks/projects/:projectId',
            builder: (_, _) =>
                const Scaffold(body: Text('Denied project destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pump(
        tester,
        fixture.container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.tap(_key('yorks-v1-project-create'));
      await tester.pumpAndSettle();
      expect(find.text('Authorized portfolio fallback'), findsOneWidget);
      expect(find.text('Denied project destination'), findsNothing);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(opened, isEmpty);
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain activation and original file recovery stay separate from the next creation proposal',
    (tester) async {
      final original = Uint8List.fromList([1, 2, 3]);
      final hash = sha256.convert(original).toString();
      final repository = _RecordingProjectRepository(activationUncertain: true);
      final picker = _QueuedDocumentPicker([
        _document(Uint8List.fromList([3, 2, 1])),
        _document(original),
      ]);
      final documents = _UncertainDocumentsRepository();
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.reviewAndCreate,
        attachments: [
          YorksV1ProjectAttachmentInput(
            localId: 'original-file',
            fileName: 'original.pdf',
            mimeType: 'application/pdf',
            sizeBytes: original.length,
            contentHash: hash,
          ),
        ],
        filesReviewed: true,
        repositoryOverride: repository,
        picker: picker,
        documents: documents,
        capabilities: {
          ...yorksV1EnforcedFeatureActionCapabilities,
          YorksV1CapabilityKeys.documentsView,
          YorksV1CapabilityKeys.documentsUpload,
        },
      );
      final originalDraft = fixture.draft;
      final draftId = originalDraft.draftId;
      final opened = <YorksV1Project>[];
      await _pump(tester, fixture.container, onProjectCreated: opened.add);
      await tester.tap(_key('yorks-v1-project-create'));
      await tester.pumpAndSettle();
      final frozen = _operationForDraft(fixture, draftId);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(opened.single.id, frozen.project!.id);
      expect(frozen.coreSucceeded, isTrue);
      expect(frozen.project!.state, YorksV1ProjectLifecycle.draft);
      expect(
        frozen.activation!.status,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      expect(
        frozen.files.single.status,
        YorksV1ProjectSetupFileStatus.needsReselect,
      );
      expect(frozen.cleanupComplete, isFalse);
      expect(documents.uploads, isEmpty);
      final freshId = fixture.draft.draftId;
      expect(freshId, isNot(draftId));
      expect(fixture.draft.attachments, isEmpty);

      await _pump(
        tester,
        fixture.container,
        child: YorksV1ProjectCreateFlowScreen(
          editItem: _recoveryEditItem(frozen, originalDraft),
        ),
      );
      final editProvider = yorksV1ProjectEditDraftProvider(
        YorksV1ProjectEditDraftContext(
          ownerAuthUserId: _owner,
          projectId: frozen.project!.id,
        ),
      );
      await tester.enterText(
        _key('yorks-v1-project-name'),
        'Independent unpublished project proposal',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final independentProposal = _proposalContent(
        fixture.container.read(editProvider),
      );
      expect(_key('project-setup-pending-recovery'), findsOneWidget);
      final reselect = _key('project-setup-pending-reselect-original-file');
      await _tapVisible(tester, reselect);
      expect(picker.selections, 1);
      expect(documents.uploads, isEmpty);
      expect(
        find.text(YorksV1ProjectStrings.fileContentMismatch.primary),
        findsWidgets,
      );
      expect(
        _proposalContent(fixture.container.read(editProvider)),
        independentProposal,
      );
      await _tapVisible(tester, reselect);
      expect(picker.selections, 2);
      expect(documents.uploads, hasLength(1));
      expect(
        documents.uploads.single.idempotencyKey,
        frozen.files.single.idempotencyKey,
      );
      expect(documents.uploads.single.bytes, original);
      final operation = _operationForDraft(fixture, draftId);
      expect(operation.core.canonicalPayload, frozen.core.canonicalPayload);
      expect(operation.core.idempotencyKey, frozen.core.idempotencyKey);
      expect(
        operation.activation!.idempotencyKey,
        frozen.activation!.idempotencyKey,
      );
      expect(
        operation.files.single.idempotencyKey,
        frozen.files.single.idempotencyKey,
      );
      expect(fixture.draft.draftId, freshId);
      expect(fixture.draft.name, isEmpty);
      expect(
        _proposalContent(fixture.container.read(editProvider)),
        independentProposal,
      );
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));
      expect(opened, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain upload remains recoverable from the authorized project with its original manifest key',
    (tester) async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final repository = _RecordingProjectRepository();
      final picker = _QueuedDocumentPicker([
        _document(bytes),
        _document(Uint8List.fromList([3, 2, 1])),
        _document(bytes),
      ]);
      final documents = _UncertainDocumentsRepository();
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.attachments,
        attachments: const [],
        repositoryOverride: repository,
        picker: picker,
        documents: documents,
        capabilities: {
          ...yorksV1EnforcedFeatureActionCapabilities,
          YorksV1CapabilityKeys.documentsView,
          YorksV1CapabilityKeys.documentsUpload,
        },
      );
      final originalDraft = fixture.draft;
      final draftId = originalDraft.draftId;
      final opened = <YorksV1Project>[];
      await _pump(tester, fixture.container, onProjectCreated: opened.add);
      await tester.tap(find.text(YorksV1ProjectStrings.addAttachment.primary));
      await tester.pumpAndSettle();
      final localId = fixture.draft.attachments.single.localId!;
      expect(
        find.descendant(
          of: _key('yorks-v1-desktop-file-$localId'),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      await tester.tap(_key('yorks-v1-project-continue'));
      await tester.pumpAndSettle();
      await tester.tap(_key('yorks-v1-project-create'));
      await tester.pumpAndSettle();
      final frozen = _operationForDraft(fixture, draftId);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(frozen.project!.state, YorksV1ProjectLifecycle.active);
      expect(
        frozen.files.single.status,
        YorksV1ProjectSetupFileStatus.outcomeUncertain,
      );
      expect(frozen.cleanupComplete, isFalse);
      expect(documents.uploads, hasLength(1));
      final uploadKey = documents.uploads.single.idempotencyKey;
      expect(uploadKey, frozen.files.single.idempotencyKey);
      expect(opened.single.id, frozen.project!.id);
      final freshId = fixture.draft.draftId;
      expect(freshId, isNot(draftId));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      fixture.container.invalidate(
        yorksV1ProjectSetupCoordinatorProvider((
          ownerAuthUserId: _owner,
          draftId: draftId,
          projectId: null,
        )),
      );
      await _pump(tester, fixture.container, onProjectCreated: opened.add);
      expect(fixture.draft.draftId, freshId);
      expect(_inputText(tester, 'yorks-v1-project-name'), isEmpty);
      expect(documents.uploads, hasLength(1));
      expect(opened, hasLength(1));

      await _pump(
        tester,
        fixture.container,
        child: YorksV1ProjectCreateFlowScreen(
          editItem: _recoveryEditItem(frozen, originalDraft),
        ),
      );
      final editProvider = yorksV1ProjectEditDraftProvider(
        YorksV1ProjectEditDraftContext(
          ownerAuthUserId: _owner,
          projectId: frozen.project!.id,
        ),
      );
      await tester.enterText(
        _key('yorks-v1-project-name'),
        'Independent unpublished project proposal',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final independentProposal = _proposalContent(
        fixture.container.read(editProvider),
      );
      final reselect = _key('project-setup-pending-reselect-$localId');
      await _tapVisible(tester, reselect);
      expect(documents.uploads, hasLength(1));
      expect(
        _proposalContent(fixture.container.read(editProvider)),
        independentProposal,
      );
      expect(
        _operationForDraft(fixture, draftId).files.single.contentHash,
        frozen.files.single.contentHash,
      );
      await _tapVisible(tester, reselect);
      expect(documents.uploads, hasLength(2));
      expect(documents.uploads.last.idempotencyKey, uploadKey);
      expect(documents.uploads.last.bytes, bytes);
      expect(
        _operationForDraft(fixture, draftId).core.canonicalPayload,
        frozen.core.canonicalPayload,
      );
      expect(
        _proposalContent(fixture.container.read(editProvider)),
        independentProposal,
      );
      expect(fixture.draft.draftId, freshId);
      expect(repository.creates, hasLength(1));
      expect(repository.activations, hasLength(1));
      expect(opened, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

// This fixture renders only project setup content. The actual shared Yorks
// header/sidebar and portfolio entry are covered by workspace integration tests.
void _expectContentOnlyChrome() {
  expect(find.text(YorksV1ShellStrings.companyName.primary), findsNothing);
  expect(_key('project-setup-workspace-navigation'), findsNothing);
  expect(_key('project-setup-workspace-search'), findsNothing);
  expect(_key('project-setup-mobile-header'), findsNothing);
}

Finder _key(String value) => find.byKey(ValueKey(value));

String _inputText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _key(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  Widget? child,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<YorksV1Project>? onProjectCreated,
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home:
            child ??
            YorksV1ProjectCreateFlowScreen(
              resumeDraftId: container
                  .read(yorksV1ProjectSetupCreationDraftProvider(_owner))
                  .draftId,
              onProjectCreated: onProjectCreated,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<_Fixture> _fixture(
  YorksV1ProjectCreationStage stage, {
  List<YorksV1ProjectBuildingInput>? buildings,
  List<YorksV1InitialProjectMemberInput>? selectedMembers,
  List<YorksV1ProjectTeamDirectoryMember>? directory,
  List<YorksV1ProjectAttachmentInput>? attachments,
  bool filesReviewed = false,
  List<String> reviewedFileIds = const [],
  _NoCommandRepository? repositoryOverride,
  YorksV1DocumentFileService? picker,
  YorksV1DocumentsRepository? documents,
  Iterable<String> capabilities = yorksV1EnforcedFeatureActionCapabilities,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = repositoryOverride ?? _NoCommandRepository();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1AuthUserIdProvider.overrideWithValue(_owner),
      currentUserProvider.overrideWithValue(
        AppUser(
          id: _owner,
          fullName: 'Sarah Ahmed',
          email: 'desktop-fixture@example.invalid',
          role: UserRole.engineer,
          createdAt: DateTime.utc(2026, 10, 4),
        ),
      ),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.projectEngineer),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          yorksV1TrustedFeaturePermissionState(
            role: YorksV1Role.projectEngineer,
            capabilities: capabilities,
          ),
        ),
      ),
      yorksV1ProjectReferenceAdvisoryProvider.overrideWith(
        (ref, query) async => YorksV1ProjectReferenceAdvisory.unavailable,
      ),
      yorksV1ProjectRepositoryProvider.overrideWithValue(repository),
      if (picker != null)
        yorksV1DocumentFileServiceProvider.overrideWithValue(picker),
      if (documents != null)
        yorksV1DocumentsRepositoryProvider.overrideWithValue(documents),
      yorksV1ProjectReviewedCommandRepositoryProvider.overrideWithValue(
        ProjectSetupReviewedRepositoryAdapter(repository),
      ),
      yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(
        _UnitTestDraftStorage(preferences),
      ),
      yorksV1ProjectTeamDirectoryRepositoryProvider.overrideWithValue(
        _DirectoryRepository(directory ?? _directory),
      ),
    ],
  );
  addTearDown(container.dispose);
  final provider = yorksV1ProjectSetupCreationDraftProvider(_owner);
  final controller = container.read(provider.notifier);
  await controller.initialized;
  await controller.save(
    container
        .read(provider)
        .copyWith(
          currentStage: stage,
          visitedStages: {
            for (final value in YorksV1ProjectCreationStage.values)
              if (value.index <= stage.index) value,
          },
          reference: 'YRA-322',
          name: 'NEXUS — Four substations',
          clientName: 'Nexus Energy',
          jobOrContractReference: 'C-4587',
          siteLocation: 'Al Dhafra, Abu Dhabi',
          startDate: DateTime.utc(2024, 3, 12),
          endDate: DateTime.utc(2024, 11, 30),
          notes: 'Four new substations as part of the Nexus programme.',
          parties: _parties,
          initialMembers: selectedMembers ?? _selectedMembers,
          buildings: buildings ?? _buildings,
          attachments: attachments ?? _attachments,
          rawEditorState: {
            if (filesReviewed || reviewedFileIds.isNotEmpty)
              'reviewedOperationalFiles': [
                for (final file in attachments ?? _attachments)
                  if (filesReviewed || reviewedFileIds.contains(file.localId))
                    '${file.localId ?? file.fileName}:${file.contentHash ?? file.sizeBytes}',
              ],
          },
        ),
  );
  return _Fixture(container, repository);
}

class _Fixture {
  const _Fixture(this.container, this.repository);
  final ProviderContainer container;
  final _NoCommandRepository repository;
  YorksV1ProjectCreationDraft get draft =>
      container.read(yorksV1ProjectSetupCreationDraftProvider(_owner));
  YorksV1ProjectSetupOperation get operation => container
      .read(
        yorksV1ProjectSetupCoordinatorProvider((
          ownerAuthUserId: _owner,
          draftId: draft.draftId,
          projectId: null,
        )),
      )
      .operation!;
}

Map<String, dynamic> _proposalContent(YorksV1ProjectCreationDraft draft) => {
  'draftId': draft.draftId,
  'baseVersion': draft.baseVersion,
  'baseSnapshot': draft.baseSnapshot,
  'payload': draft.toCreationInput().toRpcPayload(),
};

YorksV1ProjectSetupOperation _operationForDraft(
  _Fixture fixture,
  String draftId,
) => fixture.container
    .read(
      yorksV1ProjectSetupCoordinatorProvider((
        ownerAuthUserId: _owner,
        draftId: draftId,
        projectId: null,
      )),
    )
    .operation!;

YorksV1ProjectPortfolioItem _recoveryEditItem(
  YorksV1ProjectSetupOperation operation,
  YorksV1ProjectCreationDraft proposal,
) => YorksV1ProjectPortfolioItem(
  project: operation.project!,
  activeBuildingCount: proposal.buildings.length,
  activeProjectEngineerCount: 1,
  activeSiteEngineerCount: 0,
  activeMembers: YorksV1ProjectCreationResult.fromRpcJson(
    operation.core.result!,
  ).members,
  buildings: proposal.buildings,
);

YorksV1SelectedDocument _document(Uint8List bytes) => YorksV1SelectedDocument(
  fileName: 'original.pdf',
  mimeType: 'application/pdf',
  bytes: bytes,
);

class _QueuedDocumentPicker implements YorksV1DocumentFileService {
  _QueuedDocumentPicker(this.queue);
  final List<YorksV1SelectedDocument> queue;
  int selections = 0;
  @override
  Future<YorksV1SelectedDocument?> selectDocument() async =>
      queue[selections++];
  @override
  Future<YorksV1SelectedDocument?> selectImage() async => null;
  @override
  Future<bool> saveDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => true;
}

class _UncertainDocumentsRepository implements YorksV1DocumentsRepository {
  final uploads = <YorksV1DocumentUploadInput>[];
  @override
  Future<YorksV1DocumentWorkspace> upload(
    YorksV1DocumentUploadInput input,
  ) async {
    uploads.add(input);
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.backendUnavailable,
    );
  }

  @override
  Future<YorksV1DocumentWorkspace> getWorkspace(String projectId) async =>
      throw UnimplementedError();
  @override
  Future<void> linkDocument(YorksV1DocumentLinkInput input) async =>
      throw UnimplementedError();
  @override
  Future<void> removeDocumentLink(
    YorksV1DocumentLinkRemovalInput input,
  ) async => throw UnimplementedError();
  @override
  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  }) async => throw UnimplementedError();
}

class _RecordingProjectRepository extends _NoCommandRepository {
  _RecordingProjectRepository({this.activationUncertain = false});
  final bool activationUncertain;
  final creates = <YorksV1ProjectCreationInput>[];
  final activations = <YorksV1SetProjectStateInput>[];
  YorksV1Project _project(YorksV1ProjectLifecycle state) => YorksV1Project(
    id: 'created-desktop-project',
    reference: creates.single.reference,
    name: creates.single.name,
    siteLocation: creates.single.siteLocation,
    state: state,
    version: state == YorksV1ProjectLifecycle.draft ? 1 : 2,
    createdAt: DateTime.utc(2026, 10, 4),
    updatedAt: DateTime.utc(2026, 10, 4),
  );
  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    creates.add(input);
    return YorksV1ProjectCreationResult(
      project: _project(YorksV1ProjectLifecycle.draft),
      scopes: [
        const YorksV1ProjectScope(
          id: 'common-scope',
          projectId: 'created-desktop-project',
          kind: YorksV1ProjectScopeKind.common,
          code: 'COMMON',
          name: 'Common / All Buildings',
          active: true,
        ),
        for (final building in input.buildings)
          YorksV1ProjectScope(
            id: 'scope-${building.code}',
            projectId: 'created-desktop-project',
            kind: YorksV1ProjectScopeKind.building,
            code: building.code,
            name: building.name,
            active: true,
            floorsOrLevels: building.floorsOrLevels,
            hasFrpRoom: building.hasFrpRoom,
          ),
      ],
      members: [
        YorksV1ProjectMember(
          id: 'creator-membership',
          projectId: 'created-desktop-project',
          memberAuthUserId: _owner,
          projectRole: YorksV1ProjectMembershipRole.projectEngineer,
          effectiveFrom: DateTime.utc(2024, 3, 12),
          createdAt: DateTime.utc(2026, 10, 4),
        ),
      ],
      parties: input.parties,
      attachments: const [],
      commonScopeId: 'common-scope',
      idempotencyKey: input.idempotencyKey,
    );
  }

  @override
  Future<YorksV1Project> setProjectState(
    YorksV1SetProjectStateInput input,
  ) async {
    activations.add(input);
    if (activationUncertain) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return _project(YorksV1ProjectLifecycle.active);
  }
}

class _DirectoryRepository implements YorksV1ProjectTeamDirectoryRepository {
  const _DirectoryRepository(this.members);
  final List<YorksV1ProjectTeamDirectoryMember> members;
  @override
  Future<List<YorksV1ProjectTeamDirectoryMember>> listActiveMembers() async =>
      members;
}

/// Unit seam only. Real browser Web Locks proof lives in the browser storage
/// suite; this in-process fixture makes no cross-process guarantee.
class _UnitTestDraftStorage extends SharedPreferencesProjectDraftStorage {
  _UnitTestDraftStorage(super.preferences);
  @override
  bool get supportsAtomicOwnership => true;
}

class _NoCommandRepository implements YorksV1ProjectRepository {
  int commandCalls = 0;
  Never _unexpected() {
    commandCalls++;
    throw StateError('A desktop draft interaction issued a server command');
  }

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async => _unexpected();
  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) async =>
      _unexpected();
  @override
  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  ) async => _unexpected();
  @override
  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  ) async => _unexpected();
  @override
  Future<YorksV1Project> setProjectState(
    YorksV1SetProjectStateInput input,
  ) async => _unexpected();
  @override
  Future<YorksV1Project> archiveProject(
    YorksV1ArchiveProjectInput input,
  ) async => _unexpected();
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter cache from the test runner');
}

const _directory = [
  YorksV1ProjectTeamDirectoryMember(
    authUserId: _owner,
    displayName: 'Sarah Ahmed',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'tom',
    displayName: 'Tom Mitchell',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'emma',
    displayName: 'Emma Wilson',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'james',
    displayName: 'James Dobson',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'laura',
    displayName: 'Laura Chen',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'sophie',
    displayName: 'Sophie Reed',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
];
const _selectedMembers = [
  YorksV1InitialProjectMemberInput(
    authUserId: 'tom',
    projectRole: YorksV1ProjectMembershipRole.siteEngineer,
  ),
  YorksV1InitialProjectMemberInput(
    authUserId: 'emma',
    projectRole: YorksV1ProjectMembershipRole.siteEngineer,
  ),
];
const _parties = [
  YorksV1ProjectPartyInput(
    kind: YorksV1ProjectPartyKind.subcontractor,
    name: 'Northfield Electrical Ltd',
    retainedFields: {'local_row_id': 'northfield'},
  ),
  YorksV1ProjectPartyInput(
    kind: YorksV1ProjectPartyKind.subcontractor,
    name: 'Delta Mechanical Services',
    retainedFields: {'local_row_id': 'delta'},
  ),
  YorksV1ProjectPartyInput(
    kind: YorksV1ProjectPartyKind.otherContractor,
    name: 'Siteworks UK',
    retainedFields: {'local_row_id': 'siteworks'},
  ),
  YorksV1ProjectPartyInput(
    kind: YorksV1ProjectPartyKind.otherContractor,
    name: 'Crane Hire Co.',
    retainedFields: {'local_row_id': 'crane'},
  ),
  YorksV1ProjectPartyInput(
    kind: YorksV1ProjectPartyKind.otherContractor,
    name: 'Safety Solutions',
    retainedFields: {'local_row_id': 'safety'},
  ),
];
const _buildings = [
  YorksV1ProjectBuildingInput(
    localRowId: 'building-df3w',
    code: 'DF3W',
    name: 'DF3W substation',
    floorsOrLevels: ['Ground', 'Roof'],
    deliveryAddress: 'Al Dhafra, Abu Dhabi',
    hasFrpRoom: true,
  ),
  YorksV1ProjectBuildingInput(
    localRowId: 'building-df4w',
    code: 'DF4W',
    name: 'DF4W substation',
    floorsOrLevels: ['Ground'],
  ),
  YorksV1ProjectBuildingInput(
    localRowId: 'building-df6w',
    code: 'DF6W',
    name: 'DF6W substation',
    floorsOrLevels: ['Ground', 'L1'],
  ),
  YorksV1ProjectBuildingInput(
    localRowId: 'building-df7w',
    code: 'DF7W',
    name: 'DF7W substation',
    hasFrpRoom: true,
  ),
];
const _attachments = [
  YorksV1ProjectAttachmentInput(
    localId: 'drawing-file',
    fileName: 'DF3W_General_Arrangement.pdf',
    mimeType: 'application/pdf',
    sizeBytes: 2400000,
    contentHash: 'drawing-fixture',
  ),
  YorksV1ProjectAttachmentInput(
    localId: 'calculation-file',
    fileName: 'Load_Calculations_DF3W.xlsx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sizeBytes: 1100000,
    contentHash: 'calculation-fixture',
  ),
  YorksV1ProjectAttachmentInput(
    localId: 'programme-file',
    fileName: 'Programme_DF3W.docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    sizeBytes: 856000,
    contentHash: 'programme-fixture',
  ),
  YorksV1ProjectAttachmentInput(
    localId: 'schematics-file',
    fileName: 'Electrical_Schematics.pdf',
    mimeType: 'application/pdf',
    sizeBytes: 4800000,
    contentHash: 'schematics-fixture',
  ),
];

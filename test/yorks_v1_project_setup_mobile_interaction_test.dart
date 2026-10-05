import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_setup_mobile_shell.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_completion.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_desktop_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_team_directory_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/project_setup_completion_fixture.dart';
import 'support/project_setup_reviewed_repository_adapter.dart';
import 'support/yorks_v1_permission_test_support.dart';

const _referenceViewport = Size(431, 863);
const _owner = 'mobile-fixture-sarah';

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
    '360px Arabic Details omits the information card and keeps inline validation',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.projectDetails,
        language: AppLanguage.arabic,
      );
      await _pump(tester, fixture.container, viewport: const Size(360, 800));
      expect(
        find.text(
          YorksV1ProjectSetupDesktopStrings.toContinue.active(
            AppLanguage.arabic,
          ),
        ),
        findsNothing,
      );
      expect(
        find.text(
          YorksV1ProjectSetupDesktopStrings.otherDetailsLater.active(
            AppLanguage.arabic,
          ),
        ),
        findsNothing,
      );
      await tester.ensureVisible(_key('yorks-v1-project-reference'));
      await tester.enterText(_key('yorks-v1-project-reference'), '');
      await tester.ensureVisible(_key('yorks-v1-project-name'));
      await tester.enterText(_key('yorks-v1-project-name'), '');
      await _tapVisible(tester, _key('yorks-v1-project-continue'));
      expect(
        find.text(
          YorksV1ProjectStrings.requiredField.active(AppLanguage.arabic),
        ),
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
    '360px Arabic Add creates one building and Save edits its stable identity',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.buildings,
        language: AppLanguage.arabic,
        buildings: const [],
      );
      await _pump(tester, fixture.container, viewport: const Size(360, 800));
      final apply = _key('yorks-v1-mobile-apply-building');
      expect(
        find.descendant(
          of: apply,
          matching: find.text(
            YorksV1ProjectStrings.addBuilding.active(AppLanguage.arabic),
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(_key('yorks-v1-building-name'));
      await tester.enterText(_key('yorks-v1-building-name'), 'مبنى جديد');
      await _tapVisible(tester, apply);
      final created = fixture.draft.buildings.single;
      expect(created.localRowId, isNotEmpty);
      await _tapVisible(
        tester,
        _key('yorks-v1-mobile-building-${created.localRowId}'),
      );
      expect(
        find.descendant(
          of: apply,
          matching: find.text(
            YorksV1ProjectSetupDesktopStrings.saveBuilding.active(
              AppLanguage.arabic,
            ),
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(_key('yorks-v1-building-name'));
      await tester.enterText(
        _key('yorks-v1-building-name'),
        'مبنى بعد التعديل',
      );
      await tester.ensureVisible(apply);
      expect(tester.getSize(apply).height, greaterThanOrEqualTo(44));
      await _tapVisible(tester, apply);
      expect(fixture.draft.buildings, hasLength(1));
      expect(fixture.draft.buildings.single.localRowId, created.localRowId);
      expect(fixture.draft.buildings.single.name, 'مبنى بعد التعديل');
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in YorksV1ProjectCreationStage.values) {
    testWidgets('mobile reference ${stage.name} — content-only431×863', (
      tester,
    ) async {
      final fixture = await _fixture(stage, filesReviewed: true);
      await _pump(tester, fixture.container);
      if (stage == YorksV1ProjectCreationStage.buildings) {
        await _tapVisible(
          tester,
          _key('yorks-v1-mobile-building-building-df3w'),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        // Opening the real editor focuses its field and reveals it. Reset
        // only the reference capture's scroll; user focus behavior is retained.
        FocusManager.instance.primaryFocus?.unfocus();
        await fixture.container
            .read(yorksV1ProjectSetupCreationDraftProvider(_owner).notifier)
            .flush();
        tester
            .widget<YorksV1ProjectSetupMobileShell>(
              find.byType(YorksV1ProjectSetupMobileShell),
            )
            .scrollController
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 300));
        await fixture.container
            .read(yorksV1ProjectSetupCreationDraftProvider(_owner).notifier)
            .flush();
        await tester.pumpAndSettle();
      }
      final shell = _key('project-setup-mobile-shell');
      expect(shell, findsOneWidget);
      expect(tester.getSize(shell), _referenceViewport);
      _expectContentOnlyChrome();
      expect(_key('project-setup-mobile-stepper'), findsOneWidget);
      final stepper = tester.getRect(_key('project-setup-mobile-stepper'));
      expect(stepper.top, greaterThanOrEqualTo(0));
      expect(stepper.bottom, lessThanOrEqualTo(_referenceViewport.height));
      _expectPrimary(tester, stage, _referenceViewport);
      _expectVisibleButtonTargets(tester, _referenceViewport);
      expect(tester.takeException(), isNull);
      await expectLater(
        shell,
        matchesGoldenFile(
          'goldens/project_setup_mobile/${stage.name}_431x863.png',
        ),
      );
      await _scrollThroughToBottom(tester);
      _expectPrimary(tester, stage, _referenceViewport);
      _expectVisibleButtonTargets(tester, _referenceViewport);
      expect(tester.takeException(), isNull);
      await expectLater(
        shell,
        matchesGoldenFile(
          'goldens/project_setup_mobile/${stage.name}_bottom_431x863.png',
        ),
      );
      expect(fixture.repository.commandCalls, 0);
      // Finish the bottom-scroll checkpoint while its listeners are mounted;
      // testWidgets verifies pending timers before registered teardown hooks.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('mobile reference confirmed result — content-only431×863', (
    tester,
  ) async {
    final fixture = await _fixture(YorksV1ProjectCreationStage.reviewAndCreate);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _pump(
      tester,
      fixture.container,
      child: YorksV1ProjectSetupMobileShell(
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
        body: buildProjectSetupCompletionFixture(
          compact: true,
          onDismissBanner: () {},
        ),
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
    final shell = _key('project-setup-mobile-shell');
    expect(tester.getSize(shell), _referenceViewport);
    _expectContentOnlyChrome();
    expect(_key('yorks-v1-project-create'), findsNothing);
    _expectVisibleButtonTargets(tester, _referenceViewport);
    expect(tester.takeException(), isNull);
    await expectLater(
      shell,
      matchesGoldenFile(
        'goldens/project_setup_mobile/confirmed_result_431x863.png',
      ),
    );
    await _scrollThroughToBottom(tester);
    _expectVisibleButtonTargets(tester, _referenceViewport);
    expect(tester.takeException(), isNull);
    await expectLater(
      shell,
      matchesGoldenFile(
        'goldens/project_setup_mobile/confirmed_result_bottom_431x863.png',
      ),
    );
    expect(fixture.repository.commandCalls, 0);
  });

  for (final stage in YorksV1ProjectCreationStage.values) {
    testWidgets(
      '360px ${stage.name} keeps complete actions and touch targets',
      (tester) async {
        const viewport = Size(360, 800);
        final fixture = await _fixture(stage, filesReviewed: true);
        await _pump(tester, fixture.container, viewport: viewport);
        _expectPrimary(tester, stage, viewport);
        _expectVisibleButtonTargets(tester, viewport);
        expect(tester.takeException(), isNull);
        expect(fixture.repository.commandCalls, 0);
      },
    );
  }

  for (final viewport in [const Size(768, 1024), const Size(1024, 768)]) {
    for (final stage in [
      YorksV1ProjectCreationStage.projectDetails,
      YorksV1ProjectCreationStage.buildings,
    ]) {
      testWidgets('tablet $viewport ${stage.name} remains readable', (
        tester,
      ) async {
        final fixture = await _fixture(stage, filesReviewed: true);
        await _pump(tester, fixture.container, viewport: viewport);
        expect(_key('project-setup-desktop-shell'), findsNothing);
        _expectPrimary(tester, stage, viewport);
        expect(tester.takeException(), isNull);
        expect(fixture.repository.commandCalls, 0);
      });
    }
  }

  for (final stage in [
    YorksV1ProjectCreationStage.projectDetails,
    YorksV1ProjectCreationStage.attachments,
  ]) {
    testWidgets('Arabic360px 200% ${stage.name} reflows full actions', (
      tester,
    ) async {
      const viewport = Size(360, 800);
      final fixture = await _fixture(
        stage,
        filesReviewed: true,
        language: AppLanguage.arabic,
      );
      await _pump(
        tester,
        fixture.container,
        viewport: viewport,
        textScaler: const TextScaler.linear(2),
        safePadding: const EdgeInsets.only(top: 24, bottom: 20),
      );
      final shell = _key('project-setup-mobile-shell');
      expect(shell, findsOneWidget);
      expect(
        Directionality.of(tester.element(_key('yorks-v1-project-continue'))),
        TextDirection.rtl,
      );
      _expectPrimary(tester, stage, viewport, language: AppLanguage.arabic);
      expect(
        tester.getRect(_key('yorks-v1-project-continue')).bottom,
        lessThanOrEqualTo(780),
      );
      _expectVisibleButtonTargets(tester, viewport);
      expect(tester.takeException(), isNull);
      expect(fixture.repository.commandCalls, 0);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'phone keyboard and safe area keep notes reachable at $scale×',
      (tester) async {
        const viewport = Size(360, 800);
        final fixture = await _fixture(
          YorksV1ProjectCreationStage.projectDetails,
        );
        await _pump(
          tester,
          fixture.container,
          viewport: viewport,
          textScaler: TextScaler.linear(scale),
          safePadding: const EdgeInsets.only(top: 24, bottom: 20),
          keyboardInset: 300,
        );
        final notes = _key('yorks-v1-project-notes');
        final input = find.descendant(
          of: notes,
          matching: find.byType(EditableText),
        );
        await tester.ensureVisible(input);
        await tester.showKeyboard(notes);
        await tester.enterText(notes, 'Keyboard entry remains a device draft.');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        final action = tester.getRect(_key('yorks-v1-project-continue'));
        expect(action.bottom, lessThanOrEqualTo(480));
        expect(tester.getRect(input).bottom, lessThanOrEqualTo(action.top));
        _expectPrimary(
          tester,
          YorksV1ProjectCreationStage.projectDetails,
          viewport,
        );
        expect(fixture.draft.notes, 'Keyboard entry remains a device draft.');
        expect(fixture.draft.isAcknowledged, isTrue);
        expect(fixture.repository.commandCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'transient 1px viewport retains the same draft and unapplied editor',
    (tester) async {
      const tinyViewport = Size(1, 1);
      const notes = '  Raw notes before navigation\nSecond line stays.  ';
      const pendingName = 'DF3W revision — not applied';
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.buildings,
        buildings: const [
          YorksV1ProjectBuildingInput(
            localRowId: 'stable-local-row',
            sourceScopeId: 'retained-server-scope',
            code: 'DF3W',
            name: 'Applied building',
            hasFrpRoom: true,
            flags: {'has_frp_room': true, 'future_flag': 'retain'},
            retainedFields: {'future_source': 'retain'},
          ),
        ],
      );
      final controller = fixture.container.read(
        yorksV1ProjectSetupCreationDraftProvider(_owner).notifier,
      );
      await controller.save(
        fixture.draft.copyWith(
          notes: notes,
          rawEditorState: {
            ...fixture.draft.rawEditorState,
            'buildingLocalId': 'stable-local-row',
            'buildingName': 'Restored unfinished editor',
            'buildingCode': 'DF3W',
            'buildingFloors': 'Ground, Roof',
            'buildingAddress': '  Delivery notes\nKeep this line.  ',
            'buildingFrp': false,
          },
        ),
      );
      final draftId = fixture.draft.draftId;
      final applied = fixture.draft.buildings.single.toDraftJson();
      await _pump(tester, fixture.container, viewport: tinyViewport);
      final flowState = tester.state(
        find.byType(YorksV1ProjectCreateFlowScreen),
      );

      void expectPreserved() {
        expect(fixture.draft.draftId, draftId);
        expect(fixture.draft.notes, notes);
        expect(fixture.draft.buildings.single.toDraftJson(), applied);
        expect(
          fixture.draft.rawEditorState['buildingLocalId'],
          'stable-local-row',
        );
        expect(fixture.draft.rawEditorState['buildingFrp'], isFalse);
        expect(fixture.repository.commandCalls, 0);
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
        expect(
          tester.state(find.byType(YorksV1ProjectCreateFlowScreen)),
          same(flowState),
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> resize(Size viewport) async {
        tester.view.physicalSize = viewport;
        await tester.binding.setSurfaceSize(viewport);
        await tester.pumpAndSettle();
      }

      expect(_key('project-setup-mobile-shell'), findsNothing);
      expectPreserved();
      await resize(_referenceViewport);
      expect(_key('project-setup-mobile-shell'), findsOneWidget);
      expect(
        _inputText(tester, 'yorks-v1-building-name'),
        'Restored unfinished editor',
      );
      expectPreserved();
      await tester.ensureVisible(_key('yorks-v1-building-name'));
      await tester.enterText(_key('yorks-v1-building-name'), pendingName);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await controller.flush();
      await tester.pumpAndSettle();
      expect(fixture.draft.isAcknowledged, isTrue);
      expect(fixture.draft.rawEditorState['buildingName'], pendingName);
      expectPreserved();

      await resize(tinyViewport);
      expect(_key('project-setup-mobile-shell'), findsNothing);
      expect(fixture.draft.rawEditorState['buildingName'], pendingName);
      expectPreserved();
      await resize(_referenceViewport);
      expect(_key('project-setup-mobile-shell'), findsOneWidget);
      expect(_inputText(tester, 'yorks-v1-building-name'), pendingName);
      expect(
        _inputText(tester, 'yorks-v1-building-delivery-address'),
        '  Delivery notes\nKeep this line.  ',
      );
      expect(
        tester
            .widget<FilledButton>(_key('yorks-v1-project-continue'))
            .onPressed,
        isNull,
      );
      expectPreserved();
    },
  );

  testWidgets(
    'phone filtered building Apply retains scope identity and false FRP',
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
      await _pump(tester, fixture.container, viewport: const Size(360, 800));
      await tester.enterText(_key('yorks-v1-mobile-building-search'), 'Second');
      await tester.pumpAndSettle();
      expect(_key('yorks-v1-mobile-building-first-row'), findsNothing);
      await _tapVisible(tester, _key('yorks-v1-mobile-building-second-row'));
      await tester.ensureVisible(_key('yorks-v1-building-name'));
      await tester.enterText(_key('yorks-v1-building-name'), 'Second renamed');
      await _tapVisible(tester, _key('yorks-v1-mobile-building-frp'));
      expect(fixture.draft.buildings[1].name, 'Second building');
      expect(
        tester
            .widget<FilledButton>(_key('yorks-v1-project-continue'))
            .onPressed,
        isNull,
      );
      await _tapVisible(tester, _key('yorks-v1-mobile-apply-building'));
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

  testWidgets('phone Cancel preserves the applied building and its metadata', (
    tester,
  ) async {
    final fixture = await _fixture(YorksV1ProjectCreationStage.buildings);
    await _pump(tester, fixture.container, viewport: const Size(360, 800));
    final original = fixture.draft.buildings.first.toDraftJson();
    await _tapVisible(tester, _key('yorks-v1-mobile-building-building-df3w'));
    await tester.ensureVisible(_key('yorks-v1-building-name'));
    await tester.enterText(_key('yorks-v1-building-name'), 'Unapplied value');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(fixture.draft.buildings.first.toDraftJson(), original);
    await _tapVisible(tester, _key('yorks-v1-mobile-cancel-building'));
    expect(fixture.draft.buildings.first.toDraftJson(), original);
    expect(_inputText(tester, 'yorks-v1-building-name'), isEmpty);
    expect(fixture.repository.commandCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone optional categories and missing bytes do not block core creation',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.reviewAndCreate,
      );
      await _pump(tester, fixture.container, viewport: const Size(360, 800));
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

  testWidgets(
    'phone same-name filtered file menu removes the stable identity',
    (tester) async {
      final fixture = await _fixture(
        YorksV1ProjectCreationStage.attachments,
        attachments: const [
          YorksV1ProjectAttachmentInput(
            localId: 'first-file',
            fileName: 'same-name.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 11,
            contentHash: 'first-content-hash',
          ),
          YorksV1ProjectAttachmentInput(
            localId: 'second-file',
            fileName: 'same-name.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 22,
            contentHash: 'second-content-hash',
            categoryKey: 'drawing',
          ),
        ],
      );
      await _pump(tester, fixture.container, viewport: const Size(360, 800));
      final second = _key('yorks-v1-mobile-file-second-file');
      expect(
        find.descendant(of: second, matching: find.byType(Checkbox)),
        findsNothing,
      );
      await _tapVisible(tester, _key('yorks-v1-mobile-file-category-filter'));
      await tester.tap(
        find
            .text(YorksV1ProjectSetupDesktopStrings.categoryDrawing.primary)
            .last,
      );
      await tester.pumpAndSettle();
      expect(_key('yorks-v1-mobile-file-first-file'), findsNothing);
      expect(second, findsOneWidget);
      // The selected file is now displayed index zero. Its action must still
      // resolve the original local identity and content hash.
      await _tapVisible(tester, _key('yorks-v1-mobile-file-menu-second-file'));
      await tester.tap(find.text(YorksV1ProjectStrings.remove.primary).last);
      await tester.pumpAndSettle();
      expect(fixture.draft.attachments, hasLength(1));
      expect(fixture.draft.attachments.single.localId, 'first-file');
      expect(
        fixture.draft.attachments.single.contentHash,
        'first-content-hash',
      );
      expect(fixture.draft.isAcknowledged, isTrue);
      expect(fixture.repository.commandCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

// Project setup owns its fields/stages/actions only. Shared workspace chrome is
// asserted separately by the real Projects-to-Create integration fixture.
void _expectContentOnlyChrome() {
  expect(find.text(YorksV1ShellStrings.companyName.primary), findsNothing);
  expect(_key('project-setup-mobile-header'), findsNothing);
  expect(_key('project-setup-workspace-navigation'), findsNothing);
  expect(_key('project-setup-workspace-search'), findsNothing);
}

Finder _key(String value) => find.byKey(ValueKey(value));

String _inputText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _key(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollThroughToBottom(WidgetTester tester) async {
  final shell = tester.widget<YorksV1ProjectSetupMobileShell>(
    find.byType(YorksV1ProjectSetupMobileShell),
  );
  final controller = shell.scrollController;
  expect(controller.hasClients, isTrue);
  final position = controller.position;
  // Walk one viewport at a time, not just a final jump that could conceal a
  // middle section's layout exception. Each checkpoint preserves the draft.
  final increment = position.viewportDimension * .8;
  while (controller.offset < position.maxScrollExtent) {
    controller.jumpTo(
      (controller.offset + increment)
          .clamp(0, position.maxScrollExtent)
          .toDouble(),
    );
    await tester.pumpAndSettle();
    _expectVisibleButtonTargets(
      tester,
      tester.getSize(_key('project-setup-mobile-shell')),
    );
    expect(tester.takeException(), isNull);
  }
  expect(controller.offset, position.maxScrollExtent);
}

void _expectPrimary(
  WidgetTester tester,
  YorksV1ProjectCreationStage stage,
  Size viewport, {
  AppLanguage language = AppLanguage.english,
}) {
  final review = stage == YorksV1ProjectCreationStage.reviewAndCreate;
  final action = _key('yorks-v1-project-${review ? 'create' : 'continue'}');
  expect(action, findsOneWidget);
  final rect = tester.getRect(action);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
  expect(rect.width, greaterThanOrEqualTo(44));
  expect(rect.height, greaterThanOrEqualTo(44));
  final label = (switch (stage) {
    YorksV1ProjectCreationStage.projectDetails =>
      YorksV1ProjectSetupShellStrings.continueParties,
    YorksV1ProjectCreationStage.partiesAndAccess =>
      YorksV1ProjectSetupShellStrings.continueBuildings,
    YorksV1ProjectCreationStage.buildings =>
      YorksV1ProjectSetupShellStrings.continueAttachments,
    YorksV1ProjectCreationStage.attachments =>
      YorksV1ProjectSetupShellStrings.continueLabel,
    YorksV1ProjectCreationStage.reviewAndCreate =>
      YorksV1ProjectStrings.createProject,
  }).active(language);
  final text = find.descendant(of: action, matching: find.text(label));
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
}

void _expectVisibleButtonTargets(WidgetTester tester, Size viewport) {
  final controls = find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is TextField ||
        widget is DropdownButton ||
        widget is Checkbox,
  );
  for (final element in controls.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    if (!Rect.fromLTWH(
      0,
      0,
      viewport.width,
      viewport.height,
    ).contains(rect.center)) {
      continue;
    }
    expect(
      rect.width,
      greaterThanOrEqualTo(44),
      reason: '${element.widget.runtimeType} actual control bounds: $rect',
    );
    expect(
      rect.height,
      greaterThanOrEqualTo(44),
      reason: '${element.widget.runtimeType} actual control bounds: $rect',
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  Widget? child,
  Size viewport = _referenceViewport,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets safePadding = EdgeInsets.zero,
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            padding: safePadding,
            viewPadding: safePadding,
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: Directionality(
            textDirection: container.read(languageProvider).isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child!,
          ),
        ),
        home:
            child ??
            YorksV1ProjectCreateFlowScreen(
              resumeDraftId: container
                  .read(yorksV1ProjectSetupCreationDraftProvider(_owner))
                  .draftId,
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
  bool filesReviewed = false,
  AppLanguage language = AppLanguage.english,
  List<YorksV1ProjectBuildingInput> buildings = _buildings,
  List<YorksV1ProjectAttachmentInput> attachments = _attachments,
}) async {
  SharedPreferences.setMockInitialValues({'selected_language': language.code});
  final preferences = await SharedPreferences.getInstance();
  final repository = _NoCommandRepository();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1FeatureFlagsProvider.overrideWithValue(
        const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          projectSetup: true,
        ),
      ),
      yorksV1AuthUserIdProvider.overrideWithValue(_owner),
      currentUserProvider.overrideWithValue(
        AppUser(
          id: _owner,
          fullName: 'Sarah Ahmed',
          email: 'mobile-fixture@example.invalid',
          role: UserRole.engineer,
          createdAt: DateTime.utc(2026, 10, 4),
        ),
      ),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.projectEngineer),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          yorksV1TrustedFeaturePermissionState(
            role: YorksV1Role.projectEngineer,
          ),
        ),
      ),
      yorksV1ProjectReferenceAdvisoryProvider.overrideWith(
        (ref, query) async => YorksV1ProjectReferenceAdvisory.unavailable,
      ),
      yorksV1ProjectRepositoryProvider.overrideWithValue(repository),
      yorksV1ProjectReviewedCommandRepositoryProvider.overrideWithValue(
        ProjectSetupReviewedRepositoryAdapter(repository),
      ),
      yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(
        _UnitTestDraftStorage(preferences),
      ),
      yorksV1ProjectTeamDirectoryRepositoryProvider.overrideWithValue(
        const _DirectoryRepository(),
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
          parties: const [
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
              name: 'Crane Hire Co.',
              retainedFields: {'local_row_id': 'crane'},
            ),
          ],
          initialMembers: const [
            YorksV1InitialProjectMemberInput(
              authUserId: 'tom',
              projectRole: YorksV1ProjectMembershipRole.siteEngineer,
            ),
            YorksV1InitialProjectMemberInput(
              authUserId: 'emma',
              projectRole: YorksV1ProjectMembershipRole.siteEngineer,
            ),
          ],
          buildings: buildings,
          attachments: attachments,
          rawEditorState: {
            if (filesReviewed)
              'reviewedOperationalFiles': [
                for (final file in attachments)
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
}

/// A unit-only in-process ownership seam, not native cross-process evidence.
class _UnitTestDraftStorage extends SharedPreferencesProjectDraftStorage {
  _UnitTestDraftStorage(super.preferences);
  @override
  bool get supportsAtomicOwnership => true;
}

class _DirectoryRepository implements YorksV1ProjectTeamDirectoryRepository {
  const _DirectoryRepository();
  @override
  Future<List<YorksV1ProjectTeamDirectoryMember>> listActiveMembers() async =>
      const [
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
      ];
}

class _NoCommandRepository implements YorksV1ProjectRepository {
  int commandCalls = 0;
  Never _unexpected() {
    commandCalls++;
    throw StateError('A mobile draft interaction issued a server command');
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_completion.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_attachment_preview.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_desktop_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_navigation_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_team_directory_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';
import 'support/project_setup_reviewed_repository_adapter.dart';

const _authUserId = 'test-auth-user-001';
final _testOwnerProvider = StateProvider<String>((ref) => _authUserId);

void main() {
  setUpAll(() async {
    final nexus = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final cache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([nexus.load(), arabic.load(), icons.load()]);
  });

  Future<ProviderContainer> createContainer({
    required YorksV1Role? role,
    required _FakeProjectRepository repository,
    YorksV1CurrentPermissionSnapshotState? permissionState,
    YorksV1ProjectTeamDirectoryRepository? teamDirectoryRepository,
    YorksV1DocumentFileService? documentFileService,
    AnalyticsService? analytics,
    List<YorksV1ProjectPortfolioItem> Function()? portfolioItems,
    ProjectDraftAtomicStorage Function(SharedPreferences)? draftStorageFactory,
  }) async {
    SharedPreferences.setMockInitialValues({});
    repository.creatorRole = role;
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1ProjectReferenceAdvisoryProvider.overrideWith(
          (ref, query) async => YorksV1ProjectReferenceAdvisory.unavailable,
        ),
        if (analytics != null)
          analyticsServiceProvider.overrideWithValue(analytics),
        yorksV1AuthUserIdProvider.overrideWith(
          (ref) => ref.watch(_testOwnerProvider),
        ),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            permissionState ??
                yorksV1TrustedFeaturePermissionState(
                  role: role ?? YorksV1Role.admin,
                ),
          ),
        ),
        yorksV1ProjectRepositoryProvider.overrideWithValue(repository),
        if (portfolioItems != null)
          yorksV1ProjectPortfolioProvider.overrideWith(
            (ref) async => portfolioItems(),
          ),
        yorksV1ProjectReviewedCommandRepositoryProvider.overrideWithValue(
          ProjectSetupReviewedRepositoryAdapter(repository),
        ),
        yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(
          draftStorageFactory?.call(preferences) ??
              _SupportedTestDraftStorage(preferences),
        ),
        yorksV1ProjectTeamDirectoryRepositoryProvider.overrideWithValue(
          teamDirectoryRepository ?? _FakeTeamDirectoryRepository(),
        ),
        if (documentFileService != null)
          yorksV1DocumentFileServiceProvider.overrideWithValue(
            documentFileService,
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('renders the exact five R35 stages on desktop and mobile', (
    tester,
  ) async {
    for (final size in [
      const Size(1366, 768),
      const Size(1024, 768),
      const Size(390, 844),
      const Size(360, 800),
    ]) {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      await _pumpScreen(tester, container, size: size);

      expect(
        find.text(YorksV1ProjectStrings.projectDetails.primary),
        findsWidgets,
      );
      if (size.width >= 1100) {
        for (final label in [
          YorksV1ProjectStrings.partiesAndAccess,
          YorksV1ProjectStrings.buildings,
          YorksV1ProjectStrings.attachments,
          YorksV1ProjectStrings.reviewAndCreate,
        ]) {
          expect(find.text(label.primary), findsWidgets);
        }
      } else {
        expect(
          find.byKey(const ValueKey('project-setup-mobile-shell')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('project-setup-mobile-stepper')),
          findsOneWidget,
        );
        for (final stage in YorksV1ProjectCreationStage.values) {
          expect(
            find.byKey(ValueKey('project-setup-mobile-step-${stage.name}')),
            findsOneWidget,
          );
        }
      }
      expect(
        find.text(YorksV1ProjectStrings.typedDateFormatHelp.primary),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('setup text inputs expose their visible name on the input node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final stage in [
      YorksV1ProjectCreationStage.projectDetails,
      YorksV1ProjectCreationStage.partiesAndAccess,
      YorksV1ProjectCreationStage.buildings,
    ]) {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final controller = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
      );
      await controller.initialized;
      await controller.save(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .copyWith(currentStage: stage),
      );
      await _pumpScreen(tester, container, size: const Size(1366, 1500));
      if (stage == YorksV1ProjectCreationStage.projectDetails) {
        await tester.tap(
          find.text(YorksV1ProjectStrings.optionalContacts.primary),
        );
        await tester.pumpAndSettle();
      }
      final inputs = find.byType(TextFormField);
      expect(inputs, findsWidgets);
      for (final element in inputs.evaluate()) {
        final input = find.byWidget(element.widget);
        String? visibleName;
        element.visitAncestorElements((ancestor) {
          final widget = ancestor.widget;
          if (widget is Semantics &&
              (widget.properties.label?.isNotEmpty ?? false)) {
            visibleName = widget.properties.label;
            return false;
          }
          return true;
        });
        expect(visibleName, isNotEmpty);
        final node = tester.getSemantics(input);
        expect(node.flagsCollection.isTextField, isTrue);
        expect(node.label, contains(visibleName!));
      }
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('review Edit controls name their own section', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    final controller = container.read(
      yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
    );
    await controller.initialized;
    await controller.save(
      container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .copyWith(currentStage: YorksV1ProjectCreationStage.reviewAndCreate),
    );
    await _pumpScreen(tester, container, size: const Size(1366, 1500));
    for (final label in [
      YorksV1ProjectStrings.editProjectDetails.primary,
      YorksV1ProjectStrings.editPartiesAccess.primary,
      YorksV1ProjectStrings.editBuildings.primary,
      YorksV1ProjectStrings.editAttachments.primary,
    ]) {
      final button = find.bySemanticsLabel(label);
      expect(button, findsOneWidget);
      final node = tester.getSemantics(button);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, contains(label));
    }
    semantics.dispose();
  });

  testWidgets('create access and review show the server creator membership', (
    tester,
  ) async {
    for (final role in [
      YorksV1Role.projectEngineer,
      YorksV1Role.siteEngineer,
      YorksV1Role.seniorMechanicalEngineer,
      YorksV1Role.projectManager,
      YorksV1Role.workshopInCharge,
      YorksV1Role.documentController,
      YorksV1Role.admin,
    ]) {
      final container = await createContainer(
        role: role,
        repository: _FakeProjectRepository(),
      );
      final controller = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
      );
      await controller.initialized;
      for (final stage in [
        YorksV1ProjectCreationStage.partiesAndAccess,
        YorksV1ProjectCreationStage.reviewAndCreate,
      ]) {
        await controller.save(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .copyWith(currentStage: stage),
        );
        await _pumpScreen(tester, container, size: const Size(1366, 1500));
        if (role == YorksV1Role.admin) {
          expect(
            find.textContaining(
              YorksV1ProjectStrings.automaticCreatorMembership.primary,
            ),
            findsNothing,
          );
        } else {
          final projectRole = role == YorksV1Role.siteEngineer
              ? YorksV1ProjectMembershipRole.siteEngineer
              : YorksV1ProjectMembershipRole.projectEngineer;
          if (stage == YorksV1ProjectCreationStage.partiesAndAccess) {
            expect(
              find.text(
                YorksV1ProjectStrings.automaticCreatorMembership.primary,
              ),
              findsOneWidget,
            );
            expect(
              find.text(
                YorksV1ProjectStrings.roleLabel(projectRole.wireValue).primary,
              ),
              findsWidgets,
            );
          } else {
            expect(
              find.text(
                '${YorksV1ProjectStrings.automaticCreatorMembership.primary} · ${YorksV1ProjectStrings.roleLabel(projectRole.wireValue).primary}',
              ),
              findsOneWidget,
            );
          }
        }
        if (stage == YorksV1ProjectCreationStage.reviewAndCreate) {
          expect(
            find.text(
              (role == YorksV1Role.siteEngineer || role == YorksV1Role.admin
                      ? YorksV1ProjectStrings.expectedDraftProject
                      : YorksV1ProjectStrings.expectedActiveProject)
                  .primary,
            ),
            findsOneWidget,
          );
        }
        expect(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .initialMembers,
          isEmpty,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'Arabic at 360px and 200 percent text gives the header full width',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      await container
          .read(languageProvider.notifier)
          .setLanguage(AppLanguage.arabic);
      await _pumpScreen(
        tester,
        container,
        size: const Size(360, 800),
        textScaler: const TextScaler.linear(2),
        textDirection: TextDirection.rtl,
      );
      final title = find.text(
        YorksV1ProjectSetupShellStrings.create.active(AppLanguage.arabic),
      );
      final save = find.text(
        YorksV1ProjectStrings.saveDraft.active(AppLanguage.arabic),
      );
      expect(
        tester.renderObject<RenderParagraph>(title).constraints.maxWidth,
        greaterThan(300),
      );
      expect(tester.getSize(title).height, lessThan(100));
      expect(
        tester.getRect(save).top,
        greaterThan(tester.getRect(title).bottom),
      );
      expect(Directionality.of(tester.element(title)), TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksV1ProjectCreateFlowScreen),
        matchesGoldenFile(
          'goldens/r35/project_create_details_arabic_360_200pct.png',
        ),
      );
      final controller = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
      );
      await controller.save(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .copyWith(
              currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
            ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        YorksV1ProjectStrings.back.active(AppLanguage.arabic),
        YorksV1ProjectStrings.createProject.active(AppLanguage.arabic),
      ]) {
        final text = find.text(label).last;
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in [
    YorksV1ProjectCreationStage.projectDetails,
    YorksV1ProjectCreationStage.partiesAndAccess,
    YorksV1ProjectCreationStage.buildings,
    YorksV1ProjectCreationStage.attachments,
  ]) {
    testWidgets('Yorks mobile project creation ${stage.name} — 390×844', (
      tester,
    ) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      if (stage != YorksV1ProjectCreationStage.projectDetails) {
        final notifier = container.read(
          yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
        );
        await notifier.save(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .copyWith(
                reference: 'YRA-MOBILE-001',
                name: 'Mobile project',
                currentStage: stage,
              ),
        );
      }
      await _pumpScreen(tester, container, size: const Size(390, 844));

      await expectLater(
        find.byType(YorksV1ProjectCreateFlowScreen),
        matchesGoldenFile(
          'goldens/mobile_batch1/project_create_${stage.name}_390.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Procurement receives a clear forbidden create screen', (
    tester,
  ) async {
    final container = await createContainer(
      role: YorksV1Role.procurement,
      repository: _FakeProjectRepository(),
    );
    await _pumpScreen(tester, container);

    expect(find.text(YorksV1ProjectStrings.noPermission.primary), findsWidgets);
    expect(
      find.text(YorksV1ProjectStrings.noPermissionDescription.primary),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('yorks-v1-project-reference')),
      findsNothing,
    );
  });

  testWidgets(
    'temporary access failure retains the editable local project draft',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        permissionState: const YorksV1CurrentPermissionSnapshotState(
          error: YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        ),
      );
      await _pumpScreen(tester, container);

      expect(
        find.text('Unable to verify access. Your work is safe.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('yorks-v1-project-reference')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-reference')),
        'YRA-RECOVER-001',
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .reference,
        'YRA-RECOVER-001',
      );
      expect(
        find.text(YorksV1ProjectStrings.noPermission.primary),
        findsNothing,
      );
    },
  );

  test('browser-dropped documents use the controlled picker validation', () {
    final selected = YorksV1SelectedDocument.checked(
      fileName: 'plans/issued-drawing.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(selected.fileName, 'issued-drawing.pdf');
    expect(selected.mimeType, 'application/pdf');
    expect(
      () => YorksV1SelectedDocument.checked(
        fileName: 'unsafe-script.exe',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<YorksV1DomainException>()),
    );
  });

  test(
    'controlled project attachments accept 20 MiB and reject larger files',
    () {
      final selected = YorksV1SelectedDocument.checked(
        fileName: 'issued-drawing.pdf',
        bytes: Uint8List(yorksV1MaxDocumentBytes),
      );

      expect(selected.bytes.lengthInBytes, yorksV1MaxDocumentBytes);
      expect(
        () => YorksV1SelectedDocument.checked(
          fileName: 'oversized-drawing.pdf',
          bytes: Uint8List(yorksV1MaxDocumentBytes + 1),
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
    },
  );

  testWidgets('attachments choose files directly without metadata fields', (
    tester,
  ) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
      documentFileService: _FakeDocumentFileService(),
    );
    final draftNotifier = container.read(
      yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
    );
    await draftNotifier.save(
      container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .copyWith(
            reference: 'YRA-ATTACH-001',
            name: 'Attachment project',
            currentStage: YorksV1ProjectCreationStage.attachments,
            buildings: const [
              YorksV1ProjectBuildingInput(code: 'B1', name: 'Building One'),
            ],
          ),
    );

    await _pumpScreen(tester, container);

    expect(
      find.byKey(const ValueKey('yorks-v1-attachment-file-name')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
    );
    await tester.pumpAndSettle();

    expect(find.text('site-plan.pdf'), findsOneWidget);
    expect(
      container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .attachments
          .single
          .sizeBytes,
      3,
    );
  });

  testWidgets(
    'same filename with different content keeps distinct attachment metadata',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        documentFileService: _FakeDocumentFileService(),
      );
      await container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                .copyWith(
                  reference: 'YRA-ATTACH-RECOVERY-001',
                  name: 'Attachment recovery project',
                  currentStage: YorksV1ProjectCreationStage.attachments,
                  buildings: const [
                    YorksV1ProjectBuildingInput(
                      code: 'B1',
                      name: 'Building One',
                    ),
                  ],
                  attachments: const [
                    YorksV1ProjectAttachmentInput(
                      fileName: 'site-plan.pdf',
                      mimeType: 'application/pdf',
                      sizeBytes: 1,
                    ),
                  ],
                ),
          );

      await _pumpScreen(tester, container);
      expect(
        find.textContaining(YorksV1ProjectStrings.fileReselect.primary),
        findsWidgets,
      );

      await tester.tap(
        find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
      );
      await tester.pumpAndSettle();

      final restored = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(restored.attachments, hasLength(2));
      expect(restored.attachments.first.sizeBytes, 1);
      expect(restored.attachments.last.sizeBytes, 3);
      expect(find.text('2 files'), findsOneWidget);
    },
  );

  testWidgets('R35 project attachments stage — 1366×768', (tester) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    await container
        .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .copyWith(
                reference: 'YRA-VISUAL-001',
                name: 'Visual evidence project',
                currentStage: YorksV1ProjectCreationStage.attachments,
                buildings: const [
                  YorksV1ProjectBuildingInput(code: 'B1', name: 'Building One'),
                ],
              ),
        );

    await _pumpScreen(tester, container, size: const Size(1366, 768));

    // The six full-shell desktop goldens live in the desktop interaction
    // suite. This retained case verifies the smaller desktop viewport.
    expect(
      find.byKey(const ValueKey('project-setup-desktop-shell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R35 project attachments stage — 360×800', (tester) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    await container
        .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .copyWith(
                reference: 'YRA-VISUAL-002',
                name: 'Mobile visual evidence project',
                currentStage: YorksV1ProjectCreationStage.attachments,
                buildings: const [
                  YorksV1ProjectBuildingInput(code: 'B1', name: 'Building One'),
                ],
              ),
        );

    await _pumpScreen(tester, container, size: const Size(360, 800));

    await expectLater(
      find.byType(YorksV1ProjectCreateFlowScreen),
      matchesGoldenFile('goldens/r35/project_create_attachments_mobile.png'),
    );
  });

  testWidgets('R35 project review stage includes the creation decision data', (
    tester,
  ) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    await container
        .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
              .copyWith(
                reference: 'YRA-VISUAL-003',
                name: 'Review evidence project',
                clientName: 'Yorks Client',
                jobOrContractReference: 'CON-1100C450',
                siteLocation: 'Dubai South',
                startDate: DateTime(2026, 8, 1),
                endDate: DateTime(2027, 2, 28),
                notes: 'Coordinate the common scope with the site team.',
                parties: const [
                  YorksV1ProjectPartyInput(
                    kind: YorksV1ProjectPartyKind.consultant,
                    name: 'Akins',
                  ),
                  YorksV1ProjectPartyInput(
                    kind: YorksV1ProjectPartyKind.mainContractor,
                    name: 'York Contracting',
                  ),
                  YorksV1ProjectPartyInput(
                    kind: YorksV1ProjectPartyKind.subcontractor,
                    name: 'MEP Specialist',
                  ),
                ],
                attachments: const [
                  YorksV1ProjectAttachmentInput(
                    fileName: 'approved-schedule.pdf',
                    mimeType: 'application/pdf',
                    sizeBytes: 1200,
                  ),
                ],
                currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                buildings: const [
                  YorksV1ProjectBuildingInput(code: 'B1', name: 'Building One'),
                ],
              ),
        );

    await _pumpScreen(tester, container, size: const Size(1366, 768));

    expect(find.text('CON-1100C450'), findsOneWidget);
    expect(find.text('Dubai South'), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(find.text('Dubai South')).textAlign,
      TextAlign.start,
    );
    expect(
      Directionality.of(tester.element(find.text('Dubai South'))),
      TextDirection.ltr,
    );
    expect(find.text('Yorks Client'), findsOneWidget);
    expect(find.text('Akins'), findsOneWidget);
    expect(find.text('York Contracting'), findsOneWidget);
    expect(find.text('MEP Specialist'), findsOneWidget);
    expect(find.text('approved-schedule.pdf'), findsOneWidget);
    expect(find.text('Building One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'starts a blank building and copies only after the explicit action',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final draftNotifier = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
      );
      await draftNotifier.save(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .copyWith(
              reference: 'YRA-BUILDING-001',
              name: 'Building editor project',
              currentStage: YorksV1ProjectCreationStage.buildings,
              buildings: const [
                YorksV1ProjectBuildingInput(
                  sourceScopeId: 'scope-building-1',
                  code: 'B01',
                  name: 'Tower One',
                  floorsOrLevels: ['GF', 'L1'],
                  hasFrpRoom: true,
                  deliveryAddress: 'North gate',
                ),
              ],
            ),
      );

      await _pumpScreen(tester, container);
      final editButton = find.text('Tower One');
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('yorks-v1-building-name')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Tower One',
      );

      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-building-name')),
        'Tower One Updated',
      );
      final apply = find.byKey(
        const ValueKey('yorks-v1-desktop-apply-building'),
      );
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final updated = container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .buildings
          .single;
      expect(updated.name, 'Tower One Updated');
      expect(updated.sourceScopeId, 'scope-building-1');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('yorks-v1-building-code')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('yorks-v1-building-delivery-address'),
                ),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('yorks-v1-desktop-building-frp')),
            )
            .value,
        isFalse,
      );
      await _buildingMenuAction(
        tester,
        updated,
        YorksV1ProjectStrings.addAnotherLikeThis.primary,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('yorks-v1-building-code')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'B02',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('yorks-v1-desktop-building-frp')),
            )
            .value,
        isTrue,
      );
      // Route teardown can occur before the duplication edit's debounce fires.
      // It must acknowledge that unfinished editor without publishing into a
      // Consumer element that has already been unmounted.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final retained = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(retained.rawEditorState['buildingCode'], 'B02');
      expect(retained.rawEditorState['buildingFrp'], isTrue);
      expect(retained.isAcknowledged, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1366, 768), const Size(360, 800)]) {
    testWidgets(
      'review validation survives return to invalid stage ${size.width}',
      (tester) async {
        final repository = _FakeProjectRepository();
        final container = await createContainer(
          role: YorksV1Role.siteEngineer,
          repository: repository,
        );
        final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
        final draft = container
            .read(provider)
            .copyWith(
              reference: 'VALIDATION-LOCAL-001',
              name: 'Preserved project',
              clientName: 'Synthetic client',
              startDate: DateTime(2026, 9, 17),
              endDate: DateTime(2026, 9, 16),
              currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
              buildings: const [
                YorksV1ProjectBuildingInput(code: 'B01', name: 'Building One'),
              ],
            );
        await container.read(provider.notifier).save(draft);
        await _pumpScreen(tester, container, size: size);
        final create = find.byKey(const ValueKey('yorks-v1-project-create'));
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(repository.receivedCreationInputs, isEmpty);
        expect(
          container.read(provider).currentStage,
          YorksV1ProjectCreationStage.projectDetails,
        );
        expect(container.read(provider).name, draft.name);
        expect(container.read(provider).endDate, draft.endDate);
        expect(
          find.text(YorksV1ProjectStrings.endDateAfterStart.primary),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('creates through the V1 command controller and retries safely', (
    tester,
  ) async {
    final repository = _FakeProjectRepository(failFirstCreate: true);
    final container = await createContainer(
      role: YorksV1Role.siteEngineer,
      repository: repository,
    );
    final draftNotifier = container.read(
      yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
    );
    final initialDraft = container
        .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
        .copyWith(
          reference: 'YRK-B2-001',
          name: 'Tower HVAC Works',
          clientName: 'Yorks Client',
          currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
          buildings: const [
            YorksV1ProjectBuildingInput(code: 'T01', name: 'Tower One'),
          ],
        );
    await draftNotifier.save(initialDraft);
    final originalIdempotencyKey = initialDraft.creationIdempotencyKey;
    YorksV1Project? createdProject;
    var createdCallbacks = 0;

    await _pumpScreen(
      tester,
      container,
      onProjectCreated: (project) {
        createdCallbacks++;
        createdProject = project;
      },
    );

    final createButton = find.byKey(const ValueKey('yorks-v1-project-create'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(repository.receivedCreationInputs, hasLength(1));
    expect(
      container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .creationIdempotencyKey,
      originalIdempotencyKey,
    );
    expect(createdProject, isNull);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(repository.receivedCreationInputs, hasLength(2));
    expect(
      repository.receivedCreationInputs
          .map((input) => input.idempotencyKey)
          .toSet(),
      {repository.receivedCreationInputs.first.idempotencyKey},
    );
    expect(createdProject?.reference, 'YRK-B2-001');
    await tester.pumpAndSettle();
    expect(createdCallbacks, 1);
    expect(createdProject?.state, YorksV1ProjectLifecycle.draft);
    expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
    expect(
      find.text(YorksV1ProjectStrings.projectCreated.primary),
      findsNothing,
    );
    final retiredProvider = yorksV1ProjectSetupCreationDraftProvider(
      _authUserId,
    );
    container.invalidate(retiredProvider);
    await container.read(retiredProvider.notifier).initialized;
    expect(container.read(retiredProvider).reference, isEmpty);
  });

  testWidgets(
    'never renders a saved raw team UUID and blocks creation until a stale member is resolved',
    (tester) async {
      const staleAuthUserId = '00000000-0000-4000-8000-000000000099';
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: repository,
        teamDirectoryRepository: _FakeTeamDirectoryRepository(
          members: const [
            YorksV1ProjectTeamDirectoryMember(
              authUserId: 'auth-available-project-engineer',
              displayName: 'Amina Project Engineer',
              eligibleRole: YorksV1Role.projectEngineer,
            ),
          ],
        ),
      );
      final draftNotifier = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
      );
      await draftNotifier.save(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .copyWith(
              reference: 'YRK-STALE-001',
              name: 'Stale team member project',
              currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
              initialMembers: const [
                YorksV1InitialProjectMemberInput(
                  authUserId: staleAuthUserId,
                  projectRole: YorksV1ProjectMembershipRole.projectEngineer,
                ),
              ],
              buildings: const [
                YorksV1ProjectBuildingInput(code: 'B1', name: 'Building One'),
              ],
            ),
      );

      await _pumpScreen(tester, container);

      expect(find.text(staleAuthUserId), findsNothing);
      expect(
        find.textContaining(YorksV1ProjectStrings.profileId.primary),
        findsWidgets,
      );

      final createButton = find.byKey(
        const ValueKey('yorks-v1-project-create'),
      );
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(repository.receivedCreationInputs, isEmpty);
      expect(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .currentStage,
        YorksV1ProjectCreationStage.partiesAndAccess,
      );
      expect(find.text(staleAuthUserId), findsNothing);
      expect(
        find.text(YorksV1ProjectStrings.teamMemberNoLongerAvailable.primary),
        findsWidgets,
      );
    },
  );

  for (final size in [const Size(1536, 1024), const Size(360, 800)]) {
    testWidgets(
      '${size.width} categories resume and local Preview uses each same-name file exact bytes',
      (tester) async {
        final language = size.width == 360
            ? AppLanguage.arabic
            : AppLanguage.english;
        final images = (await tester.runAsync(
          () => Future.wait([
            File('assets/logo.png').readAsBytes(),
            File('assets/branding/yorks_emblem_mobile.png').readAsBytes(),
          ]),
        ))!;
        final selected = [
          for (final bytes in images)
            YorksV1SelectedDocument(
              fileName: 'same-name.png',
              mimeType: 'image/png',
              bytes: bytes,
            ),
          YorksV1SelectedDocument(
            fileName: 'schedule.docx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            bytes: Uint8List.fromList([80, 75, 3, 4, 11, 12]),
          ),
        ];
        final picker = _PreviewDocumentFileService(selected);
        final repository = _FakeProjectRepository();
        final container = await createContainer(
          role: YorksV1Role.projectEngineer,
          repository: repository,
          documentFileService: picker,
        );
        container.read(languageProvider.notifier).setLanguage(language);
        final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
        final writer = container.read(provider.notifier);
        await writer.initialized;
        await writer.save(
          container
              .read(provider)
              .copyWith(
                currentStage: YorksV1ProjectCreationStage.attachments,
                reference: 'LOCAL-PREVIEW',
                name: 'Exact local file preview',
              ),
        );
        await _pumpScreen(
          tester,
          container,
          size: size,
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        final prefix = size.width >= 1100 ? 'desktop' : 'mobile';
        Future<void> tapVisible(Finder finder) async {
          await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tapVisible(
          find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
        );
        final first = container.read(provider).attachments.single;
        expect(first.category, YorksV1ProjectAttachmentCategory.general);
        final firstCategory = find.byKey(
          ValueKey('yorks-v1-$prefix-file-category-${first.localId}'),
        );
        final categoryInput = find.descendant(
          of: firstCategory,
          matching: find.byType(DropdownButtonFormField<String>),
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(categoryInput)
              .initialValue,
          'general',
        );
        await tapVisible(firstCategory);
        await tester.tap(
          find
              .text(
                YorksV1ProjectSetupDesktopStrings.categoryDrawing.active(
                  language,
                ),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await writer.flush();
        expect(
          container.read(provider).attachments.single.category,
          YorksV1ProjectAttachmentCategory.drawing,
        );
        for (var index = 1; index < selected.length; index++) {
          await tapVisible(
            find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
          );
        }
        final files = container.read(provider).attachments;
        expect(files, hasLength(3));
        expect(files[0].fileName, files[1].fileName);
        expect(files[0].localId, isNot(files[1].localId));
        expect(files[0].contentHash, isNot(files[1].contentHash));
        expect(files[1].category, YorksV1ProjectAttachmentCategory.general);
        expect(find.byType(Checkbox), findsNothing);
        for (var index = 0; index < files.length; index++) {
          final preview = find.byKey(
            ValueKey('yorks-v1-$prefix-file-preview-${files[index].localId}'),
          );
          await tapVisible(preview);
          final dialog = find.byType(YorksV1ProjectSetupAttachmentPreview);
          expect(dialog, findsOneWidget);
          final rendered = tester.widget<YorksV1ProjectSetupAttachmentPreview>(
            dialog,
          );
          expect(rendered.file.bytes, orderedEquals(selected[index].bytes));
          expect(
            sha256.convert(rendered.file.bytes).toString(),
            files[index].contentHash,
          );
          if (index < 2) {
            final image = tester.widget<Image>(
              find.byKey(const ValueKey('yorks-v1-local-file-image-preview')),
            );
            expect(
              (image.image as MemoryImage).bytes,
              orderedEquals(selected[index].bytes),
            );
          } else {
            expect(
              find.byKey(const ValueKey('yorks-v1-local-file-image-preview')),
              findsNothing,
            );
            expect(
              find.text(
                YorksV1ProjectSetupDesktopStrings.previewUnsupported.active(
                  language,
                ),
              ),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('yorks-v1-local-file-save')),
            );
            await tester.pumpAndSettle();
            expect(
              picker.saved.single.bytes,
              orderedEquals(selected[index].bytes),
            );
            expect(picker.saved.single.mimeType, selected[index].mimeType);
          }
          await tester.tap(
            find.byTooltip(
              YorksV1ProjectSetupDesktopStrings.closePreview.active(language),
            ),
          );
          await tester.pumpAndSettle();
        }
        await tapVisible(
          find.byKey(
            ValueKey('yorks-v1-$prefix-file-preview-${files.first.localId}'),
          ),
        );
        final openPreview = tester.widget<YorksV1ProjectSetupAttachmentPreview>(
          find.byType(YorksV1ProjectSetupAttachmentPreview),
        );
        final staleSave = openPreview.onSave!;
        expect(
          find.byKey(const ValueKey('yorks-v1-local-file-image-preview')),
          findsOneWidget,
        );
        container.read(_testOwnerProvider.notifier).state =
            'revoked-preview-owner';
        await tester.pumpAndSettle();
        expect(find.byType(YorksV1ProjectSetupAttachmentPreview), findsNothing);
        expect(
          find.byKey(const ValueKey('yorks-v1-local-file-image-preview')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('yorks-v1-local-file-save')),
          findsNothing,
        );
        expect(
          find.text(YorksV1ProjectStrings.noPermission.active(language)),
          findsWidgets,
        );
        staleSave();
        await tester.pumpAndSettle();
        expect(
          picker.saved,
          hasLength(1),
          reason:
              'An already captured callback must not save after revocation.',
        );
        await tester.tap(
          find.text(
            YorksV1ProjectSetupDesktopStrings.closePreview.active(language),
          ),
        );
        await tester.pumpAndSettle();
        container.read(_testOwnerProvider.notifier).state = _authUserId;
        await tester.pumpAndSettle();
        await writer.flush();
        final draftId = container.read(provider).draftId;
        final acknowledgedFiles = container
            .read(provider)
            .attachments
            .map((file) => file.toDraftJson())
            .toList();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _pumpScreen(
          tester,
          container,
          size: size,
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(container.read(provider).draftId, draftId);
        expect(
          container
              .read(provider)
              .attachments
              .map((file) => file.toDraftJson())
              .toList(),
          acknowledgedFiles,
        );
        final restoredCategory = tester.widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: firstCategory,
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        );
        expect(restoredCategory.initialValue, 'drawing');
        final missing = find.byKey(
          ValueKey('yorks-v1-$prefix-file-preview-${first.localId}'),
        );
        expect(
          find.descendant(
            of: missing,
            matching: find.text(
              YorksV1ProjectStrings.fileReselect.active(language),
            ),
          ),
          findsOneWidget,
        );
        await tapVisible(missing);
        expect(picker.selections, 4);
        expect(find.byType(YorksV1ProjectSetupAttachmentPreview), findsNothing);
        expect(
          find.byKey(const ValueKey('yorks-v1-local-file-image-preview')),
          findsNothing,
        );
        expect(repository.receivedCreationInputs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      '${size.width} navigates directly to the authorized project after confirmed creation',
      (tester) async {
        final repository = _FakeProjectRepository();
        final container = await createContainer(
          role: YorksV1Role.siteEngineer,
          repository: repository,
        );
        await container
            .read(
              yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier,
            )
            .save(
              container
                  .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                  .copyWith(
                    reference: 'YRK-NAV-001',
                    name: 'Project route handoff',
                    currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                    buildings: const [
                      YorksV1ProjectBuildingInput(
                        code: 'B1',
                        name: 'Building One',
                      ),
                    ],
                  ),
            );
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => YorksV1ProjectCreateFlowScreen(
                resumeDraftId: container
                    .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                    .draftId,
              ),
            ),
            GoRoute(
              path: '/yorks/projects/:projectId',
              builder: (_, state) => Scaffold(
                body: Text('Opened ${state.pathParameters['projectId']}'),
              ),
            ),
          ],
        );
        await tester.binding.setSurfaceSize(size);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final createButton = find.byKey(
          const ValueKey('yorks-v1-project-create'),
        );
        await tester.ensureVisible(createButton);
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(repository.receivedCreationInputs, hasLength(1));
        expect(find.text('Opened project-b2-001'), findsOneWidget);
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
        expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
        await tester.pumpAndSettle();
        expect(repository.receivedCreationInputs, hasLength(1));
        expect(
          find.text(YorksV1ProjectStrings.projectCreated.primary),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'phone confirmed creation returns to the portfolio without project-view authority',
    (tester) async {
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: repository,
        permissionState: yorksV1TrustedFeaturePermissionState(
          role: YorksV1Role.siteEngineer,
          capabilities: const [YorksV1CapabilityKeys.projectsCreate],
        ),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'YRA-PHONE-DENIED-ACTIONS',
                  name: 'Known Draft with restricted next actions',
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                  visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                  buildings: const [
                    YorksV1ProjectBuildingInput(name: 'Main building'),
                  ],
                ),
          );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => YorksV1ProjectCreateFlowScreen(
              resumeDraftId: container
                  .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                  .draftId,
            ),
          ),
          GoRoute(
            path: '/yorks/projects',
            builder: (_, _) => const Scaffold(body: Text('Projects portfolio')),
          ),
          GoRoute(
            path: '/yorks/projects/:projectId',
            builder: (_, _) =>
                const Scaffold(body: Text('Unauthorized project destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('yorks-v1-project-create'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Projects portfolio'), findsOneWidget);
      expect(find.text('Unauthorized project destination'), findsNothing);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(repository.receivedCreationInputs, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'phone review wraps full names and keeps activation readiness separate from creation',
    (tester) async {
      const projectName =
          'Nexus Power Transmission and Refrigeration Installation Project Phase One';
      const engineerName = 'Abdul Raheem Mohammed Abdullah Al Mansouri';
      const buildingName =
          'Main Control and Refrigeration Equipment Services Building';
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: repository,
        teamDirectoryRepository: _FakeTeamDirectoryRepository(
          members: const [
            YorksV1ProjectTeamDirectoryMember(
              authUserId: 'phone-review-engineer',
              displayName: engineerName,
              eligibleRole: YorksV1Role.projectEngineer,
            ),
          ],
        ),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'YRA-PHONE-FULL-NAMES',
                  name: projectName,
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                  visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                  initialMembers: const [
                    YorksV1InitialProjectMemberInput(
                      authUserId: 'phone-review-engineer',
                      projectRole: YorksV1ProjectMembershipRole.projectEngineer,
                    ),
                  ],
                  buildings: const [
                    YorksV1ProjectBuildingInput(
                      localRowId: 'phone-review-building',
                      code: 'B01',
                      name: buildingName,
                      hasFrpRoom: true,
                      flags: {'retained_flag': 'keep'},
                    ),
                  ],
                ),
          );
      await _pumpScreen(tester, container, size: const Size(390, 844));
      for (final name in [projectName, engineerName, buildingName]) {
        final matches = find.textContaining(name);
        expect(matches, findsWidgets);
        final paragraphs = matches.evaluate().map(
          (element) => element.renderObject! as RenderParagraph,
        );
        expect(
          paragraphs.any((paragraph) => !paragraph.didExceedMaxLines),
          isTrue,
          reason: 'The complete name must remain readable: $name',
        );
      }
      expect(
        find.text(YorksV1ProjectStrings.expectedActiveProject.primary),
        findsOneWidget,
      );
      final submit = find.byKey(const ValueKey('yorks-v1-project-create'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await container
          .read(provider.notifier)
          .save(container.read(provider).copyWith(initialMembers: const []));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.expectedDraftProject.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ProjectStrings.expectedActiveProject.primary),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      final building = container.read(provider).buildings.single;
      expect(building.localRowId, 'phone-review-building');
      expect(building.name, buildingName);
      expect(building.hasFrpRoom, isTrue);
      expect(building.flags['retained_flag'], 'keep');
      expect(repository.receivedCreationInputs, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone footer requires applying the building editor and preserves stable rows',
    (tester) async {
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: repository,
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'YRA-PHONE-APPLY',
                  name: 'Phone building application',
                  currentStage: YorksV1ProjectCreationStage.buildings,
                  visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                  buildings: const [
                    YorksV1ProjectBuildingInput(
                      localRowId: 'preserved-phone-building',
                      code: 'B01',
                      name: 'Existing local building',
                      flags: {'retained_flag': 'keep'},
                    ),
                  ],
                ),
          );
      await _pumpScreen(tester, container, size: const Size(390, 844));
      final add = find.byKey(const ValueKey('yorks-v1-mobile-add-building'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('yorks-v1-building-name'));
      await tester.ensureVisible(name);
      await tester.enterText(
        name,
        'New building with its own reviewed FRP room',
      );
      final frp = find.byKey(const ValueKey('yorks-v1-mobile-building-frp'));
      await tester.ensureVisible(frp);
      await tester.tap(frp);
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('yorks-v1-project-continue'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      expect(container.read(provider).buildings, hasLength(1));
      final apply = find.byKey(
        const ValueKey('yorks-v1-mobile-apply-building'),
      );
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      final buildings = container.read(provider).buildings;
      expect(buildings, hasLength(2));
      expect(buildings.first.localRowId, 'preserved-phone-building');
      expect(buildings.first.code, 'B01');
      expect(buildings.first.name, 'Existing local building');
      expect(buildings.first.hasFrpRoom, isFalse);
      expect(buildings.first.flags['retained_flag'], 'keep');
      expect(buildings.last.localRowId, isNotEmpty);
      expect(buildings.last.localRowId, isNot(buildings.first.localRowId));
      expect(buildings.last.hasFrpRoom, isTrue);
      expect(
        buildings.last.name,
        'New building with its own reviewed FRP room',
      );
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        container.read(provider).currentStage,
        YorksV1ProjectCreationStage.attachments,
      );
      expect(
        container
            .read(provider)
            .buildings
            .map((building) => building.localRowId),
        buildings.map((building) => building.localRowId),
      );
      expect(repository.receivedCreationInputs, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone Resume opens the known project and preserves its original file recovery',
    (tester) async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final hash = sha256.convert(bytes).toString();
      final picker = _QueuedDocumentFileService([
        Uint8List.fromList([3, 2, 1]),
        bytes,
      ]);
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: repository,
        documentFileService: picker,
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'YRA-PHONE-RECOVERY',
                  name: 'Known project with one original pending file',
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                  visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                  buildings: const [
                    YorksV1ProjectBuildingInput(name: 'Main building'),
                  ],
                  attachments: [
                    YorksV1ProjectAttachmentInput(
                      localId: 'phone-file',
                      fileName: 'site-plan.pdf',
                      mimeType: 'application/pdf',
                      sizeBytes: bytes.length,
                      contentHash: hash,
                    ),
                  ],
                  rawEditorState: {
                    'reviewedOperationalFiles': ['phone-file:$hash'],
                  },
                ),
          );
      final draft = container.read(provider);
      final scope = (
        ownerAuthUserId: _authUserId,
        draftId: draft.draftId,
        projectId: null as String?,
      );
      final coordinator = container.read(
        yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
      );
      await coordinator.prepareCreate(
        draft.toCreationInput(),
        files: [
          YorksV1ProjectSetupFile(
            localId: 'phone-file',
            idempotencyKey: 'phone-file-intent',
            fileName: 'site-plan.pdf',
            mimeType: 'application/pdf',
            sizeBytes: bytes.length,
            contentHash: hash,
            classification: YorksV1DocumentClassification.operational,
          ),
        ],
      );
      await coordinator.submitCore();
      final original = coordinator.currentState.operation!;
      final originalDraftId = draft.draftId;
      final storageKey = container.read(provider.notifier).storageKey;
      final preferences = container.read(sharedPreferencesProvider);
      final journalKey = '$storageKey:journal:$originalDraftId';
      final originalJournal = preferences.getString(journalKey)!;
      final opened = <YorksV1Project>[];
      await _pumpScreen(
        tester,
        container,
        size: const Size(390, 844),
        onProjectCreated: opened.add,
      );
      final fresh = container.read(provider);
      expect(fresh.draftId, isNot(originalDraftId));
      expect(fresh.creationIdempotencyKey, isNot(draft.creationIdempotencyKey));
      expect(fresh.reference, isEmpty);
      expect(fresh.name, isEmpty);
      expect(fresh.attachments, isEmpty);
      expect(fresh.currentStage, YorksV1ProjectCreationStage.projectDetails);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(opened, hasLength(1));
      expect(opened.single.id, original.project!.id);
      expect(picker.selections, 0);
      expect(repository.receivedCreationInputs, hasLength(1));
      expect(preferences.getString(journalKey), originalJournal);
      expect(original.filesPending, isTrue);
      expect(original.cleanupComplete, isFalse);
      expect(
        preferences.getString('$storageKey:retired:$originalDraftId'),
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      container.invalidate(yorksV1ProjectSetupCoordinatorProvider(scope));
      await _pumpScreen(
        tester,
        container,
        size: const Size(390, 844),
        onProjectCreated: opened.add,
      );
      expect(container.read(provider).draftId, fresh.draftId);
      expect(container.read(provider).reference, isEmpty);
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      expect(preferences.getString(journalKey), originalJournal);
      expect(repository.receivedCreationInputs, hasLength(1));
      expect(opened, hasLength(1));
      expect(opened.single.id, original.project!.id);
      expect(picker.selections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uses a safe display label when a directory name equals its UUID',
    (tester) async {
      const fallbackAuthUserId = '00000000-0000-4000-8000-000000000077';
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        teamDirectoryRepository: _FakeTeamDirectoryRepository(
          members: const [
            YorksV1ProjectTeamDirectoryMember(
              authUserId: fallbackAuthUserId,
              displayName: fallbackAuthUserId,
              eligibleRole: YorksV1Role.projectEngineer,
            ),
            YorksV1ProjectTeamDirectoryMember(
              authUserId: 'auth-named-project-engineer',
              displayName: 'Amina Project Engineer',
              eligibleRole: YorksV1Role.projectEngineer,
            ),
          ],
        ),
      );
      await container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text(fallbackAuthUserId), findsNothing);
      expect(
        find.textContaining(YorksV1ProjectStrings.profileId.primary),
        findsWidgets,
      );
      expect(find.text('Amina Project Engineer'), findsOneWidget);
    },
  );

  testWidgets(
    'never renders an email-like directory label from typed picker state',
    (tester) async {
      const emailLikeDisplayName = 'Amina <amina@example.test>';
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        teamDirectoryRepository: _FakeTeamDirectoryRepository(
          members: const [
            YorksV1ProjectTeamDirectoryMember(
              authUserId: '00000000-0000-4000-8000-000000000043',
              displayName: emailLikeDisplayName,
              eligibleRole: YorksV1Role.projectEngineer,
            ),
          ],
        ),
      );
      await container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text(emailLikeDisplayName), findsNothing);
      expect(find.textContaining('amina@example.test'), findsNothing);
      expect(
        find.textContaining(YorksV1ProjectStrings.profileId.primary),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'a Site Engineer can nominate one base Project Engineer and no Site Engineer',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: _FakeProjectRepository(),
        teamDirectoryRepository: _FakeTeamDirectoryRepository(
          members: const [
            YorksV1ProjectTeamDirectoryMember(
              authUserId: 'auth-project-engineer',
              displayName: 'Amina Project Engineer',
              eligibleRole: YorksV1Role.projectEngineer,
            ),
            YorksV1ProjectTeamDirectoryMember(
              authUserId: 'auth-site-engineer',
              displayName: 'Bilal Site Engineer',
              eligibleRole: YorksV1Role.siteEngineer,
            ),
          ],
        ),
      );
      await container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text('Amina Project Engineer'), findsOneWidget);
      expect(find.text('Bilal Site Engineer'), findsNothing);
      final candidate = find.byKey(
        const ValueKey('yorks-v1-desktop-directory-add-auth-project-engineer'),
      );
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();

      final initialMembers = container
          .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
          .initialMembers;
      expect(initialMembers, hasLength(1));
      expect(initialMembers.single.authUserId, 'auth-project-engineer');
      expect(
        initialMembers.single.projectRole,
        YorksV1ProjectMembershipRole.projectEngineer,
      );
      expect(
        find.byKey(
          const ValueKey('yorks-v1-project-team-picker-siteEngineer-1'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'partial typed dates remain recoverable and cannot continue silently',
    (tester) async {
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: repository,
      );
      await _pumpScreen(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-reference')),
        'PARTIAL-DATE',
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Preserved proposal',
      );
      final date = find.byKey(
        ValueKey('yorks-v1-project-date-${YorksV1ProjectStrings.startDate.en}'),
      );
      await tester.ensureVisible(date);
      await tester.enterText(date, '12/10/');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final draft = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(draft.startDate, isNull);
      expect(draft.rawEditorState['dateStartText'], '12/10/');
      expect(draft.isAcknowledged, isTrue);
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-continue')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .currentStage,
        YorksV1ProjectCreationStage.projectDetails,
      );
      expect(repository.receivedCreationInputs, isEmpty);
      expect(
        find.text(YorksV1ProjectStrings.invalidTypedDate.primary),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await _pumpScreen(tester, container);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: date, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '12/10/',
      );
    },
  );

  testWidgets('unfinished building and party text survives stage navigation', (
    tester,
  ) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
    await container
        .read(provider.notifier)
        .save(
          container
              .read(provider)
              .copyWith(
                reference: 'RAW-EDITOR',
                name: 'Raw editor project',
                currentStage: YorksV1ProjectCreationStage.buildings,
                visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                buildings: const [
                  YorksV1ProjectBuildingInput(name: 'Existing local building'),
                ],
              ),
        );
    await _pumpScreen(tester, container);
    await tester.enterText(
      find.byKey(const ValueKey('yorks-v1-building-name')),
      'Unapplied second building',
    );
    await tester.enterText(
      find.byKey(const ValueKey('yorks-v1-building-floors')),
      'B1, Ground, Roof,',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await _selectStage(tester, YorksV1ProjectCreationStage.projectDetails);
    await _selectStage(tester, YorksV1ProjectCreationStage.buildings);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('yorks-v1-building-name')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Unapplied second building',
    );
    expect(
      container.read(provider).rawEditorState['buildingFloors'],
      'B1, Ground, Roof,',
    );
  });

  testWidgets(
    'removing a new building is reversible with its stable identity',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'UNDO',
                  name: 'Undo project',
                  currentStage: YorksV1ProjectCreationStage.buildings,
                  buildings: const [
                    YorksV1ProjectBuildingInput(
                      name: 'Local building',
                      hasFrpRoom: true,
                      floorsOrLevels: ['B1', 'Roof'],
                    ),
                  ],
                ),
          );
      final original = container.read(provider).buildings.single.toDraftJson();
      await _pumpScreen(tester, container);
      await _buildingMenuAction(
        tester,
        container.read(provider).buildings.single,
        YorksV1ProjectStrings.remove.primary,
      );
      expect(container.read(provider).buildings, isEmpty);
      final undo = find.text(YorksV1ProjectStrings.undoBuildingChange.primary);
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(container.read(provider).buildings.single.toDraftJson(), original);
    },
  );

  testWidgets(
    'optional empty details continue and saved status is explicitly local',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      await _pumpScreen(tester, container, size: const Size(360, 800));
      expect(
        find.text(YorksV1ProjectStrings.notSavedYet.primary),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-reference')),
        'ONLY-REQUIRED',
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Required fields only',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectSetupShellStrings.saved.primary),
        findsOneWidget,
      );
      expect(
        container
            .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
            .isAcknowledged,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-continue')));
      await tester.pumpAndSettle();
      final draft = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(draft.currentStage, YorksV1ProjectCreationStage.partiesAndAccess);
      expect(draft.startDate, isNull);
      expect(draft.clientName, isNull);
    },
  );

  testWidgets(
    'restored uncertain command shows original values and explicit status recovery',
    (tester) async {
      final repository = _FakeProjectRepository(failFirstCreate: true);
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: repository,
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'ORIGINAL-INTENT',
                  name: 'Original reviewed project',
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                  buildings: const [
                    YorksV1ProjectBuildingInput(name: 'Original building'),
                  ],
                ),
          );
      final draft = container.read(provider);
      final scope = (
        ownerAuthUserId: _authUserId,
        draftId: draft.draftId,
        projectId: null as String?,
      );
      final coordinator = container.read(
        yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
      );
      await coordinator.prepareCreate(draft.toCreationInput());
      await expectLater(
        coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'LOCAL-AMENDMENT',
                  name: 'Unsent local proposal',
                ),
          );
      YorksV1Project? saved;
      await _pumpScreen(
        tester,
        container,
        onProjectCreated: (project) => saved = project,
      );
      expect(
        find.byKey(const ValueKey('yorks-v1-project-operation-outcome')),
        findsOneWidget,
      );
      expect(find.textContaining('ORIGINAL-INTENT'), findsWidgets);
      expect(find.text('Unsent local proposal'), findsNothing);
      expect(
        find.text(YorksV1ProjectStrings.checkSavedStatus.primary),
        findsWidgets,
      );
      expect(
        find.text(YorksV1ProjectStrings.createProject.primary),
        findsNothing,
      );
      expect(saved, isNull);
      expect(container.read(provider).draftId, draft.draftId);
      expect(repository.receivedCreationInputs, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-create')));
      await tester.pumpAndSettle();
      expect(repository.receivedCreationInputs, hasLength(2));
      expect(
        repository.receivedCreationInputs.last.reference,
        'ORIGINAL-INTENT',
      );
      expect(
        repository.receivedCreationInputs.last.idempotencyKey,
        repository.receivedCreationInputs.first.idempotencyKey,
      );
      expect(saved!.name, 'Original reviewed project');
      expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      await tester.pumpAndSettle();
      expect(repository.receivedCreationInputs, hasLength(2));
    },
  );

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      '${size.width} optional file category preserves operational pending recovery after core navigation',
      (tester) async {
        final repository = _FakeProjectRepository();
        final container = await createContainer(
          role: YorksV1Role.projectEngineer,
          repository: repository,
        );
        final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
        await container.read(provider.notifier).initialized;
        await container
            .read(provider.notifier)
            .save(
              container
                  .read(provider)
                  .copyWith(
                    reference: 'YRA-FILES-PENDING',
                    name: 'Files pending project',
                    currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                    visitedStages: YorksV1ProjectCreationStage.values.toSet(),
                    buildings: const [
                      YorksV1ProjectBuildingInput(name: 'Main building'),
                    ],
                    attachments: const [
                      YorksV1ProjectAttachmentInput(
                        localId: 'pending-file',
                        fileName: 'site-plan.pdf',
                        mimeType: 'application/pdf',
                        sizeBytes: 3,
                        categoryKey: 'drawing',
                      ),
                    ],
                  ),
            );
        final originalDraft = container.read(provider);
        final originalDraftId = originalDraft.draftId;
        final storageKey = container.read(provider.notifier).storageKey;
        YorksV1Project? created;
        await _pumpScreen(
          tester,
          container,
          onProjectCreated: (value) => created = value,
          size: size,
        );
        final submit = find.byKey(const ValueKey('yorks-v1-project-create'));
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(repository.receivedCreationInputs, isEmpty);
        final editAttachments = find.bySemanticsLabel(
          YorksV1ProjectStrings.editAttachments.primary,
        );
        await tester.ensureVisible(editAttachments);
        await tester.tap(editAttachments);
        await tester.pumpAndSettle();
        expect(
          container.read(provider).currentStage,
          YorksV1ProjectCreationStage.attachments,
        );
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(YorksV1ProjectSetupAttachmentPreview), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('yorks-v1-project-continue')),
        );
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.receivedCreationInputs, hasLength(1));
        expect(
          repository
              .receivedCreationInputs
              .single
              .attachments
              .single
              .categoryKey,
          isNull,
        );
        expect(
          repository.receivedCreationInputs.single.attachments.single
              .toRpcJson(),
          {
            'file_name': 'site-plan.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 3,
          },
        );
        expect(created?.reference, 'YRA-FILES-PENDING');
        expect(created?.state, YorksV1ProjectLifecycle.active);
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
        final nextDraft = container.read(provider);
        expect(nextDraft.draftId, isNot(originalDraftId));
        expect(nextDraft.reference, isEmpty);
        expect(nextDraft.attachments, isEmpty);
        final preferences = container.read(sharedPreferencesProvider);
        final active =
            jsonDecode(preferences.getString(storageKey)!)
                as Map<String, dynamic>;
        expect(active['retired'], isFalse);
        expect(
          YorksV1ProjectCreationDraft.fromJson(
            Map<String, dynamic>.from(active['draft'] as Map),
          ).draftId,
          nextDraft.draftId,
        );
        final retired =
            jsonDecode(
                  preferences.getString(
                    '$storageKey:retired:$originalDraftId',
                  )!,
                )
                as Map<String, dynamic>;
        expect(retired['retired'], isTrue);
        expect(retired['resultProjectId'], created!.id);
        final retiredDraft = YorksV1ProjectCreationDraft.fromJson(
          Map<String, dynamic>.from(retired['draft'] as Map),
        );
        expect(retiredDraft.draftId, originalDraftId);
        expect(retiredDraft.attachments.single.localId, 'pending-file');
        final journalKey = '$storageKey:journal:$originalDraftId';
        final journalJson = preferences.getString(journalKey)!;
        final persistedOperation = YorksV1ProjectSetupOperation.fromJson(
          Map<String, dynamic>.from(jsonDecode(journalJson) as Map),
        );
        expect(persistedOperation.coreSucceeded, isTrue);
        expect(persistedOperation.filesPending, isTrue);
        expect(persistedOperation.cleanupComplete, isFalse);
        expect(persistedOperation.files.single.localId, 'pending-file');
        expect(persistedOperation.files.single.categoryKey, 'drawing');
        expect(
          persistedOperation.files.single.classification,
          YorksV1DocumentClassification.operational,
        );
        expect(
          persistedOperation.files.single.status,
          YorksV1ProjectSetupFileStatus.needsReselect,
        );
        expect(
          persistedOperation.core.idempotencyKey,
          repository.receivedCreationInputs.single.idempotencyKey,
        );
        expect(persistedOperation.core.project!.id, created!.id);
        await tester.pumpAndSettle();
        expect(repository.receivedCreationInputs, hasLength(1));
        expect(preferences.getString(journalKey), journalJson);
      },
    );
  }

  testWidgets('owner switch clears the previous owner building undo buffer', (
    tester,
  ) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
    await container
        .read(provider.notifier)
        .save(
          container
              .read(provider)
              .copyWith(
                reference: 'OWNER-A',
                name: 'Private project',
                currentStage: YorksV1ProjectCreationStage.buildings,
                buildings: const [
                  YorksV1ProjectBuildingInput(
                    name: 'Private building',
                    deliveryAddress: 'Private address',
                  ),
                ],
              ),
        );
    await _pumpScreen(tester, container);
    await _buildingMenuAction(
      tester,
      container.read(provider).buildings.single,
      YorksV1ProjectStrings.remove.primary,
    );
    expect(
      find.text(YorksV1ProjectStrings.undoBuildingChange.primary),
      findsOneWidget,
    );
    container.read(_testOwnerProvider.notifier).state = 'another-owner';
    await tester.pumpAndSettle();
    final otherProvider = yorksV1ProjectSetupCreationDraftProvider(
      'another-owner',
    );
    await container
        .read(otherProvider.notifier)
        .save(
          container
              .read(otherProvider)
              .copyWith(currentStage: YorksV1ProjectCreationStage.buildings),
        );
    await tester.pumpAndSettle();
    expect(
      find.text(YorksV1ProjectStrings.undoBuildingChange.primary),
      findsNothing,
    );
    expect(find.textContaining('Private building'), findsNothing);
    expect(container.read(otherProvider).buildings, isEmpty);
  });

  testWidgets(
    'an in-flight command never retires or navigates the next owner draft',
    (tester) async {
      final delay = Completer<void>();
      final repository = _FakeProjectRepository(createDelay: delay);
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: repository,
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container.read(provider.notifier).initialized;
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'OWNER-A',
                  name: 'Owner A proposal',
                  currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
                  buildings: const [
                    YorksV1ProjectBuildingInput(name: 'Owner A building'),
                  ],
                ),
          );
      YorksV1Project? navigated;
      await _pumpScreen(
        tester,
        container,
        onProjectCreated: (value) => navigated = value,
      );
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.receivedCreationInputs, hasLength(1));
      container.read(_testOwnerProvider.notifier).state = 'owner-b';
      await tester.pumpAndSettle();
      final other = yorksV1ProjectSetupCreationDraftProvider('owner-b');
      await container.read(other.notifier).initialized;
      await container
          .read(other.notifier)
          .save(
            container
                .read(other)
                .copyWith(reference: 'OWNER-B', name: 'Owner B proposal'),
          );
      delay.complete();
      await tester.pumpAndSettle();
      expect(navigated, isNull);
      expect(container.read(other).reference, 'OWNER-B');
      expect(container.read(other).name, 'Owner B proposal');
    },
  );

  testWidgets(
    'lifecycle refresh stays fenced and requires returning to selected Resume',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      final controller = container.read(provider.notifier);
      await controller.initialized;
      await controller.save(
        container
            .read(provider)
            .copyWith(reference: 'OWNER-A', name: 'Saved proposal'),
      );
      await _pumpScreen(tester, container);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      final preferences = container.read(sharedPreferencesProvider);
      final record =
          jsonDecode(preferences.getString(controller.storageKey)!)
              as Map<String, dynamic>;
      record['ownerWriterId'] = 'another-tab-writer';
      await preferences.setString(controller.storageKey, jsonEncode(record));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        container.read(provider).storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      expect(
        find.text(YorksV1ProjectStrings.takeOverDraft.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectStrings.draftResumedElsewhere.primary),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'step arrows and Home End move focus before Enter activates the step',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container.read(provider.notifier).initialized;
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  visitedStages: {
                    YorksV1ProjectCreationStage.projectDetails,
                    YorksV1ProjectCreationStage.partiesAndAccess,
                    YorksV1ProjectCreationStage.buildings,
                  },
                ),
          );
      await _pumpScreen(tester, container, size: const Size(1366, 900));
      FocusNode node(YorksV1ProjectCreationStage stage) => tester
          .widget<InkWell>(
            find.byKey(ValueKey('yorks-v1-project-stage-${stage.name}')),
          )
          .focusNode!;
      node(YorksV1ProjectCreationStage.projectDetails).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(
        node(YorksV1ProjectCreationStage.partiesAndAccess).hasFocus,
        isTrue,
      );
      expect(
        container.read(provider).currentStage,
        YorksV1ProjectCreationStage.projectDetails,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(node(YorksV1ProjectCreationStage.projectDetails).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(node(YorksV1ProjectCreationStage.buildings).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        container.read(provider).currentStage,
        YorksV1ProjectCreationStage.buildings,
      );
    },
  );

  testWidgets(
    'a rich restored draft keeps its acknowledged manual save through navigation checkpoints',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      final controller = container.read(provider.notifier);
      await controller.initialized;
      await controller.save(
        container
            .read(provider)
            .copyWith(
              reference: 'YRA-322',
              name: 'NEXUS — Four substations',
              clientName: 'TAQA Transmission',
              jobOrContractReference: 'C-4587',
              siteLocation: 'Al Dhafra, Abu Dhabi',
              startDate: DateTime.utc(2024, 3, 12),
              endDate: DateTime.utc(2024, 11, 30),
              notes: 'Four new substations as part of the Nexus programme.',
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
              attachments: const [
                YorksV1ProjectAttachmentInput(
                  localId: 'fixture-file-1',
                  fileName: 'DF3W_General_Arrangement.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 2400000,
                ),
                YorksV1ProjectAttachmentInput(
                  localId: 'fixture-file-2',
                  fileName: 'Load_Calculations_DF3W.xlsx',
                  mimeType:
                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  sizeBytes: 1100000,
                ),
                YorksV1ProjectAttachmentInput(
                  localId: 'fixture-file-3',
                  fileName: 'Programme_DF3W.docx',
                  mimeType:
                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                  sizeBytes: 856000,
                ),
                YorksV1ProjectAttachmentInput(
                  localId: 'fixture-file-4',
                  fileName: 'Electrical_Schematics.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 1800000,
                ),
              ],
              rawEditorState: const {
                'reviewedOperationalFiles': [
                  'fixture-file-1:2400000',
                  'fixture-file-2:1100000',
                  'fixture-file-3:856000',
                  'fixture-file-4:1800000',
                ],
              },
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
      await _pumpScreen(tester, container);
      await tester.tap(find.byKey(const ValueKey('project-setup-save-draft')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(YorksV1ProjectStrings.draftSaved.primary),
        ),
        findsOneWidget,
      );
      expect(container.read(provider).isAcknowledged, isTrue);
      final startDateInput = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .firstWhere((field) => field.controller?.text == '12/03/2024');
      // Flutter web updates selection when a hydrated date field receives or
      // loses focus. This is a controller notification without a text edit.
      startDateInput.controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pumpAndSettle();
      final leaving = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(await leaving, isTrue);
      expect(container.read(provider).attachments.length, 4);
      expect(container.read(provider).buildings.length, 4);
      startDateInput.controller!.text = '12/10/';
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        container.read(provider).rawEditorState['dateStartText'],
        '12/10/',
      );
      final editedLeave = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(YorksV1ProjectStrings.keepWorking.primary));
      await tester.pumpAndSettle();
      expect(await editedLeave, isFalse);
    },
  );

  testWidgets(
    'manual local save reports failure, retries, and only then permits a direct exit',
    (tester) async {
      late _ManualSaveTestDraftStorage storage;
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: repository,
        draftStorageFactory: (preferences) =>
            storage = _ManualSaveTestDraftStorage(preferences),
      );
      await _pumpScreen(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Keep this local proposal',
      );
      storage.failWrites = true;
      await tester.tap(find.byKey(const ValueKey('project-setup-save-draft')));
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1ProjectStrings.localSaveFailed.primary),
        findsWidgets,
      );
      expect(
        await container
            .read(yorksV1ProjectSetupNavigationGuardProvider)
            .canLeave(),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      expect(container.read(provider).name, 'Keep this local proposal');
      expect(container.read(provider).isAcknowledged, isFalse);

      storage.failWrites = false;
      await tester.tap(find.byKey(const ValueKey('project-setup-save-draft')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(YorksV1ProjectStrings.draftSaved.primary),
        ),
        findsOneWidget,
      );
      expect(container.read(provider).isAcknowledged, isTrue);
      final permitted = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      expect(await permitted, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.receivedCreationInputs, isEmpty);
    },
  );

  testWidgets(
    'typing during a manual save is retained and requires another leave decision',
    (tester) async {
      late _ManualSaveTestDraftStorage storage;
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        draftStorageFactory: (preferences) =>
            storage = _ManualSaveTestDraftStorage(preferences),
      );
      await _pumpScreen(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Input when Save was pressed',
      );
      final commit = Completer<void>();
      storage.nextTransaction = commit;
      await tester.tap(find.byKey(const ValueKey('project-setup-save-draft')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'New typing while storage was pending',
      );
      await tester.pump(const Duration(milliseconds: 300));
      commit.complete();
      await tester.pumpAndSettle();
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      expect(
        container.read(provider).name,
        'New typing while storage was pending',
      );
      expect(container.read(provider).isAcknowledged, isTrue);
      expect(
        find.text(YorksV1ProjectStrings.changedDuringLocalSave.primary),
        findsOneWidget,
      );
      final leaving = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(YorksV1ProjectStrings.keepWorking.primary));
      await tester.pumpAndSettle();
      expect(await leaving, isFalse);
    },
  );

  testWidgets(
    'navigation guard acknowledges a field still inside the debounce window',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      await _pumpScreen(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Just typed before leaving',
      );
      final stay = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      await tester.tap(find.text(YorksV1ProjectStrings.keepWorking.primary));
      await tester.pumpAndSettle();
      expect(await stay, isFalse);
      final leaving = container
          .read(yorksV1ProjectSetupNavigationGuardProvider)
          .canLeave();
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(YorksV1ProjectStrings.leaveWithSavedDraft.primary),
      );
      await tester.pumpAndSettle();
      final allowed = await leaving;
      final draft = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(allowed, isTrue);
      expect(draft.name, 'Just typed before leaving');
      expect(draft.acknowledgedRevision, draft.revision);
      expect(draft.storageState, YorksV1ProjectDraftStorageState.saved);
      expect(
        await container
            .read(yorksV1ProjectSetupNavigationGuardProvider)
            .canLeave(),
        isTrue,
      );
    },
  );

  testWidgets(
    'returning to a section restores its saved scroll and focused field',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container.read(provider.notifier).initialized;
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  reference: 'YRA-CONTEXT',
                  name: 'Context project',
                  visitedStages: {
                    YorksV1ProjectCreationStage.projectDetails,
                    YorksV1ProjectCreationStage.partiesAndAccess,
                  },
                ),
          );
      await _pumpScreen(tester, container, size: const Size(360, 800));
      final notes = find.byKey(const ValueKey('yorks-v1-project-notes'));
      await tester.ensureVisible(notes);
      await tester.tap(notes);
      await tester.enterText(notes, 'Keep the notes field and its position');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final scrollable = find
          .ancestor(of: notes, matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(before, greaterThan(0));
      // The stepper is inside the scroll area on phones. Use the fixed footer
      // so leaving does not first scroll the current section back to its top.
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-continue')));
      await tester.pumpAndSettle();
      final contexts =
          container.read(provider).rawEditorState['sectionContext'] as Map;
      expect((contexts['projectDetails'] as Map)['focusedField'], 'notes');
      expect((contexts['projectDetails'] as Map)['scroll'], closeTo(before, 1));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('project-setup-mobile-footer')),
          matching: find.text(YorksV1ProjectStrings.back.primary),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(
              find.ancestor(of: notes, matching: find.byType(Scrollable)).first,
            )
            .position
            .pixels,
        closeTo(before, 1),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: notes, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'party removal undo restores stable identity order and hidden contacts',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
      await container.read(provider.notifier).initialized;
      await container
          .read(provider.notifier)
          .save(
            container
                .read(provider)
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                  parties: const [
                    YorksV1ProjectPartyInput(
                      kind: YorksV1ProjectPartyKind.subcontractor,
                      name: 'First party',
                      contactPhone: 'Preserved contact',
                      retainedFields: {
                        'local_row_id': 'party-1',
                        'future_field': 'keep',
                      },
                    ),
                    YorksV1ProjectPartyInput(
                      kind: YorksV1ProjectPartyKind.subcontractor,
                      name: 'Second party',
                      retainedFields: {'local_row_id': 'party-2'},
                    ),
                  ],
                ),
          );
      await _pumpScreen(tester, container);
      tester
          .widget<InputChip>(
            find.byKey(const ValueKey('yorks-v1-party-party-1')),
          )
          .onDeleted!();
      await tester.pumpAndSettle();
      expect(container.read(provider).parties.map((party) => party.name), [
        'Second party',
      ]);
      await tester.tap(
        find.text(YorksV1ProjectStrings.undoPartyRemoval.primary),
      );
      await tester.pumpAndSettle();
      final restored = container.read(provider).parties;
      expect(restored.map((party) => party.name), [
        'First party',
        'Second party',
      ]);
      expect(restored.first.contactPhone, 'Preserved contact');
      expect(restored.first.retainedFields, {
        'local_row_id': 'party-1',
        'future_field': 'keep',
      });
      expect(
        container.read(provider).toCreationInput().toRpcPayload().toString(),
        isNot(contains('local_row_id')),
      );
    },
  );

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      '${size.width} physical building reorder and undo preserve source IDs FRP and flags',
      (tester) async {
        final container = await createContainer(
          role: YorksV1Role.projectEngineer,
          repository: _FakeProjectRepository(),
        );
        final provider = yorksV1ProjectSetupCreationDraftProvider(_authUserId);
        await container.read(provider.notifier).initialized;
        await container
            .read(provider.notifier)
            .save(
              container
                  .read(provider)
                  .copyWith(
                    currentStage: YorksV1ProjectCreationStage.buildings,
                    buildings: const [
                      YorksV1ProjectBuildingInput(
                        localRowId: 'row-a',
                        sourceScopeId: 'scope-a',
                        name: 'First building',
                        hasFrpRoom: true,
                        flags: {'future_flag': 'keep'},
                        deliveryAddress: 'Address A',
                      ),
                      YorksV1ProjectBuildingInput(
                        localRowId: 'row-b',
                        sourceScopeId: 'scope-b',
                        name: 'Second building',
                        deliveryAddress: 'Address B',
                      ),
                    ],
                  ),
            );
        await _pumpScreen(tester, container, size: size);
        await _buildingMenuAction(
          tester,
          container.read(provider).buildings.first,
          YorksV1ProjectStrings.moveBuildingDown.primary,
        );
        expect(
          container
              .read(provider)
              .buildings
              .map((building) => building.sourceScopeId),
          ['scope-b', 'scope-a'],
        );
        await tester.tap(
          find.text(YorksV1ProjectStrings.undoBuildingChange.primary),
        );
        await tester.pumpAndSettle();
        final restored = container.read(provider).buildings;
        expect(restored.map((building) => building.sourceScopeId), [
          'scope-a',
          'scope-b',
        ]);
        expect(restored.map((building) => building.localRowId), [
          'row-a',
          'row-b',
        ]);
        expect(restored.first.hasFrpRoom, isTrue);
        expect(restored.first.flags['future_flag'], 'keep');
        expect(restored.first.deliveryAddress, 'Address A');
      },
    );
  }

  testWidgets('an unchanged edit leaves without submitting an update command', (
    tester,
  ) async {
    final repository = _FakeProjectRepository();
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: repository,
    );
    final now = DateTime.utc(2026, 10, 3);
    final item = YorksV1ProjectPortfolioItem(
      project: YorksV1Project(
        id: 'existing-project',
        reference: 'EXISTING',
        name: 'Existing project',
        state: YorksV1ProjectLifecycle.active,
        version: 4,
        createdAt: now,
        updatedAt: now,
      ),
      activeBuildingCount: 1,
      activeProjectEngineerCount: 1,
      activeSiteEngineerCount: 0,
      activeMembers: [
        YorksV1ProjectMember(
          id: 'unchanged-edit-membership',
          projectId: 'existing-project',
          memberAuthUserId: _authUserId,
          projectRole: YorksV1ProjectMembershipRole.projectEngineer,
          effectiveFrom: now,
          createdAt: now,
        ),
      ],
      buildings: const [
        YorksV1ProjectBuildingInput(
          sourceScopeId: 'scope-1',
          name: 'Existing building',
        ),
      ],
    );
    YorksV1Project? updated;
    await _pumpScreen(
      tester,
      container,
      editItem: item,
      onProjectUpdated: (value) => updated = value,
    );
    await _selectStage(tester, YorksV1ProjectCreationStage.reviewAndCreate);
    await tester.tap(find.byKey(const ValueKey('yorks-v1-project-create')));
    await tester.pumpAndSettle();
    expect(updated?.id, 'existing-project');
    expect(updated?.version, 4);
    expect(repository.updateCalls, 0);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      '${size.width} confirmed edit navigates directly and a later Edit uses the fresh confirmed version',
      (tester) async {
        final repository = _FakeProjectRepository();
        final now = DateTime.utc(2026, 8, 1);
        final item = YorksV1ProjectPortfolioItem(
          project: YorksV1Project(
            id: 'edited-project',
            reference: 'YRA-EDITED',
            name: 'Original project name',
            state: YorksV1ProjectLifecycle.active,
            version: 4,
            createdAt: now,
            updatedAt: now,
            siteLocation: 'Original site',
            notes: 'Original notes',
          ),
          activeBuildingCount: 1,
          activeProjectEngineerCount: 1,
          activeSiteEngineerCount: 0,
          activeMembers: [
            YorksV1ProjectMember(
              id: 'edit-membership',
              projectId: 'edited-project',
              memberAuthUserId: _authUserId,
              projectRole: YorksV1ProjectMembershipRole.projectEngineer,
              effectiveFrom: now,
              createdAt: now,
            ),
          ],
          buildings: const [
            YorksV1ProjectBuildingInput(
              sourceScopeId: 'edit-building',
              name: 'Original building',
              hasFrpRoom: true,
            ),
          ],
        );
        final container = await createContainer(
          role: YorksV1Role.projectEngineer,
          repository: repository,
          portfolioItems: () => [
            YorksV1ProjectPortfolioItem(
              project: repository._updatedProject ?? item.project,
              activeBuildingCount: item.activeBuildingCount,
              activeProjectEngineerCount: item.activeProjectEngineerCount,
              activeSiteEngineerCount: item.activeSiteEngineerCount,
              activeMembers: item.activeMembers,
              buildings: item.buildings,
            ),
          ],
        );
        final router = GoRouter(
          initialLocation: '/yorks/projects/edited-project/edit',
          routes: [
            GoRoute(
              path: '/yorks/projects/:projectId/edit',
              pageBuilder: (_, state) => MaterialPage<void>(
                key: state.pageKey,
                child: YorksV1ProjectEditFlowScreen(
                  projectId: state.pathParameters['projectId']!,
                ),
              ),
            ),
            GoRoute(
              path: '/yorks/projects/:projectId',
              builder: (_, _) => Scaffold(
                body: Text(
                  'Opened ${repository._updatedProject?.name} '
                  'version ${repository._updatedProject?.version}',
                ),
              ),
            ),
          ],
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.binding.setSurfaceSize(size);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final provider = yorksV1ProjectEditDraftProvider(
          const YorksV1ProjectEditDraftContext(
            ownerAuthUserId: _authUserId,
            projectId: 'edited-project',
          ),
        );
        await container.read(provider.notifier).initialized;
        final originalDraftId = container.read(provider).draftId;
        final storageKey = container.read(provider.notifier).storageKey;
        expect(container.read(provider).baseVersion, 4);
        await tester.enterText(
          find.byKey(const ValueKey('yorks-v1-project-name')),
          'Reviewed project name',
        );
        await _selectStage(tester, YorksV1ProjectCreationStage.reviewAndCreate);
        await tester.tap(find.byKey(const ValueKey('yorks-v1-project-create')));
        await tester.pumpAndSettle();
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
        expect(find.byType(YorksV1ProjectCreateFlowScreen), findsNothing);
        expect(
          find.text('Opened Reviewed project name version 5'),
          findsOneWidget,
        );
        expect(repository._updatedProject?.name, 'Reviewed project name');
        expect(repository._updatedProject?.version, 5);
        expect(repository.updateCalls, 1);
        expect(repository.receivedCreationInputs, isEmpty);
        expect(router.canPop(), isFalse);
        await container.read(provider.notifier).initialized;
        await tester.pumpAndSettle();
        final freshDraftId = container.read(provider).draftId;
        expect(freshDraftId, isNot(originalDraftId));
        final preferences = container.read(sharedPreferencesProvider);
        final freshEnvelope = preferences.getString(storageKey)!;
        final tombstoneKey = '$storageKey:retired:$originalDraftId';
        final tombstoneJson = preferences.getString(tombstoneKey)!;
        final tombstone = jsonDecode(tombstoneJson) as Map<String, dynamic>;
        expect(tombstone['retired'], isTrue);
        expect(tombstone['resultProjectId'], 'edited-project');
        final retiredDraft = YorksV1ProjectCreationDraft.fromJson(
          Map<String, dynamic>.from(tombstone['draft'] as Map),
        );
        expect(retiredDraft.draftId, originalDraftId);
        expect(retiredDraft.baseVersion, 4);
        expect(retiredDraft.name, 'Reviewed project name');

        void expectFreshDraftPreserved() {
          final fresh = container.read(provider);
          expect(fresh.draftId, freshDraftId);
          expect(fresh.mode, YorksV1ProjectDraftMode.edit);
          expect(fresh.projectId, 'edited-project');
          expect(fresh.baseVersion, isNull);
          expect(fresh.baseSnapshot, isEmpty);
          expect(fresh.reference, isEmpty);
          expect(fresh.name, isEmpty);
          expect(fresh.siteLocation, isNull);
          expect(fresh.notes, isNull);
          expect(fresh.buildings, isEmpty);
          expect(fresh.parties, isEmpty);
          expect(fresh.attachments, isEmpty);
          expect(fresh.rawEditorState, isEmpty);
          expect(preferences.getString(storageKey), freshEnvelope);
          expect(preferences.getString(tombstoneKey), tombstoneJson);
        }

        expectFreshDraftPreserved();
        for (final modifier in [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.metaLeft,
        ]) {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
          await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
          expectFreshDraftPreserved();
          expect(repository.updateCalls, 1);
          expect(repository.receivedCreationInputs, isEmpty);
          expect(tester.takeException(), isNull);
        }
        router.go('/yorks/projects/edited-project/edit');
        await tester.pumpAndSettle();
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
        expect(find.byType(YorksV1ProjectCreateFlowScreen), findsOneWidget);
        final nextProposal = container.read(provider);
        expect(nextProposal.draftId, freshDraftId);
        expect(nextProposal.baseVersion, 5);
        expect(nextProposal.name, 'Reviewed project name');
        expect(nextProposal.reference, 'YRA-EDITED');
        expect(
          nextProposal.currentStage,
          YorksV1ProjectCreationStage.projectDetails,
        );
        final nextBase = YorksV1ProjectCreationDraft.fromJson(
          nextProposal.baseSnapshot,
        );
        expect(nextBase.baseVersion, 5);
        expect(nextBase.name, 'Reviewed project name');
        expect(
          nextProposal.toCreationInput().toRpcPayload()
            ..remove('idempotency_key'),
          nextBase.toCreationInput().toRpcPayload()..remove('idempotency_key'),
        );
        final nameEditor = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('yorks-v1-project-name')),
            matching: find.byType(EditableText),
          ),
        );
        expect(nameEditor.controller.text, 'Reviewed project name');
        expect(repository.updateCalls, 1);
        expect(repository.receivedCreationInputs, isEmpty);
        expect(preferences.getString(tombstoneKey), tombstoneJson);
        expect(tester.takeException(), isNull);
        expect(find.byType(YorksV1ProjectSetupCompletion), findsNothing);
      },
    );
  }

  testWidgets(
    'throwing analytics cannot block navigation or its saved checkpoint',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        analytics: const _ThrowingAnalyticsService(),
      );
      await _pumpScreen(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-reference')),
        'YRA-ANALYTICS',
      );
      await tester.enterText(
        find.byKey(const ValueKey('yorks-v1-project-name')),
        'Analytics failure proposal',
      );
      await tester.tap(find.byKey(const ValueKey('yorks-v1-project-continue')));
      await tester.pumpAndSettle();
      final draft = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
      );
      expect(draft.currentStage, YorksV1ProjectCreationStage.partiesAndAccess);
      expect(draft.acknowledgedRevision, draft.revision);
      expect(draft.name, 'Analytics failure proposal');
      expect(tester.takeException(), isNull);
    },
  );

  test('screen does not reach a legacy/local project writer', () {
    final source = File(
      'lib/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('projectsProvider')));
    expect(source, isNot(contains('CollectionStore')));
    expect(source, isNot(contains('SupabaseClient')));
    expect(source, contains('yorksV1ProjectCommandControllerProvider'));
  });
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1280, 900),
  ValueChanged<YorksV1Project>? onProjectCreated,
  YorksV1ProjectPortfolioItem? editItem,
  ValueChanged<YorksV1Project>? onProjectUpdated,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Directionality(textDirection: textDirection, child: child!),
        ),
        home: YorksV1ProjectCreateFlowScreen(
          // Retained proposals select their exact ID. Only corrupt/unverified
          // original storage uses the explicit legacy recovery route.
          legacyRecovery:
              editItem == null &&
              container
                      .read(
                        yorksV1ProjectSetupCreationDraftProvider(_authUserId),
                      )
                      .storageState ==
                  YorksV1ProjectDraftStorageState.recoveryRequired,
          resumeDraftId:
              editItem == null &&
                  container
                          .read(
                            yorksV1ProjectSetupCreationDraftProvider(
                              _authUserId,
                            ),
                          )
                          .storageState !=
                      YorksV1ProjectDraftStorageState.recoveryRequired
              ? container
                    .read(yorksV1ProjectSetupCreationDraftProvider(_authUserId))
                    .draftId
              : null,
          onProjectCreated: onProjectCreated,
          editItem: editItem,
          onProjectUpdated: onProjectUpdated,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    // Let auto-disposed, screen-scoped providers finish their scheduled
    // disposal before the test container is closed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _selectStage(
  WidgetTester tester,
  YorksV1ProjectCreationStage stage,
) async {
  final desktop = find.byKey(ValueKey('yorks-v1-project-stage-${stage.name}'));
  final target = desktop.evaluate().isNotEmpty
      ? desktop
      : find.byKey(ValueKey('project-setup-mobile-step-${stage.name}'));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _buildingMenuAction(
  WidgetTester tester,
  YorksV1ProjectBuildingInput building,
  String action,
) async {
  final identity = building.localRowId ?? building.sourceScopeId ?? '0';
  final desktopMenu = find.byKey(
    ValueKey('yorks-v1-desktop-building-menu-$identity'),
  );
  final menu = desktopMenu.evaluate().isNotEmpty
      ? desktopMenu
      : find.byKey(ValueKey('yorks-v1-mobile-building-menu-$identity'));
  expect(menu, findsOneWidget);
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  final item = find.descendant(
    of: find.byType(PopupMenuItem<String>),
    matching: find.text(action),
  );
  expect(item, findsOneWidget);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

class _FakeProjectRepository implements YorksV1ProjectRepository {
  _FakeProjectRepository({this.failFirstCreate = false, this.createDelay});

  final bool failFirstCreate;
  final Completer<void>? createDelay;
  YorksV1Role? creatorRole;
  YorksV1Project? _createdProject;
  YorksV1Project? _updatedProject;
  int updateCalls = 0;
  final List<YorksV1ProjectCreationInput> receivedCreationInputs = [];

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    receivedCreationInputs.add(input);
    if (createDelay != null) await createDelay!.future;
    if (failFirstCreate && receivedCreationInputs.length == 1) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    final now = DateTime.utc(2026, 8, 1);
    final project = YorksV1Project(
      id: 'project-b2-001',
      reference: input.reference,
      name: input.name,
      state: YorksV1ProjectLifecycle.draft,
      version: 0,
      createdAt: now,
      updatedAt: now,
      clientName: input.clientName,
      jobOrContractReference: input.jobOrContractReference,
      siteLocation: input.siteLocation,
    );
    _createdProject = project;
    final creatorProjectRole = creatorRole == YorksV1Role.siteEngineer
        ? YorksV1ProjectMembershipRole.siteEngineer
        : creatorRole?.isEngineering == true
        ? YorksV1ProjectMembershipRole.projectEngineer
        : null;
    return YorksV1ProjectCreationResult(
      project: project,
      scopes: const [],
      members: [
        if (creatorProjectRole != null)
          YorksV1ProjectMember(
            id: 'creator-membership',
            projectId: project.id,
            memberAuthUserId: _authUserId,
            projectRole: creatorProjectRole,
            effectiveFrom: now,
            createdAt: now,
          ),
      ],
      parties: input.parties,
      attachments: input.attachments,
      idempotencyKey: input.idempotencyKey,
    );
  }

  @override
  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<YorksV1Project> setProjectState(
    YorksV1SetProjectStateInput input,
  ) async {
    final project = _createdProject!;
    return YorksV1Project(
      id: project.id,
      reference: project.reference,
      name: project.name,
      state: input.targetState,
      version: input.expectedProjectVersion + 1,
      createdAt: project.createdAt,
      updatedAt: DateTime.utc(2026, 10, 4),
      clientName: project.clientName,
      jobOrContractReference: project.jobOrContractReference,
      siteLocation: project.siteLocation,
    );
  }

  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) async {
    updateCalls++;
    final project = YorksV1Project(
      id: input.projectId,
      reference: input.project.reference,
      name: input.project.name,
      state: YorksV1ProjectLifecycle.active,
      version: input.expectedProjectVersion + 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 10, 4),
      clientName: input.project.clientName,
      jobOrContractReference: input.project.jobOrContractReference,
      siteLocation: input.project.siteLocation,
      startDate: input.project.startDate,
      endDate: input.project.endDate,
      notes: input.project.notes,
    );
    _updatedProject = project;
    return project;
  }

  @override
  Future<YorksV1Project> archiveProject(
    YorksV1ArchiveProjectInput input,
  ) async {
    throw UnimplementedError();
  }
}

class _FakeTeamDirectoryRepository
    implements YorksV1ProjectTeamDirectoryRepository {
  _FakeTeamDirectoryRepository({this.members = const []});

  final List<YorksV1ProjectTeamDirectoryMember> members;

  @override
  Future<List<YorksV1ProjectTeamDirectoryMember>> listActiveMembers() async {
    return members;
  }
}

class _FakeDocumentFileService implements YorksV1DocumentFileService {
  @override
  Future<YorksV1SelectedDocument?> selectDocument() async {
    return YorksV1SelectedDocument(
      fileName: 'site-plan.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
  }

  @override
  Future<YorksV1SelectedDocument?> selectImage() async => null;

  @override
  Future<bool> saveDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => true;
}

class _QueuedDocumentFileService extends _FakeDocumentFileService {
  _QueuedDocumentFileService(this.bytes);
  final List<Uint8List> bytes;
  int selections = 0;

  @override
  Future<YorksV1SelectedDocument?> selectDocument() async =>
      YorksV1SelectedDocument(
        fileName: 'site-plan.pdf',
        mimeType: 'application/pdf',
        bytes: bytes[selections++],
      );
}

class _PreviewDocumentFileService extends _FakeDocumentFileService {
  _PreviewDocumentFileService(this.files);
  final List<YorksV1SelectedDocument> files;
  final List<YorksV1SelectedDocument> saved = [];
  int selections = 0;

  @override
  Future<YorksV1SelectedDocument?> selectDocument() async {
    final index = selections++;
    return index < files.length ? files[index] : null;
  }

  @override
  Future<bool> saveDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    saved.add(
      YorksV1SelectedDocument(
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
      ),
    );
    return true;
  }
}

class _SupportedTestDraftStorage extends SharedPreferencesProjectDraftStorage {
  _SupportedTestDraftStorage(super.preferences);
  @override
  bool get supportsAtomicOwnership => true;
}

class _ManualSaveTestDraftStorage extends _SupportedTestDraftStorage {
  _ManualSaveTestDraftStorage(super.preferences);
  bool failWrites = false;
  Completer<void>? nextTransaction;

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction transaction) work,
  ) async {
    final gate = nextTransaction;
    nextTransaction = null;
    if (gate != null) await gate.future;
    if (failWrites) {
      throw const ProjectDraftStorageException('synthetic_unavailable');
    }
    return super.transaction(lockKey, work);
  }
}

class _ThrowingAnalyticsService extends NoopAnalyticsService {
  const _ThrowingAnalyticsService();
  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) {
    throw StateError('Instrumentation unavailable');
  }
}

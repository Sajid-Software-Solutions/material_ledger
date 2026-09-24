import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_team_directory_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _authUserId = 'test-auth-user-001';

void main() {
  Future<ProviderContainer> createContainer({
    required YorksV1Role? role,
    required _FakeProjectRepository repository,
    YorksV1CurrentPermissionSnapshotState? permissionState,
    YorksV1ProjectTeamDirectoryRepository? teamDirectoryRepository,
    YorksV1DocumentFileService? documentFileService,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue(_authUserId),
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
      expect(
        find.text(YorksV1ProjectStrings.partiesAndAccess.primary),
        findsWidgets,
      );
      expect(find.text(YorksV1ProjectStrings.buildings.primary), findsWidgets);
      expect(
        find.text(YorksV1ProjectStrings.attachments.primary),
        findsWidgets,
      );
      expect(
        find.text(YorksV1ProjectStrings.reviewAndCreate.primary),
        findsWidgets,
      );
      expect(
        find.text(YorksV1ProjectStrings.dateFormatHelp.primary),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    }
  });

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
          yorksV1ProjectCreationDraftProvider(_authUserId).notifier,
        );
        await notifier.save(
          container
              .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
            .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
      yorksV1ProjectCreationDraftProvider(_authUserId).notifier,
    );
    await draftNotifier.save(
      container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
          .attachments
          .single
          .sizeBytes,
      3,
    );
  });

  testWidgets(
    'restored attachment metadata requires and accepts a same-name reselect',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
        documentFileService: _FakeDocumentFileService(),
      );
      await container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
        find.textContaining(
          YorksV1ProjectStrings.attachmentNeedsReselect.primary,
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('yorks-v1-attachment-dropzone')),
      );
      await tester.pumpAndSettle();

      final restored = container.read(
        yorksV1ProjectCreationDraftProvider(_authUserId),
      );
      expect(restored.attachments, hasLength(1));
      expect(restored.attachments.single.sizeBytes, 3);
      expect(
        find.textContaining(YorksV1ProjectStrings.attachmentReady.primary),
        findsOneWidget,
      );
    },
  );

  testWidgets('R35 project attachments stage — 1366×768', (tester) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    await container
        .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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

    await expectLater(
      find.byType(YorksV1ProjectCreateFlowScreen),
      matchesGoldenFile('goldens/r35/project_create_attachments_desktop.png'),
    );
  });

  testWidgets('R35 project attachments stage — 360×800', (tester) async {
    final container = await createContainer(
      role: YorksV1Role.projectEngineer,
      repository: _FakeProjectRepository(),
    );
    await container
        .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
        .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
        .save(
          container
              .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
      tester.widget<Text>(find.text('Dubai South')).textAlign,
      TextAlign.start,
    );
    expect(
      Directionality.of(tester.element(find.text('Dubai South'))),
      TextDirection.ltr,
    );
    await expectLater(
      find.byType(YorksV1ProjectCreateFlowScreen),
      matchesGoldenFile('goldens/r35/project_create_review_desktop.png'),
    );
  });

  testWidgets(
    'copies a building form for the next building and updates an existing building in place',
    (tester) async {
      final container = await createContainer(
        role: YorksV1Role.projectEngineer,
        repository: _FakeProjectRepository(),
      );
      final draftNotifier = container.read(
        yorksV1ProjectCreationDraftProvider(_authUserId).notifier,
      );
      await draftNotifier.save(
        container
            .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
      final editButton = find.byTooltip(
        YorksV1ProjectStrings.editBuilding.primary,
      );
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
      await tester.tap(find.text(YorksV1ProjectStrings.updateBuilding.primary));
      await tester.pumpAndSettle();

      final updated = container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
        'B02',
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
        'North gate',
      );
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
        final provider = yorksV1ProjectCreationDraftProvider(_authUserId);
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
      yorksV1ProjectCreationDraftProvider(_authUserId).notifier,
    );
    final initialDraft = container
        .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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

    await _pumpScreen(
      tester,
      container,
      onProjectCreated: (project) => createdProject = project,
    );

    final createButton = find.byKey(const ValueKey('yorks-v1-project-create'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(repository.receivedCreationInputs, hasLength(1));
    expect(
      container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
      {originalIdempotencyKey},
    );
    expect(createdProject?.reference, 'YRK-B2-001');
    expect(
      find.text(YorksV1ProjectStrings.projectCreated.primary),
      findsNothing,
    );
    expect(
      container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
          .reference,
      isEmpty,
    );
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
        yorksV1ProjectCreationDraftProvider(_authUserId).notifier,
      );
      await draftNotifier.save(
        container
            .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
      expect(find.text(YorksV1ProjectStrings.profileId.primary), findsWidgets);

      final createButton = find.byKey(
        const ValueKey('yorks-v1-project-create'),
      );
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(repository.receivedCreationInputs, isEmpty);
      expect(
        container
            .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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

  testWidgets(
    'opens the new project overview immediately after a committed create',
    (tester) async {
      final repository = _FakeProjectRepository();
      final container = await createContainer(
        role: YorksV1Role.siteEngineer,
        repository: repository,
      );
      await container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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
            builder: (_, _) => const YorksV1ProjectCreateFlowScreen(),
          ),
          GoRoute(
            path: '/yorks/projects/:projectId',
            builder: (_, state) => Scaffold(
              body: Text('Opened ${state.pathParameters['projectId']}'),
            ),
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(1280, 900));
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
      expect(
        find.text(YorksV1ProjectStrings.projectCreated.primary),
        findsNothing,
      );
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
          .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text(fallbackAuthUserId), findsNothing);
      expect(find.text(YorksV1ProjectStrings.profileId.primary), findsWidgets);
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
          .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text(emailLikeDisplayName), findsNothing);
      expect(find.textContaining('amina@example.test'), findsNothing);
      expect(find.text(YorksV1ProjectStrings.profileId.primary), findsWidgets);
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
          .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
          .save(
            container
                .read(yorksV1ProjectCreationDraftProvider(_authUserId))
                .copyWith(
                  currentStage: YorksV1ProjectCreationStage.partiesAndAccess,
                ),
          );

      await _pumpScreen(tester, container);

      expect(find.text('Amina Project Engineer'), findsOneWidget);
      expect(find.text('Bilal Site Engineer'), findsNothing);
      final candidate = find.text('Amina Project Engineer');
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();

      final initialMembers = container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
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

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1280, 900),
  ValueChanged<YorksV1Project>? onProjectCreated,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: YorksV1ProjectCreateFlowScreen(
          onProjectCreated: onProjectCreated,
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

class _FakeProjectRepository implements YorksV1ProjectRepository {
  _FakeProjectRepository({this.failFirstCreate = false});

  final bool failFirstCreate;
  final List<YorksV1ProjectCreationInput> receivedCreationInputs = [];

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    receivedCreationInputs.add(input);
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
    return YorksV1ProjectCreationResult(
      project: project,
      scopes: const [],
      members: const [],
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
    throw UnimplementedError();
  }

  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) async {
    throw UnimplementedError();
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

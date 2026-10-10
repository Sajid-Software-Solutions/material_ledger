import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/features/engineering_tools/presentation/screens/yorks_v1_engineering_calculator_screens.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in <({String name, Widget child, String expected})>[
    (
      name: 'material requests',
      child: YorksV1MaterialRequestsScreen(),
      expected: 'Material Requests',
    ),
    (
      name: 'duct sizer',
      child: YorksV1DuctSizerScreen(),
      expected: 'Duct Sizer',
    ),
    (
      name: 'ESP calculator',
      child: YorksV1EspCalculatorScreen(),
      expected: 'ESP Calculator',
    ),
  ]) {
    testWidgets(
      'R35 ${entry.name} route stays laid out at desktop and mobile widths',
      (tester) async {
        final preferences = await SharedPreferences.getInstance();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => YorksV1WorkspaceShell(child: entry.child),
            ),
          ],
        );

        for (final size in [
          const Size(1366, 768),
          const Size(1024, 768),
          const Size(360, 800),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(preferences),
                yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                  (ref) => YorksV1TestPermissionController(
                    yorksV1TrustedFeaturePermissionState(),
                  ),
                ),
                yorksV1CurrentRoleProvider.overrideWithValue(
                  YorksV1Role.projectEngineer,
                ),
                yorksV1MaterialRequestListProvider(
                  null,
                ).overrideWith((ref) async => []),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(entry.expected), findsWidgets);
          expect(tester.takeException(), isNull, reason: 'viewport $size');
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  }

  testWidgets(
    'R35 material requests shows a recoverable state without backend',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1MaterialRequestsScreen(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Material Requests'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Company Use entry appears at desktop and mobile widths when released',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      const companyRequestsEnabled = YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
        companyMaterialRequests: true,
      );

      for (final entry in <({Size size, Key entryKey})>[
        (
          size: const Size(1366, 768),
          entryKey: const ValueKey('material-request-centre-create-company'),
        ),
        (
          size: const Size(360, 800),
          entryKey: const ValueKey('material-request-centre-create-company'),
        ),
      ]) {
        tester.view.physicalSize = entry.size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1FeatureFlagsProvider.overrideWithValue(
                companyRequestsEnabled,
              ),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => YorksV1TestPermissionController(
                  yorksV1TrustedFeaturePermissionState(),
                ),
              ),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.projectEngineer,
              ),
              yorksV1MaterialRequestListProvider(
                null,
              ).overrideWith((ref) async => []),
            ],
            child: const MaterialApp(home: YorksV1MaterialRequestsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(entry.entryKey), findsOneWidget);
        expect(
          find.byKey(const ValueKey('material-request-use-switch')),
          findsNothing,
        );
        expect(find.text('Company use'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${entry.size}');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Dispatches keeps completed dispatch records connected and visible',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestListProvider(null).overrideWith(
              (ref) async => [_receivedQueueRequest, _closedQueueRequest],
            ),
          ],
          child: const MaterialApp(
            home: YorksV1WorkflowQueueScreen(
              kind: YorksV1WorkflowQueueKind.dispatches,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dispatch Centre'), findsOneWidget);
      expect(find.text('Project folders'), findsOneWidget);
      expect(find.text('Completed deliveries'), findsWidgets);
      await tester.tap(find.text('All dispatches'));
      await tester.pumpAndSettle();
      expect(find.text('YRA123-MR-RECEIVED'), findsOneWidget);
      expect(find.text('YRA123-MR-CLOSED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dispatch-register-table')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dispatch Centre remains organized at a 360px phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestListProvider(null).overrideWith(
            (ref) async => [_receivedQueueRequest, _closedQueueRequest],
          ),
        ],
        child: const MaterialApp(
          home: YorksV1WorkflowQueueScreen(
            kind: YorksV1WorkflowQueueKind.dispatches,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispatch Centre'), findsOneWidget);
    expect(find.byKey(const ValueKey('dispatch-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('dispatch-register-table')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'R35 new material request draft stays laid out at desktop and mobile widths',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1MaterialRequestDraftScreen(
                draftId: 'layout-test-draft',
              ),
            ),
          ),
        ],
      );

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final size in [
        const Size(1512, 772),
        const Size(1366, 768),
        const Size(1024, 768),
        const Size(360, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => YorksV1TestPermissionController(
                  yorksV1TrustedFeaturePermissionState(),
                ),
              ),
              yorksV1AuthUserIdProvider.overrideWithValue('layout-test-user'),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.projectEngineer,
              ),
              yorksV1MaterialRequestDraftProjectsProvider.overrideWith(
                (ref) async => [],
              ),
            ],
            child: MaterialApp.router(
              key: ValueKey('material-request-draft-${size.width}'),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Request Information'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
    },
  );

  testWidgets(
    'R35 submitted material request record stays laid out at desktop and mobile widths',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final request = YorksV1MaterialRequest(
        id: 'layout-detail',
        projectId: 'project-layout',
        projectReference: 'YRA-123',
        projectName: 'Yorks Tower',
        scopeId: 'common',
        scopeName: 'Common / All Buildings',
        state: YorksV1MaterialRequestState.received,
        recordVersion: 1,
        createdAt: DateTime.utc(2026, 8, 3),
        updatedAt: DateTime.utc(2026, 8, 3),
        timing: YorksV1MaterialRequestTiming.normal,
        requestNumber: 'YRA123-MR101',
        title: 'HVAC materials',
        requesterDisplayName: 'Masaud Khan',
        requesterProjectRole: 'Project Engineer',
        currentActionOwnerRole: 'Procurement',
        lines: const [
          YorksV1MaterialRequestLine(
            id: 'line-layout',
            displayOrder: 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: 'Insulated ductwork',
            brandOrigin: 'Yorks',
            size: '500 x 300 mm',
            planningModelTag: 'DX-01',
            quantity: '21',
            unit: 'Cylinder',
          ),
        ],
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1MaterialRequestDetailScreen(
                requestId: 'layout-detail',
              ),
            ),
          ),
        ],
      );

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final size in [
        const Size(1366, 768),
        const Size(1024, 768),
        const Size(360, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => YorksV1TestPermissionController(
                  yorksV1TrustedFeaturePermissionState(),
                ),
              ),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.projectEngineer,
              ),
              yorksV1MaterialRequestDetailProvider(
                'layout-detail',
              ).overrideWith((ref) async => request),
              yorksV1MaterialRequestDocumentProvider(
                'layout-detail',
              ).overrideWith(
                (ref) async =>
                    YorksV1MaterialRequestDocumentModel.fromRequest(request),
              ),
              yorksV1ReturnsDocumentsWorkspaceProvider(
                'layout-detail',
              ).overrideWith(
                (ref) async => _assignedEngineerDeliveryOrderWorkspace,
              ),
            ],
            child: MaterialApp.router(
              key: ValueKey('material-request-detail-${size.width}'),
              routerConfig: router,
            ),
          ),
        );
        // The controlled PDF preview renders asynchronously. A finite pump
        // verifies the route layout without treating the platform preview's
        // background raster work as an application animation.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        if (size.width > 720) {
          expect(
            find.byKey(const ValueKey('material-request-decision-banner')),
            findsOneWidget,
            reason: 'viewport $size',
          );
        }
        expect(
          find.text('${request.projectName} · ${request.scopeName}'),
          findsOneWidget,
          reason: 'viewport $size',
        );
        if (size.width == 1366) {
          final headingRect = tester.getRect(
            find.byKey(const ValueKey('material-request-record-heading')),
          );
          final workflowRect = tester.getRect(
            find.byKey(const ValueKey('material-request-workflow-actions')),
          );
          expect(workflowRect.left, greaterThan(headingRect.left));
          expect(workflowRect.right, greaterThan(headingRect.right));
          expect(
            (workflowRect.top - headingRect.top).abs(),
            lessThanOrEqualTo(2),
          );
        }
        if (size.width > 720) {
          for (final tableKey in [
            'material-request-items-table',
            'material-request-quantity-history-table',
          ]) {
            final units = find.descendant(
              of: find.byKey(ValueKey(tableKey)),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    (widget.data?.contains('Cylinder') ?? false),
              ),
            );
            expect(units, findsWidgets);
            for (final element in units.evaluate()) {
              final paragraph = element.findRenderObject()! as RenderParagraph;
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: (element.widget as Text).data!.length,
                ),
              );
              expect(
                boxes.map((box) => box.top).toSet().length,
                1,
                reason: 'quantity/unit must fit one line at $size',
              );
            }
          }
        }
        if (size.width == 1366 || size.width == 360) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/r35/material_request_table_widths_${size.width.toInt()}.png',
            ),
          );
        }
        final requestInformation = find.byKey(
          const ValueKey('material-request-information-action'),
        );
        expect(requestInformation, findsOneWidget, reason: 'viewport $size');
        await tester.ensureVisible(requestInformation);
        await tester.pumpAndSettle();
        await tester.tap(requestInformation);
        await tester.pumpAndSettle();
        expect(find.textContaining('Masaud Khan'), findsAtLeastNWidgets(1));
        expect(find.text('YRA-123'), findsWidgets);
        if (size.width > 720) {
          expect(
            find.byKey(const ValueKey('material-request-information-panel')),
            findsOneWidget,
          );
        }
        if (size.width == 1512) {
          final panelRect = tester.getRect(
            find.byKey(const ValueKey('material-request-information-panel')),
          );
          final itemsTableRect = tester.getRect(
            find.byKey(const ValueKey('material-request-items-table')),
          );
          final quantityTableRect = tester.getRect(
            find
                .ancestor(
                  of: find.byKey(
                    const ValueKey('material-request-quantity-history-table'),
                  ),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          );
          expect(itemsTableRect.right, lessThan(panelRect.left));
          expect(quantityTableRect.right, lessThan(panelRect.left));
        }
        await tester.tap(find.byIcon(Icons.close_rounded).last);
        await tester.pumpAndSettle();
        // A fully received record is closed before optional document work; the
        // router may retain an offstage copy across the viewport loop.
        expect(find.text('Close request'), findsAtLeastNWidgets(1));
        if (size.width <= 720) {
          expect(
            find.byKey(const ValueKey('mobile-mr-lifecycle')),
            findsOneWidget,
          );
        } else {
          final preview = find.byKey(
            const ValueKey('yorks-v1-controlled-material-request-preview'),
          );
          if (preview.evaluate().isEmpty) {
            final disclosure = find.text(
              YorksV1MaterialRequestStrings
                  .controlledDocumentDescription
                  .primary,
            );
            await tester.ensureVisible(disclosure);
            await tester.tap(disclosure);
            await tester.pump(const Duration(milliseconds: 250));
          }
          expect(preview, findsOneWidget);
        }
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
    },
  );

  testWidgets(
    'legacy arrangement review stays hidden without collapsing the heading',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final request = YorksV1MaterialRequest(
        id: 'approval-layout',
        projectId: 'project-layout',
        projectReference: 'YRA-313',
        projectName: 'Yorks Tower',
        scopeId: 'common',
        scopeName: 'Electrical Materials',
        state: YorksV1MaterialRequestState.awaitingApproval,
        recordVersion: 2,
        createdAt: DateTime.utc(2026, 8, 12),
        updatedAt: DateTime.utc(2026, 8, 12),
        timing: YorksV1MaterialRequestTiming.normal,
        requestNumber: 'YRA313-MR002',
        title: 'Electrical Materials',
        requesterDisplayName: 'Valentin Ortula',
        requesterProjectRole: 'Project Engineer',
        currentActionOwnerRole: 'Project Engineer',
        lines: const [
          YorksV1MaterialRequestLine(
            id: 'approval-line',
            displayOrder: 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: 'Cable tray hanging clamp',
            quantity: '50',
            unit: 'Nos',
          ),
        ],
      );
      final arrangement = YorksV1ProcurementArrangement(
        id: 'arrangement-layout',
        version: 1,
        status: YorksV1ArrangementStatus.awaitingApproval,
        isCurrent: true,
        recordVersion: 2,
        startedByDisplayName: 'Procurement User',
        startedAt: DateTime.utc(2026, 8, 12),
        lines: const [
          YorksV1ArrangementLine(
            id: 'arrangement-line',
            requestLineId: 'approval-line',
            displayOrder: 1,
            description: 'Cable tray hanging clamp',
            requestedQuantity: '50',
            unit: 'Nos',
            source: YorksV1ArrangementSource.externalSupplier,
            decision: YorksV1ArrangementDecision.full,
            arrangedQuantity: '50',
          ),
        ],
      );
      final workspace = YorksV1ArrangementWorkspace(
        requestId: request.id,
        requestNumber: request.requestNumber,
        requestState: 'awaiting_approval',
        requestRecordVersion: 2,
        canBegin: false,
        canSave: false,
        canDecide: true,
        arrangements: [arrangement],
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1MaterialRequestDetailScreen(
                requestId: 'approval-layout',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
            yorksV1MaterialRequestDetailProvider(
              request.id,
            ).overrideWith((ref) async => request),
            yorksV1MaterialRequestDocumentProvider(request.id).overrideWith(
              (ref) async =>
                  YorksV1MaterialRequestDocumentModel.fromRequest(request),
            ),
            yorksV1ArrangementWorkspaceProvider(
              request.id,
            ).overrideWith((ref) async => workspace),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final heading = find.byKey(
        const ValueKey('material-request-record-heading'),
      );
      expect(heading, findsOneWidget);
      expect(tester.getSize(heading).width, greaterThan(180));
      expect(find.text('Review & Approve'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/logo.png'),
          tester.element(find.byType(YorksV1WorkspaceShell)),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/material_request_approval_header_1366x768.png',
        ),
      );
    },
  );

  testWidgets(
    'R35 project workspace overview stays laid out at desktop and mobile widths',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final portfolioItem = YorksV1ProjectPortfolioItem(
        project: YorksV1Project(
          id: 'project-layout',
          reference: 'YRA-123',
          name: 'Yorks Tower HVAC',
          state: YorksV1ProjectLifecycle.active,
          version: 1,
          createdAt: DateTime.utc(2026, 8, 3),
          updatedAt: DateTime.utc(2026, 8, 3),
          siteLocation: 'Dubai',
        ),
        activeBuildingCount: 1,
        activeProjectEngineerCount: 1,
        activeSiteEngineerCount: 1,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1ProjectWorkspaceScreen(projectId: 'project-layout'),
            ),
          ),
        ],
      );

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final size in [
        const Size(1366, 768),
        const Size(1024, 768),
        const Size(360, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => YorksV1TestPermissionController(
                  yorksV1TrustedFeaturePermissionState(),
                ),
              ),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.projectEngineer,
              ),
              yorksV1ProjectPortfolioProvider.overrideWith(
                (ref) async => [portfolioItem],
              ),
              yorksV1BoqGroupsProvider(
                'project-layout',
              ).overrideWith((ref) async => const <YorksV1BoqGroup>[]),
              yorksV1MaterialRequestListProvider(
                'project-layout',
              ).overrideWith((ref) async => const <YorksV1MaterialRequest>[]),
              yorksV1DocumentWorkspaceProvider('project-layout').overrideWith(
                (ref) async => const YorksV1DocumentWorkspace(
                  projectId: 'project-layout',
                  documents: [],
                  auditEntries: [],
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Yorks Tower HVAC'), findsOneWidget);
        expect(
          find.text(size.width < 600 ? 'BOQ GROUPS' : 'BOQ Groups'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
    },
  );

  testWidgets(
    'ESP row editor keeps focus while recalculating after each keystroke',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1EspCalculatorScreen(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final flowField = find.byType(TextFormField).first;
      await tester.ensureVisible(flowField);
      await tester.tap(flowField);
      await tester.pump();
      final focusNode = FocusManager.instance.primaryFocus;
      expect(focusNode, isNotNull);

      await tester.enterText(flowField, '120');
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(focusNode));
      expect(tester.widget<TextFormField>(flowField).controller?.text, '120');
      expect(tester.takeException(), isNull);
    },
  );
}

final _assignedEngineerDeliveryOrderWorkspace =
    YorksV1ReturnsDocumentsWorkspace(
      requestId: 'layout-detail',
      projectId: 'project-layout',
      requestNumber: 'YRA123-MR101',
      requestState: 'received',
      requestRecordVersion: 1,
      projectName: 'Yorks Tower',
      projectReference: 'YRA-123',
      scopeName: 'Common / All Buildings',
      canGenerateDeliveryOrder: true,
      canSubmitMaterialReturn: false,
      canConfirmMaterialReturn: false,
      deliveryOrderDispatches: [
        YorksV1DeliveryOrderDispatch(
          dispatchId: 'dispatch-layout',
          dispatchNumber: 'YRA123-DSP001',
          dispatchDate: DateTime.utc(2026, 8, 3),
          dispatchRecordVersion: 1,
          canGenerate: true,
          receiptReviewedAt: DateTime.utc(2026, 8, 3),
        ),
      ],
      returnCandidates: const [],
      materialReturns: const [],
      returnInventoryItems: const [],
    );

YorksV1MaterialRequest _queueRequest(
  String id,
  String number,
  YorksV1MaterialRequestState state,
) => YorksV1MaterialRequest(
  id: id,
  projectId: 'project-layout',
  projectReference: 'YRA-123',
  projectName: 'Yorks Tower',
  scopeId: 'common',
  scopeName: 'Common / All Buildings',
  state: state,
  recordVersion: 1,
  createdAt: DateTime.utc(2026, 8, 3),
  updatedAt: DateTime.utc(2026, 8, 3),
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: number,
  title: 'Completed dispatch record',
  requesterDisplayName: 'Masaud Khan',
  requesterProjectRole: 'Project Engineer',
  currentActionOwnerRole: 'Project Engineer',
  lines: const [],
);

final _receivedQueueRequest = _queueRequest(
  'queue-received',
  'YRA123-MR-RECEIVED',
  YorksV1MaterialRequestState.received,
);
final _closedQueueRequest = _queueRequest(
  'queue-closed',
  'YRA123-MR-CLOSED',
  YorksV1MaterialRequestState.closed,
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_overview_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';

/// `GoRouter` validates its whole route tree at construction (duplicate paths,
/// malformed nested sub-routes, etc. throw immediately). Building it for every
/// role therefore validates the engineer `StatefulShellRoute` and the top-level
/// create-flows (`/new-request`, `/projects/new`, `/my-projects`) that overlay
/// it — plus the office shell — without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(debugPreloadDeferredRoutes);

  testWidgets('cold notification link survives the signed-out login gate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const target =
        '/notifications?notificationId=11000000-0000-4000-8000-000000000001';
    final router = createAppRouter(
      isOnboarded: true,
      isLoggedIn: false,
      role: UserRole.engineer,
      restoredLocation: target,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, RoutePaths.login);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['returnTo'],
      target,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  test('project workspace path uses the stable project identifier', () {
    expect(
      RoutePaths.projectWorkspacePath('project-41'),
      '/projects/project-41',
    );
  });

  test('scoped access path uses the stable AppUser identifier', () {
    expect(
      RoutePaths.yorksV1UserAccessPath('app-user-41'),
      '/admin/users/app-user-41/access',
    );
  });

  test('Team Chat deep links use the stable conversation identifier', () {
    expect(RoutePaths.yorksV1TeamChatPath(), RoutePaths.yorksV1TeamChat);
    expect(
      RoutePaths.yorksV1TeamChatPath('conversation-41'),
      '/yorks/team-chat/conversation-41',
    );
  });

  test('returning users start at a useful route without a splash hop', () {
    final signedOut = createAppRouter(
      isOnboarded: true,
      isLoggedIn: false,
      role: UserRole.engineer,
    );
    final signedIn = createAppRouter(
      isOnboarded: true,
      isLoggedIn: true,
      role: UserRole.engineer,
    );
    addTearDown(signedOut.dispose);
    addTearDown(signedIn.dispose);

    expect(signedOut.routeInformationProvider.value.uri.path, RoutePaths.login);
    expect(
      signedIn.routeInformationProvider.value.uri.path,
      RoutePaths.engineerHome,
    );
  });

  test('only a genuine first run enters the compatibility splash', () {
    final router = createAppRouter(
      isOnboarded: false,
      isLoggedIn: false,
      role: UserRole.engineer,
    );
    addTearDown(router.dispose);

    expect(router.routeInformationProvider.value.uri.path, RoutePaths.splash);
  });

  group('createAppRouter builds a valid tree for every role', () {
    for (final role in UserRole.values) {
      test('role: ${role.name}', () {
        final router = createAppRouter(
          isOnboarded: true,
          isLoggedIn: true,
          role: role,
        );
        addTearDown(router.dispose);
        expect(router.configuration.routes, isNotEmpty);
      });
    }
  });

  testWidgets(
    'Accountant is contained to locked Home and shared profile routes',
    (tester) async {
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.accountant,
        user: AppUser(
          id: 'accountant-user',
          fullName: 'Accounts User',
          email: 'accounts@yorks.test',
          role: UserRole.accountant,
          yorksV1RoleCache: YorksV1Role.accountant,
          yorksV1Roles: const [YorksV1Role.accountant],
          createdAt: DateTime.utc(2026, 8, 25),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1BoqEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1ArrangementEnabled: true,
        yorksV1LogisticsEnabled: true,
        yorksV1ReturnsDocumentsEnabled: true,
        yorksV1DocumentsEnabled: true,
        yorksV1TeamChatEnabled: true,
        yorksV1InventorySuppliersEnabled: true,
        yorksV1Role: YorksV1Role.accountant,
      );
      addTearDown(router.dispose);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            appVersionProvider.overrideWithValue(
              const AppVersionInfo(version: '1.0.0', build: 1),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(
        find.text(YorksV1OverviewStrings.accountantRolloutTitle.primary),
        findsOneWidget,
      );
      expect(router.routeInformationProvider.value.uri.path, '/');

      for (final deniedPath in <String>[
        RoutePaths.materials,
        RoutePaths.rentals,
        RoutePaths.people,
        RoutePaths.more,
        RoutePaths.engineerBrowse,
        RoutePaths.engineerProjects,
        RoutePaths.engineerCreateProject,
        RoutePaths.engineerNewRequest,
        RoutePaths.adminProjects,
        RoutePaths.adminRequests,
        RoutePaths.inventory,
        RoutePaths.procurement,
        RoutePaths.finance,
        RoutePaths.users,
        RoutePaths.activityLog,
        RoutePaths.yorksV1Projects,
        RoutePaths.yorksV1MaterialRequests,
        RoutePaths.yorksV1Inventory,
        RoutePaths.yorksV1Dispatches,
        RoutePaths.yorksV1Returns,
        RoutePaths.yorksV1Configuration,
        RoutePaths.yorksV1TeamChat,
      ]) {
        router.go(deniedPath);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.engineerHome,
          reason: deniedPath,
        );
      }

      router.go(RoutePaths.engineerProfile);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerProfile,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'V1 Procurement project deep links land on an office-shell safe route',
    (tester) async {
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.procurement,
        user: AppUser(
          id: 'procurement-user',
          fullName: 'Procurement User',
          email: 'procurement@yorks.test',
          role: UserRole.procurement,
          createdAt: DateTime.utc(2026, 8, 1),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1BoqEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1ArrangementEnabled: true,
        yorksV1LogisticsEnabled: true,
        yorksV1ReturnsDocumentsEnabled: true,
        yorksV1DocumentsEnabled: true,
        yorksV1InventorySuppliersEnabled: true,
        yorksV1Role: YorksV1Role.procurement,
      );
      addTearDown(router.dispose);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // The retained splash has a chained handoff animation. Let it finish
      // before exercising a V1 deep link so no disposed splash timer remains.
      await tester.pumpAndSettle(const Duration(seconds: 5));

      router.go(RoutePaths.engineerCreateProject);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.engineerProjects);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.procurement);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.adminRequests);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.yorksV1ProjectEditPath('project-1'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.yorksV1DuctSizer);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.activityLog);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.yorksV1Configuration);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      router.go(RoutePaths.yorksV1InventoryImport);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1InventoryImport,
      );
    },
  );

  testWidgets(
    'V1 Project and Site Engineers cannot reach retained project routes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      for (final v1Role in [
        YorksV1Role.projectEngineer,
        YorksV1Role.siteEngineer,
        YorksV1Role.seniorMechanicalEngineer,
        YorksV1Role.projectManager,
        YorksV1Role.workshopInCharge,
        YorksV1Role.documentController,
      ]) {
        final router = createAppRouter(
          isOnboarded: true,
          isLoggedIn: true,
          role: UserRole.engineer,
          user: AppUser(
            id: '${v1Role.name}-user',
            fullName: '${v1Role.name} User',
            email: '${v1Role.name}@yorks.test',
            role: UserRole.engineer,
            createdAt: DateTime.utc(2026, 8, 1),
          ),
          yorksV1ProjectsEnabled: true,
          yorksV1BoqEnabled: true,
          yorksV1RequestsEnabled: true,
          yorksV1ArrangementEnabled: true,
          yorksV1LogisticsEnabled: true,
          yorksV1ReturnsDocumentsEnabled: true,
          yorksV1DocumentsEnabled: true,
          yorksV1InventorySuppliersEnabled: true,
          yorksV1Role: v1Role,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final deniedPaths = <String>[
          RoutePaths.engineerProjects,
          RoutePaths.engineerProjectsView,
          RoutePaths.projectWorkspacePath('legacy-project'),
          RoutePaths.planReviewPath('legacy-project'),
          RoutePaths.planBuildPath('legacy-project'),
          RoutePaths.planDiffPath('legacy-project'),
          RoutePaths.engineerNewRequest,
          RoutePaths.engineerPickMaterials,
          RoutePaths.requests,
          RoutePaths.requestDetailPath('legacy-request'),
          RoutePaths.confirmReceiptPath('legacy-request'),
          RoutePaths.returnStore,
          RoutePaths.yorksV1Dispatches,
          RoutePaths.activityLog,
          RoutePaths.yorksV1Configuration,
          RoutePaths.yorksV1InventorySuppliers,
          RoutePaths.yorksV1InventoryImport,
          RoutePaths.yorksV1InventorySupplierPath('supplier-1'),
          if (v1Role != YorksV1Role.seniorMechanicalEngineer)
            RoutePaths.yorksV1Inventory,
        ];
        for (final path in deniedPaths) {
          router.go(path);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            RoutePaths.engineerHome,
            reason: '${v1Role.name} must not enter $path while V1 is enabled',
          );
        }

        if (v1Role == YorksV1Role.seniorMechanicalEngineer) {
          router.go(RoutePaths.yorksV1Inventory);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            RoutePaths.yorksV1Inventory,
            reason: 'Senior Mechanical Engineer has read-only inventory access',
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );

  testWidgets('V1 Admin cannot deep link to deferred Accounts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = createAppRouter(
      isOnboarded: true,
      isLoggedIn: true,
      role: UserRole.admin,
      user: AppUser(
        id: 'admin-user',
        fullName: 'Admin User',
        email: 'admin@yorks.test',
        role: UserRole.admin,
        createdAt: DateTime.utc(2026, 8, 1),
      ),
      yorksV1ProjectsEnabled: true,
      yorksV1Role: YorksV1Role.admin,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    router.go(RoutePaths.finance);
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.engineerHome,
    );
  });

  testWidgets('V1 Admin can open the controlled Configuration route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = createAppRouter(
      isOnboarded: true,
      isLoggedIn: true,
      role: UserRole.admin,
      user: AppUser(
        id: 'configuration-admin',
        fullName: 'Configuration Admin',
        email: 'configuration-admin@yorks.test',
        role: UserRole.admin,
        createdAt: DateTime.utc(2026, 8, 14),
      ),
      yorksV1ProjectsEnabled: true,
      yorksV1Role: YorksV1Role.admin,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    router.go(RoutePaths.yorksV1Configuration);
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.yorksV1Configuration,
    );
  });

  testWidgets(
    'only Senior Mechanical Engineer among engineering roles can open User Management',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      for (final v1Role in [
        YorksV1Role.seniorMechanicalEngineer,
        YorksV1Role.projectManager,
      ]) {
        final router = createAppRouter(
          isOnboarded: true,
          isLoggedIn: true,
          role: UserRole.engineer,
          user: AppUser(
            id: v1Role.claimValue,
            fullName: v1Role.name,
            email: '${v1Role.claimValue}@yorks.test',
            role: UserRole.engineer,
            createdAt: DateTime.utc(2026, 8, 9),
          ),
          yorksV1ProjectsEnabled: true,
          yorksV1Role: v1Role,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        router.go(RoutePaths.users);
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          v1Role == YorksV1Role.seniorMechanicalEngineer
              ? RoutePaths.users
              : RoutePaths.engineerHome,
        );

        final targetPath = RoutePaths.yorksV1UserAccessPath('target-app-user');
        router.go(targetPath);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          v1Role == YorksV1Role.seniorMechanicalEngineer
              ? targetPath
              : RoutePaths.engineerHome,
          reason:
              '${v1Role.name} must follow the same protected boundary for a user access deep link',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );

  testWidgets('Company-enabled home does not inherit Project read denial', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    for (final companyEnabled in [false, true]) {
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.engineer,
        user: AppUser(
          id: 'company-site-engineer',
          fullName: 'Site Engineer',
          email: 'site@yorks.test',
          role: UserRole.engineer,
          createdAt: DateTime.utc(2026, 9, 25),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1CompanyMaterialRequestsEnabled: companyEnabled,
        yorksV1Role: YorksV1Role.siteEngineer,
        yorksV1PermissionResolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => capabilityKey == YorksV1CapabilityKeys.materialRequestsView
            ? false
            : legacyAllowed,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      router.go(RoutePaths.yorksV1MaterialRequests);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        companyEnabled
            ? RoutePaths.yorksV1MaterialRequests
            : RoutePaths.engineerHome,
      );
      router.go(
        '${RoutePaths.yorksV1MaterialRequests}?project_id=denied-project',
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets('Accountant Company access never opens scoped Project routes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    for (final companyEnabled in [false, true]) {
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.accountant,
        user: AppUser(
          id: 'company-accountant',
          fullName: 'Accountant',
          email: 'accountant@yorks.test',
          role: UserRole.accountant,
          createdAt: DateTime.utc(2026, 9, 27),
          yorksV1RoleCache: YorksV1Role.accountant,
          yorksV1Roles: const [YorksV1Role.accountant],
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1CompanyMaterialRequestsEnabled: companyEnabled,
        yorksV1Role: YorksV1Role.accountant,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      for (final path in [
        RoutePaths.yorksV1MaterialRequests,
        RoutePaths.yorksV1CompanyMaterialRequestNew,
      ]) {
        router.go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          router.routeInformationProvider.value.uri.path,
          companyEnabled ? path : RoutePaths.engineerHome,
        );
      }
      for (final path in [
        '${RoutePaths.yorksV1MaterialRequests}?project_id=project-1',
        '${RoutePaths.yorksV1MaterialRequests}/new',
        '${RoutePaths.yorksV1MaterialRequests}/project-request-1',
        RoutePaths.yorksV1Projects,
        RoutePaths.yorksV1Inventory,
      ]) {
        router.go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.engineerHome,
          reason: 'Accountant denied $path',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets(
    'eligible V1 actors need independent create and edit capabilities',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final changed = ValueNotifier<int>(0);
      final allowed = <String, bool>{
        YorksV1CapabilityKeys.projectsView: true,
        YorksV1CapabilityKeys.boqView: false,
        YorksV1CapabilityKeys.materialRequestsView: true,
        YorksV1CapabilityKeys.projectsCreate: false,
        YorksV1CapabilityKeys.projectsEdit: false,
        YorksV1CapabilityKeys.materialRequestsCreate: false,
      };
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.engineer,
        user: AppUser(
          id: 'project-engineer-capability-test',
          fullName: 'Project Engineer',
          email: 'project.engineer@yorks.test',
          role: UserRole.engineer,
          createdAt: DateTime.utc(2026, 8, 24),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1BoqEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1Role: YorksV1Role.projectEngineer,
        refreshListenable: changed,
        yorksV1PermissionResolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => allowed[capabilityKey] ?? legacyAllowed,
      );
      addTearDown(() {
        router.dispose();
        changed.dispose();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      Future<void> expectGate(String path, String capabilityKey) async {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.engineerHome,
          reason: '$capabilityKey deny must fail closed',
        );
        allowed[capabilityKey] = true;
        changed.value++;
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          path,
          reason: '$capabilityKey grant should re-enable an eligible actor',
        );
      }

      await expectGate(
        RoutePaths.engineerCreateProject,
        YorksV1CapabilityKeys.projectsCreate,
      );
      await expectGate(
        RoutePaths.yorksV1ProjectEditPath('project-1'),
        YorksV1CapabilityKeys.projectsEdit,
      );
      await expectGate(
        RoutePaths.yorksV1BoqGroupsPath('project-1'),
        YorksV1CapabilityKeys.boqView,
      );
      await expectGate(
        RoutePaths.yorksV1MaterialRequestDraftPath('draft-1'),
        YorksV1CapabilityKeys.materialRequestsCreate,
      );
    },
  );

  testWidgets(
    'personal grants do not bypass non-delegable structural role boundaries',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.procurement,
        user: AppUser(
          id: 'procurement-structural-test',
          fullName: 'Procurement',
          email: 'procurement.structural@yorks.test',
          role: UserRole.procurement,
          createdAt: DateTime.utc(2026, 8, 24),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1BoqEnabled: true,
        yorksV1RequestsEnabled: true,
        yorksV1Role: YorksV1Role.procurement,
        yorksV1PermissionResolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => true,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      for (final path in [
        RoutePaths.engineerCreateProject,
        RoutePaths.yorksV1ProjectEditPath('project-1'),
        RoutePaths.yorksV1MaterialRequestDraftPath('draft-1'),
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.engineerHome,
          reason: 'a capability grant must not widen structural role access',
        );
      }
    },
  );

  testWidgets(
    'pending protected route decision preserves a deep link until refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final changed = ValueNotifier<int>(0);
      bool? permissionsView;
      final targetPath = RoutePaths.yorksV1UserAccessPath('target-app-user');
      final router = createAppRouter(
        isOnboarded: true,
        isLoggedIn: true,
        role: UserRole.admin,
        user: AppUser(
          id: 'cold-start-admin',
          fullName: 'Cold Start Admin',
          email: 'cold.start@yorks.test',
          role: UserRole.admin,
          createdAt: DateTime.utc(2026, 8, 24),
        ),
        yorksV1ProjectsEnabled: true,
        yorksV1Role: YorksV1Role.admin,
        refreshListenable: changed,
        yorksV1PermissionResolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) {
              if (capabilityKey == YorksV1CapabilityKeys.permissionsView) {
                return permissionsView;
              }
              return true;
            },
      );
      addTearDown(() {
        router.dispose();
        changed.dispose();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      router.go(targetPath);
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, targetPath);

      permissionsView = false;
      changed.value++;
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, RoutePaths.users);
    },
  );

  testWidgets(
    'V1 scoped access deep links require a current permissions.view snapshot',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final targetPath = RoutePaths.yorksV1UserAccessPath('target-app-user');

      for (final scenario in [
        (current: false, canView: true),
        (current: true, canView: false),
        (current: true, canView: true),
      ]) {
        final router = createAppRouter(
          isOnboarded: true,
          isLoggedIn: true,
          role: UserRole.admin,
          user: AppUser(
            id: 'permission-route-admin',
            fullName: 'Permission Route Admin',
            email: 'permission-route-admin@yorks.test',
            role: UserRole.admin,
            createdAt: DateTime.utc(2026, 8, 24),
          ),
          yorksV1ProjectsEnabled: true,
          yorksV1Role: YorksV1Role.admin,
          yorksV1PermissionResolver:
              (
                capabilityKey, {
                required legacyAllowed,
                requireWrite = false,
                organizationSummary = false,
                projectId,
              }) {
                if (capabilityKey == YorksV1CapabilityKeys.usersView) {
                  return true;
                }
                return scenario.current &&
                    scenario.canView &&
                    capabilityKey == YorksV1CapabilityKeys.permissionsView;
              },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 5));
        router.go(targetPath);
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          scenario.current && scenario.canView ? targetPath : RoutePaths.users,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );
}

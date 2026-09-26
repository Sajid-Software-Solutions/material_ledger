import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Accounts routes and legacy Finance fail closed while flag is off',
    (tester) async {
      final router = _router(
        userRole: UserRole.admin,
        exactRole: YorksV1Role.admin,
        accountsEnabled: false,
      );
      addTearDown(router.dispose);
      await _mount(tester, router, YorksV1Role.admin);

      await _go(tester, router, RoutePaths.yorksV1Accounts);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      await _go(tester, router, RoutePaths.finance);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );
    },
  );

  testWidgets('legacy Finance converges to the normalized Accounts portfolio', (
    tester,
  ) async {
    final router = _router(
      userRole: UserRole.admin,
      exactRole: YorksV1Role.admin,
      accountsEnabled: true,
    );
    addTearDown(router.dispose);
    await _mount(tester, router, YorksV1Role.admin);

    await _go(tester, router, RoutePaths.finance);
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.yorksV1Accounts,
    );
  });

  testWidgets(
    'Procurement generic project Accounts opens supplier-only route',
    (tester) async {
      final router = _router(
        userRole: UserRole.procurement,
        exactRole: YorksV1Role.procurement,
        accountsEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => capabilityKey == YorksV1CapabilityKeys.viewSupplierCosts,
      );
      addTearDown(router.dispose);
      await _mount(tester, router, YorksV1Role.procurement);

      await _go(
        tester,
        router,
        RoutePaths.yorksV1ProjectAccountsPath('project-1'),
      );
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1ProjectAccountsSupplierBillsPath('project-1'),
      );

      await _go(
        tester,
        router,
        RoutePaths.yorksV1ProjectAccountsInvoicesPath('project-1'),
      );
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );
    },
  );

  testWidgets('Project Accounts deep links stay in the project workspace', (
    tester,
  ) async {
    final router = _router(
      userRole: UserRole.admin,
      exactRole: YorksV1Role.admin,
      accountsEnabled: true,
      resolver:
          (
            capabilityKey, {
            required legacyAllowed,
            requireWrite = false,
            organizationSummary = false,
            projectId,
          }) => capabilityKey == YorksV1CapabilityKeys.viewProjectAccounts,
    );
    addTearDown(router.dispose);
    await _mount(tester, router, YorksV1Role.admin);

    await _go(
      tester,
      router,
      RoutePaths.yorksV1ProjectAccountsOverviewPath('project-1'),
    );

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.yorksV1ProjectAccountsOverviewPath('project-1'),
    );
    expect(find.byType(YorksV1ProjectWorkspaceScreen), findsOneWidget);
  });

  testWidgets(
    'Accountant lands in Accounts and cannot enter unrelated V1 flows',
    (tester) async {
      final router = _router(
        userRole: UserRole.accountant,
        exactRole: YorksV1Role.accountant,
        accountsEnabled: true,
      );
      addTearDown(router.dispose);
      await _mount(tester, router, YorksV1Role.accountant);

      await _go(tester, router, RoutePaths.login);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1Accounts,
      );

      await _go(tester, router, RoutePaths.engineerHome);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1Accounts,
      );

      for (final officePath in const [
        RoutePaths.yorksV1AccountsProjects,
        RoutePaths.yorksV1AccountsBillingProgress,
        RoutePaths.yorksV1AccountsClaims,
        RoutePaths.yorksV1AccountsClientPayments,
        RoutePaths.yorksV1AccountsSupplierBills,
        RoutePaths.yorksV1AccountsDueSchedule,
        RoutePaths.yorksV1AccountsDocuments,
        RoutePaths.yorksV1AccountsReports,
        RoutePaths.yorksV1AccountsActivity,
      ]) {
        await _go(tester, router, officePath);
        expect(router.routeInformationProvider.value.uri.path, officePath);
      }

      await _go(tester, router, RoutePaths.yorksV1MaterialRequests);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1Accounts,
      );
    },
  );

  testWidgets(
    'organization supplier register requires the supplier-cost capability',
    (tester) async {
      final router = _router(
        userRole: UserRole.accountant,
        exactRole: YorksV1Role.accountant,
        accountsEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => capabilityKey == YorksV1CapabilityKeys.viewProjectAccounts,
      );
      addTearDown(router.dispose);
      await _mount(tester, router, YorksV1Role.accountant);

      await _go(tester, router, RoutePaths.yorksV1AccountsSupplierBills);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1Accounts,
      );
    },
  );

  testWidgets(
    'organization supplier register rejects supplier-only authority',
    (tester) async {
      final router = _router(
        userRole: UserRole.accountant,
        exactRole: YorksV1Role.accountant,
        accountsEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => capabilityKey == YorksV1CapabilityKeys.viewSupplierCosts,
      );
      addTearDown(router.dispose);
      await _mount(tester, router, YorksV1Role.accountant);

      await _go(tester, router, RoutePaths.yorksV1AccountsSupplierBills);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );
      expect(find.text('Supplier Bills'), findsNothing);
    },
  );
}

GoRouter _router({
  required UserRole userRole,
  required YorksV1Role exactRole,
  required bool accountsEnabled,
  YorksV1HybridPermissionResolver? resolver,
}) => createAppRouter(
  isOnboarded: true,
  isLoggedIn: true,
  role: userRole,
  user: AppUser(
    id: 'actor-1',
    fullName: 'Accounts Actor',
    email: 'accounts@yorks.test',
    role: userRole,
    yorksV1RoleCache: exactRole,
    yorksV1Roles: [exactRole],
    createdAt: DateTime.utc(2026, 8, 26),
  ),
  yorksV1ProjectsEnabled: true,
  yorksV1BoqEnabled: true,
  yorksV1RequestsEnabled: true,
  yorksV1ArrangementEnabled: true,
  yorksV1LogisticsEnabled: true,
  yorksV1ReturnsDocumentsEnabled: true,
  yorksV1DocumentsEnabled: true,
  yorksV1AccountsEnabled: accountsEnabled,
  yorksV1Role: exactRole,
  yorksV1PermissionResolver: resolver ?? _allowAccounts,
);

bool? _allowAccounts(
  String capabilityKey, {
  required bool legacyAllowed,
  bool requireWrite = false,
  bool organizationSummary = false,
  String? projectId,
}) => _accountsCapabilities.contains(capabilityKey);

const _accountsCapabilities = {
  YorksV1CapabilityKeys.viewProjectAccounts,
  YorksV1CapabilityKeys.viewSupplierCosts,
};

Future<void> _mount(
  WidgetTester tester,
  GoRouter router,
  YorksV1Role role,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appVersionProvider.overrideWithValue(
          const AppVersionInfo(version: '1.0.0', build: 1),
        ),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _go(WidgetTester tester, GoRouter router, String path) async {
  router.go(path);
  await tester.pumpAndSettle();
}

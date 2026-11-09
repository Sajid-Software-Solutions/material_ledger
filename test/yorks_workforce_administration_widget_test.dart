import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/workforce_administration_controller.dart';
import 'package:material_ledger/features/workforce/application/workforce_providers.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/workforce_administration_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_configuration_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_foundation_models.dart';
import 'package:material_ledger/features/workforce/presentation/screens/yorks_workforce_administration_screen.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop administration exposes worker management and history', (
    tester,
  ) async {
    await _pump(tester, const Size(1366, 820));

    expect(find.text('Workforce Administration'), findsOneWidget);
    expect(find.byKey(const Key('workforce-admin-add-worker')), findsOneWidget);
    expect(find.text('Administration Test Worker'), findsOneWidget);
    expect(find.text('Change assignment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new worker keeps optional details out of the quick form', (
    tester,
  ) async {
    await _pump(tester, const Size(360, 800));
    await tester.tap(find.byKey(const Key('workforce-admin-add-worker')));
    await tester.pumpAndSettle();
    expect(find.text('More details (optional)'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(find.byType(ExpansionTile))
          .initiallyExpanded,
      isFalse,
    );
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.text('More details (optional)'));
    await tester.pumpAndSettle();
    expect(
      find.byType(DropdownButtonFormField<YorksWorkforceWorkerType>),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile administration keeps access guidance reachable', (
    tester,
  ) async {
    await _pump(tester, const Size(360, 800));

    await tester.tap(find.byKey(const Key('workforce-admin-access')));
    await tester.pumpAndSettle();

    expect(find.text('Login accounts'), findsOneWidget);
    expect(find.text('Who marks attendance?'), findsOneWidget);
    expect(find.text('History is preserved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Size viewport) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final preferences = await SharedPreferences.getInstance();
  final controller = YorksWorkforceAdministrationController(
    repository: _Repository(),
    commandKeys: YorksV1CriticalCommandKeyStore(
      preferences: preferences,
      actorAuthUserId: 'admin-1',
    ),
    connectivity: const _Connectivity(),
    canManageWorkers: true,
    canManageTeams: true,
    canManageConfiguration: true,
  );
  expect(await controller.load(), isTrue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksWorkforceAdministrationControllerProvider.overrideWith(
          (ref) => controller,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksWorkforceAdministrationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository implements YorksWorkforceRepository {
  @override
  Future<YorksWorkforceFoundationProjection> getFoundation({
    String? query,
    YorksWorkforceWorkerStatus? status,
    int limit = 50,
    int offset = 0,
    String? onDate,
  }) async => YorksWorkforceFoundationProjection.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced_administration',
    'actor_auth_user_id': 'admin-1',
    'on_date': '2026-08-31',
    'server_time': '2026-08-31T12:00:00Z',
    'trades': <Object?>[],
    'teams': <Object?>[],
    'internal_locations': <Object?>[],
    'workers': [
      {
        'worker_id': 'worker-1',
        'worker_number': 'W-001',
        'full_name': 'Administration Test Worker',
        'preferred_display_name': null,
        'designation': 'Technician',
        'trade_id': null,
        'trade_name': null,
        'department': 'Projects',
        'employer_company': 'Yorks AC & Ref.',
        'worker_type': 'yorks_employee',
        'mobile_number': null,
        'joining_date': '2026-01-01',
        'leaving_date': null,
        'current_status': 'active',
        'linked_auth_user_id': null,
        'notes': null,
        'record_version': 1,
        'effective_assignment': <String, Object?>{},
      },
    ],
    'worker_count': 1,
  });

  @override
  Future<YorksWorkforceAdministrationOptions> getAdministrationOptions({
    String? onDate,
  }) async => YorksWorkforceAdministrationOptions.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced_administration',
    'actor_auth_user_id': 'admin-1',
    'on_date': '2026-08-31',
    'server_time': '2026-08-31T12:00:00Z',
    'users': <Object?>[],
    'projects': <Object?>[],
  });

  @override
  Future<YorksWorkforceConfigurationProjection> getConfiguration({
    String? onDate,
  }) async => YorksWorkforceConfigurationProjection.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced_administration',
    'actor_auth_user_id': 'admin-1',
    'on_date': '2026-08-31',
    'server_time': '2026-08-31T12:00:00Z',
    'calendars': <Object?>[],
    'shift_templates': <Object?>[],
    'team_schedule_links': <Object?>[],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connectivity implements ConnectivityService {
  const _Connectivity();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onChange => const Stream<bool>.empty();
}

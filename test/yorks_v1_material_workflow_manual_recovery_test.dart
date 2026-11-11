import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_workflow_command_controller.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_command_outcome.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_workflow_command_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_command_outcome_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/widgets/yorks_v1_material_workflow_recovery_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_document.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'support/yorks_v1_permission_test_support.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var directory = File(Platform.resolvedExecutable).parent;
    for (var level = 0; level < 8; level++) {
      if (directory.path.endsWith('${Platform.pathSeparator}cache')) break;
      directory = directory.parent;
    }
    final bytes = await File(
      '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await Future.wait([font.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'offline then uncertain retry keeps manual recovery on the same key',
    () async {
      final fixture = await _Fixture.create();
      fixture.mutations.offline = true;
      await expectLater(
        fixture.invoke('cancel_material_request'),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(fixture.outcomes.keys, isEmpty);
      fixture.mutations.offline = false;
      await expectLater(
        fixture.invoke('cancel_material_request'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      expect(
        fixture.keys.hasTrackedPendingDispatch('cancel_material_request', 'mr'),
        isTrue,
      );
      expect(
        fixture.keys.hasPendingDispatch('cancel_material_request', 'mr'),
        isTrue,
      );
      fixture.outcomes.online = true;
      final receipt = await fixture.controller.checkCommandStatus(
        _pending('cancel_material_request'),
      );
      expect(receipt!.commandKey, 'original');
      expect(fixture.outcomes.keys, everyElement('original'));
      expect(
        fixture.mutations.calls,
        2,
      ); // One offline preflight, one actual send.
      expect(fixture.mutations.sentKeys, ['original']);
      expect(fixture.keys.pendingKey('cancel_material_request', 'mr'), isNull);
    },
  );

  for (final operation in [
    'cancel_material_request',
    'close_material_request',
    'begin_arrangement',
    'generate_delivery_order',
  ]) {
    test(
      '$operation recovers manually after three failed reads and a restart',
      () async {
        final fixture = await _Fixture.create();
        await expectLater(
          fixture.invoke(operation),
          throwsA(isA<YorksV1CommandOutcomeUnknown>()),
        );
        expect(fixture.outcomes.keys, ['original', 'original', 'original']);
        expect(fixture.mutations.calls, 1);
        expect(
          await fixture.keys.claimAutomaticCheck(
            operation,
            _entity(operation),
            'original',
          ),
          isFalse,
        );
        // A user can still check while the network is down, without reopening a mutation.
        await expectLater(
          fixture.controller.checkCommandStatus(_pending(operation)),
          throwsA(isA<YorksV1CommandOutcomeUnknown>()),
        );
        expect(fixture.outcomes.keys.length, 4);
        fixture.outcomes.online = true;
        final resumed = fixture.reconstruct();
        final receipt = await resumed.checkCommandStatus(_pending(operation));
        expect(receipt!.commandKey, 'original');
        expect(fixture.outcomes.keys, everyElement('original'));
        expect(fixture.mutations.calls, 1);
        expect(fixture.keys.pendingKey(operation, _entity(operation)), isNull);
      },
    );
  }

  test(
    'repeating an action performs manual lookup before comparing changed form input',
    () async {
      final fixture = await _Fixture.create();
      await expectLater(
        fixture.invoke('cancel_material_request'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      fixture.outcomes.online = true;
      await expectLater(
        fixture.controller.cancelMaterialRequest(
          const YorksV1CancelMaterialRequestInput(
            requestId: 'mr',
            expectedVersion: 99,
            reason: 'Changed input after reconnect',
            idempotencyKey: 'new-key-must-not-send',
          ),
        ),
        throwsA(isA<YorksV1CommittedViewUnavailable>()),
      );
      expect(fixture.mutations.calls, 1);
      expect(fixture.outcomes.keys, [
        'original',
        'original',
        'original',
        'original',
      ]);
      expect(fixture.keys.pendingKey('cancel_material_request', 'mr'), isNull);
    },
  );

  test(
    'every tracked action has explicit original-key lookup independent of its auto budget',
    () async {
      var checks = 0;
      for (final operation in const [
        'decide_material_request_approved',
        'decide_material_request_returned',
        'begin_arrangement',
        'save_arrangement',
        'decide_arrangement_approved',
        'decide_arrangement_returned',
        'dispatch_materials',
        'confirm_receipt',
        'cancel_material_request',
        'close_material_request',
        'generate_delivery_order',
      ]) {
        final fixture = await _Fixture.create();
        fixture.outcomes.online = true;
        final entity = _entity(operation);
        await fixture.keys.acquire(
          operation: operation,
          entityId: entity,
          payload: const {'request_id': 'mr'},
          trackSendState: true,
        );
        await fixture.keys.markDispatched(operation, entity, 'original');
        for (var count = 0; count < 3; count++) {
          expect(
            await fixture.keys.claimAutomaticCheck(
              operation,
              entity,
              'original',
            ),
            isTrue,
          );
        }
        final receipt = await fixture.controller.checkCommandStatus(
          _pending(operation),
        );
        expect(receipt!.commandName, _command(operation));
        expect(fixture.keys.pendingKey(operation, entity), isNull);
        checks += fixture.outcomes.keys.length;
        expect(fixture.mutations.calls, 0);
      }
      expect(checks, 11);
    },
  );

  test(
    'manual confirmation is published before a slow optional projection',
    () async {
      final fixture = await _Fixture.create();
      await expectLater(
        fixture.invoke('close_material_request'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      fixture.outcomes.online = true;
      final projection = Completer<Map<String, dynamic>?>();
      fixture.outcomes.projection = () => projection.future;
      final pending = fixture.invoke('close_material_request');
      await Future<void>.delayed(Duration.zero);
      expect(fixture.phases.last, YorksV1CommandPhase.confirmed);
      expect(fixture.keys.pendingKey('close_material_request', 'mr'), isNull);
      projection.completeError(
        TimeoutException('screen projection unavailable'),
      );
      await expectLater(
        pending,
        throwsA(isA<YorksV1CommittedViewUnavailable>()),
      );
      expect(fixture.phases.last, YorksV1CommandPhase.confirmedViewUnavailable);
      expect(fixture.outcomes.keys.length, 4);
      expect(fixture.mutations.calls, 1);
    },
  );

  test(
    'pending panel enumerates all generic leases and excludes prepared Procurement keys',
    () async {
      final fixture = await _Fixture.create();
      const operations = [
        'decide_material_request_approved',
        'decide_material_request_returned',
        'begin_arrangement',
        'save_arrangement',
        'decide_arrangement_approved',
        'decide_arrangement_returned',
        'dispatch_materials',
        'confirm_receipt',
        'cancel_material_request',
        'close_material_request',
        'generate_delivery_order',
      ];
      for (final operation in operations) {
        await fixture.keys.acquire(
          operation: operation,
          entityId: _entity(operation),
          payload: const {'request_id': 'mr'},
          trackSendState: true,
        );
        await fixture.keys.markDispatched(
          operation,
          _entity(operation),
          'original',
        );
      }
      expect(
        fixture.controller
            .pendingCommandsForRequest(
              'mr',
              arrangementIds: ['arrangement'],
              dispatchIds: ['dispatch'],
            )
            .map((entry) => entry.operation),
        unorderedEquals(operations),
      );
      for (final operation in ['save_arrangement', 'dispatch_materials']) {
        await fixture.keys.confirm(
          operation: operation,
          entityId: _entity(operation),
          idempotencyKey: 'original',
        );
        // Existing prepared flow has an opaque key but no generic send marker.
        await fixture.keys.acquire(
          operation: operation,
          entityId: _entity(operation),
          payload: const {},
        );
      }
      expect(
        fixture.controller
            .pendingCommandsForRequest(
              'mr',
              arrangementIds: ['arrangement'],
              dispatchIds: ['dispatch'],
            )
            .map((entry) => entry.operation),
        isNot(contains('save_arrangement')),
      );
      expect(
        fixture.controller
            .pendingCommandsForRequest(
              'mr',
              arrangementIds: ['arrangement'],
              dispatchIds: ['dispatch'],
            )
            .map((entry) => entry.operation),
        isNot(contains('dispatch_materials')),
      );
    },
  );

  test(
    'late manual response cannot confirm under a different authority',
    () async {
      final fixture = await _Fixture.create();
      await expectLater(
        fixture.invoke('close_material_request'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      fixture.outcomes.online = true;
      fixture.outcomes.wait = Completer<void>();
      final check = fixture.controller.checkCommandStatus(
        _pending('close_material_request'),
      );
      fixture.active = false;
      fixture.outcomes.wait!.complete();
      await expectLater(
        check,
        throwsA(
          isA<YorksV1DomainException>().having(
            (e) => e.code,
            'code',
            YorksV1DomainErrorCode.unauthenticated,
          ),
        ),
      );
      expect(
        fixture.keys.pendingKey('close_material_request', 'mr'),
        'original',
      );
    },
  );

  testWidgets(
    'switching away and back clears a stale checking phase and restores manual recovery',
    (tester) async {
      final fixture = await _Fixture.create();
      await expectLater(
        fixture.invoke('cancel_material_request'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      final actor = StateProvider<String?>((ref) => 'actor');
      final role = StateProvider<YorksV1Role?>(
        (ref) => YorksV1Role.procurement,
      );
      final container = ProviderContainer(
        overrides: [
          yorksV1MaterialWorkflowCommandControllerProvider.overrideWithValue(
            fixture.controller,
          ),
          yorksV1AuthUserIdProvider.overrideWith((ref) => ref.watch(actor)),
          yorksV1CurrentRoleProvider.overrideWith((ref) => ref.watch(role)),
        ],
      );
      addTearDown(container.dispose);
      fixture.onPhase = (id, phase) =>
          container.read(yorksV1CommandPhaseProvider(id).notifier).state =
              phase;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: YorksV1MaterialWorkflowRecoveryPanel(
                requestId: 'mr',
                language: AppLanguage.english,
                onConfirmed: () {},
              ),
            ),
          ),
        ),
      );
      container.read(yorksV1CommandPhaseProvider('mr').notifier).state =
          YorksV1CommandPhase.checking;
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('material-command-check-status')),
            )
            .onPressed,
        isNull,
      );
      container.read(actor.notifier).state = 'other-actor';
      await tester.pump();
      container.read(actor.notifier).state = 'actor';
      await tester.pump();
      expect(container.read(yorksV1CommandPhaseProvider('mr')), isNull);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('material-command-check-status')),
            )
            .onPressed,
        isNotNull,
      );
      // An exact-role change also invalidates the presentation phase.
      container.read(yorksV1CommandPhaseProvider('mr').notifier).state =
          YorksV1CommandPhase.checking;
      container.read(role.notifier).state = YorksV1Role.admin;
      await tester.pump();
      expect(container.read(yorksV1CommandPhaseProvider('mr')), isNull);
      fixture.outcomes.online = true;
      await tester.tap(
        find.byKey(const ValueKey('material-command-check-status')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('material-command-recovery')),
        findsNothing,
      );
      expect(fixture.mutations.calls, 1);
    },
  );

  testWidgets(
    'approval manual recovery survives a null phase after an exact-role reset',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var nextKey = 0;
      final fixture = await _Fixture.create(
        uuidFactory: () => nextKey++ == 0 ? 'original' : 'begin-key',
      );
      var arrangementReads = 0;
      await fixture.keys.acquire(
        operation: 'decide_material_request_approved',
        entityId: 'mr',
        payload: const {'request_id': 'mr'},
        trackSendState: true,
      );
      await fixture.keys.markDispatched(
        'decide_material_request_approved',
        'mr',
        'original',
      );
      for (var count = 0; count < 3; count++) {
        await fixture.keys.claimAutomaticCheck(
          'decide_material_request_approved',
          'mr',
          'original',
        );
      }
      final request = YorksV1MaterialRequest(
        id: 'mr',
        projectId: 'project',
        projectReference: 'YRA-1',
        projectName: 'Project',
        scopeId: 'scope',
        scopeName: 'Main',
        state: YorksV1MaterialRequestState.awaitingRequestApproval,
        recordVersion: 1,
        createdAt: DateTime.utc(2026, 10, 15),
        updatedAt: DateTime.utc(2026, 10, 15),
        timing: YorksV1MaterialRequestTiming.normal,
        canDecideRequest: true,
        lines: const [],
      );
      final role = StateProvider<YorksV1Role?>((ref) => YorksV1Role.admin);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          yorksV1MaterialWorkflowCommandControllerProvider.overrideWithValue(
            fixture.controller,
          ),
          yorksV1AuthUserIdProvider.overrideWithValue('actor'),
          yorksV1CurrentRoleProvider.overrideWith((ref) => ref.watch(role)),
          yorksV1FeatureFlagsProvider.overrideWithValue(
            const YorksV1FeatureFlags(
              foundation: true,
              projects: true,
              boq: true,
              excel: true,
              requests: true,
              arrangement: true,
            ),
          ),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(role: YorksV1Role.admin),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'mr',
          ).overrideWith((ref) async => request),
          yorksV1MaterialRequestDocumentProvider('mr').overrideWith(
            (ref) async =>
                YorksV1MaterialRequestDocumentModel.fromRequest(request),
          ),
          yorksV1ArrangementWorkspaceProvider('mr').overrideWith((ref) async {
            arrangementReads++;
            return YorksV1ArrangementWorkspace(
              requestId: 'mr',
              requestState: 'awaiting_request_approval',
              requestRecordVersion: 1,
              canBegin: false,
              canSave: false,
              canDecide: false,
              arrangements: const [],
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      fixture.onPhase = (id, phase) =>
          container.read(yorksV1CommandPhaseProvider(id).notifier).state =
              phase;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const YorksV1MaterialRequestDetailScreen(requestId: 'mr'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light,
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(yorksV1CommandPhaseProvider('mr').notifier).state =
          YorksV1CommandPhase.checking;
      await tester.pump();
      container.read(role.notifier).state = YorksV1Role.projectEngineer;
      await tester.pumpAndSettle();
      expect(container.read(yorksV1CommandPhaseProvider('mr')), isNull);
      final manual = find.byKey(
        const ValueKey('request-decision-check-status'),
      );
      expect(manual, findsOneWidget);
      expect(tester.widget<TextButton>(manual).onPressed, isNotNull);
      final approve = find.widgetWithText(
        FilledButton,
        'Approve for Procurement',
      );
      final returnForChanges = find.widgetWithText(
        OutlinedButton,
        'Return for changes',
      );
      expect(approve, findsOneWidget);
      expect(returnForChanges, findsOneWidget);
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(returnForChanges).onPressed, isNull);
      fixture.outcomes.online = true;
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(fixture.outcomes.keys, ['original']);
      expect(fixture.mutations.calls, 0);
      expect(
        fixture.keys.pendingKey('decide_material_request_approved', 'mr'),
        isNull,
      );
      await tester.pump(const Duration(seconds: 6));
      container.read(role.notifier).state = YorksV1Role.admin;
      await tester.pumpAndSettle();
      final key = await fixture.keys.acquire(
        operation: 'begin_arrangement',
        entityId: 'mr',
        payload: const {'request_id': 'mr'},
        trackSendState: true,
      );
      await fixture.keys.markDispatched('begin_arrangement', 'mr', key);
      container.read(yorksV1CommandPhaseProvider('mr').notifier).state =
          YorksV1CommandPhase.unknown;
      await tester.pumpAndSettle();
      final readsBeforeRecovery = arrangementReads;
      await tester.tap(
        find.byKey(const ValueKey('material-command-check-status')),
      );
      await tester.pumpAndSettle();
      expect(
        arrangementReads,
        greaterThan(readsBeforeRecovery),
        reason:
            'Receipt-only recovery explicitly refreshes this request arrangement',
      );
      expect(fixture.mutations.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1366.0, 360.0]) {
    testWidgets(
      'Check status remains available after exhausted checks ${width.toInt()}',
      (tester) async {
        tester.view.physicalSize = Size(width, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final fixture = await _Fixture.create();
        final container = ProviderContainer(
          overrides: [
            yorksV1MaterialWorkflowCommandControllerProvider.overrideWithValue(
              fixture.controller,
            ),
            yorksV1AuthUserIdProvider.overrideWithValue('actor'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
          ],
        );
        addTearDown(container.dispose);
        fixture.onPhase = (id, phase) =>
            container.read(yorksV1CommandPhaseProvider(id).notifier).state =
                phase;
        var refreshes = 0;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: YorksV1MaterialWorkflowRecoveryPanel(
                      requestId: 'mr',
                      language: AppLanguage.english,
                      onConfirmed: () => refreshes++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('material-command-recovery')),
          findsNothing,
        );
        // Start through the real controller while mounted: phase changes must make
        // the panel appear without a parent setState or a static seeded fixture.
        late Object failure;
        unawaited(
          fixture
              .invoke('cancel_material_request')
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failure = error;
                },
              ),
        );
        await tester.pumpAndSettle();
        expect(failure, isA<YorksV1CommandOutcomeUnknown>());
        expect(find.text('Check status'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('material-command-check-status')),
        );
        await tester.pumpAndSettle();
        expect(fixture.outcomes.keys.length, 4);
        expect(find.text('Check status'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/p0_manual_recovery/status_${width.toInt()}.png',
          ),
        );
        fixture.outcomes.online = true;
        await tester.tap(
          find.byKey(const ValueKey('material-command-check-status')),
        );
        await tester.pumpAndSettle();
        expect(refreshes, 1);
        expect(
          find.byKey(const ValueKey('material-command-recovery')),
          findsNothing,
        );
        expect(fixture.mutations.calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

String _entity(String operation) =>
    operation == 'confirm_receipt' || operation == 'generate_delivery_order'
    ? 'dispatch'
    : operation.startsWith('decide_arrangement') ||
          operation == 'save_arrangement'
    ? 'arrangement'
    : 'mr';
String _command(String operation) =>
    operation.startsWith('decide_material_request')
    ? 'v1_decide_material_request'
    : operation.startsWith('decide_arrangement')
    ? 'v1_decide_arrangement'
    : 'v1_$operation';
YorksV1PendingWorkflowCommand _pending(String operation) =>
    YorksV1PendingWorkflowCommand(
      operation: operation,
      entityId: _entity(operation),
      requestId: 'mr',
    );

class _Fixture {
  _Fixture(this.keys);
  final YorksV1CriticalCommandKeyStore keys;
  final mutations = _Mutations();
  final outcomes = _Outcomes();
  final phases = <YorksV1CommandPhase>[];
  bool active = true;
  void Function(String, YorksV1CommandPhase)? onPhase;
  late final controller = reconstruct();
  static Future<_Fixture> create({String Function()? uuidFactory}) async =>
      _Fixture(
        YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: uuidFactory ?? () => 'original',
        ),
      );
  YorksV1MaterialWorkflowCommandController reconstruct() =>
      YorksV1MaterialWorkflowCommandController(
        materialRequests: mutations,
        arrangements: _Arrangements(mutations),
        logistics: _Logistics(mutations),
        outcomes: outcomes,
        commandKeys: keys,
        delay: (_) async {},
        isCurrentAuthority: () => active,
        onPhase: (id, phase) {
          phases.add(phase);
          onPhase?.call(id, phase);
        },
      );
  Future<Object?> invoke(String operation) => switch (operation) {
    'cancel_material_request' => controller.cancelMaterialRequest(
      const YorksV1CancelMaterialRequestInput(
        requestId: 'mr',
        expectedVersion: 1,
        reason: 'Cancel requested',
        idempotencyKey: 'ignored',
      ),
    ),
    'close_material_request' => controller.closeMaterialRequest(
      const YorksV1CloseMaterialRequestInput(
        requestId: 'mr',
        expectedVersion: 1,
        idempotencyKey: 'ignored',
      ),
    ),
    'begin_arrangement' => controller.beginArrangement(
      const YorksV1BeginArrangementInput(
        requestId: 'mr',
        expectedRequestVersion: 1,
        idempotencyKey: 'ignored',
      ),
    ),
    'generate_delivery_order' => controller.generateDeliveryOrder(
      const YorksV1DeliveryOrderGenerationInput(
        requestId: 'mr',
        dispatchId: 'dispatch',
        expectedRequestVersion: 1,
        expectedDispatchVersion: 1,
        deliveryOrderReference: '',
        idempotencyKey: 'ignored',
      ),
    ),
    _ => throw StateError(operation),
  };
}

class _Mutations implements YorksV1MaterialRequestRepository {
  int calls = 0;
  bool offline = false;
  final sentKeys = <String>[];
  Future<T> lost<T>() async {
    calls++;
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.backendUnavailable,
    );
  }

  @override
  Future<YorksV1MaterialRequest> cancel(
    YorksV1CancelMaterialRequestInput input,
  ) async {
    if (offline) {
      calls++;
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    sentKeys.add(input.idempotencyKey);
    return lost();
  }

  @override
  Future<YorksV1MaterialRequest> close(
    YorksV1CloseMaterialRequestInput input,
  ) => lost();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Arrangements implements YorksV1ArrangementRepository {
  _Arrangements(this.mutations);
  final _Mutations mutations;
  @override
  Future<YorksV1ArrangementWorkspace> begin(
    YorksV1BeginArrangementInput input,
  ) => mutations.lost();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Logistics implements YorksV1LogisticsRepository {
  _Logistics(this.mutations);
  final _Mutations mutations;
  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) => mutations.lost();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Outcomes implements YorksV1CommandOutcomeRepository {
  final keys = <String>[];
  bool online = false;
  Completer<void>? wait;
  Future<Map<String, dynamic>?> Function()? projection;
  @override
  Future<YorksV1WorkflowCommandOutcome> check(
    String command,
    String key,
  ) async {
    keys.add(key);
    await wait?.future;
    if (!online) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return YorksV1WorkflowCommandOutcome(
      confirmed: true,
      receipt: YorksV1CommandReceipt(
        commandName: command,
        commandKey: key,
        entityId: 'mr',
      ),
      loadResponse: projection,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/widgets/yorks_v1_sourcing_progress_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_sourcing_progress_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_sourcing_progress_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_sourcing_progress_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _scope = (requestId: 'request-1', arrangementId: 'arrangement-1');
const _line = YorksV1SourcingLine(
  requestLineId: 'line-1',
  readyQuantity: '2',
  requestedQuantity: '5',
  sourceKind: 'warehouse',
  inventoryItemId: 'inventory-1',
);

Map<String, dynamic> _lineJson({String id = 'line-1'}) => {
  'request_line_id': id,
  'ready_qty': '2.0000',
  'requested_qty': '5.0000',
  'source_kind': 'warehouse',
  'inventory_item_id': 'inventory-1',
  'expected_available_date': '2026-10-15',
};
Map<String, dynamic> _json({
  int revision = 1,
  String request = 'request-1',
  String arrangement = 'arrangement-1',
}) => {
  'request_id': request,
  'arrangement_id': arrangement,
  'revision': revision,
  'is_current': true,
  'updated_at': '2026-10-09T10:30:00Z',
  'updated_by_display_name': 'Procurement user',
  'lines': [_lineJson()],
};
YorksV1SourcingProgress _progress({int revision = 1}) =>
    YorksV1SourcingProgress.fromJson(_json(revision: revision));
Matcher _error(YorksV1DomainErrorCode code) =>
    isA<YorksV1DomainException>().having((error) => error.code, 'code', code);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'strict decoder normalizes decimals and counts lines without adding unlike units',
    () {
      final json = _json();
      json['lines'] = [
        {..._lineJson(), 'ready_qty': '5.0000'},
        {..._lineJson(id: 'line-2'), 'ready_qty': '0'},
        {..._lineJson(id: 'line-3'), 'ready_qty': '0.0001'},
      ];
      final progress = YorksV1SourcingProgress.fromJson(json);
      expect(progress.readyLines, 1);
      expect(progress.waitingLines, 1);
      expect(progress.partialLines, 1);
      expect(progress.lines.first.readyQuantity, '5');
      expect(progress.lines.last.readyQuantity, '0.0001');
      expect(() => progress.lines.clear(), throwsUnsupportedError);
      expect(
        _line.toJson().keys,
        unorderedEquals([
          'request_line_id',
          'ready_qty',
          'source_kind',
          'inventory_item_id',
          'expected_available_date',
        ]),
      );
    },
  );

  for (final patch in <Map<String, dynamic>>[
    {'request_id': ''},
    {'arrangement_id': ' '},
    {'revision': 0},
    {'revision': '1'},
    {'is_current': 'true'},
    {'updated_at': 'not a date'},
    {'updated_by_display_name': 7},
    {'lines': 'wrong shape'},
    {'lines': <Object?>[]},
    {
      'lines': [null],
    },
    {
      'lines': [_lineJson(), _lineJson()],
    },
  ]) {
    test('strict decoder rejects malformed progress $patch', () {
      expect(
        () => YorksV1SourcingProgress.fromJson({..._json(), ...patch}),
        throwsA(_error(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    });
  }

  for (final patch in <Map<String, dynamic>>[
    {'request_line_id': ''},
    {'ready_qty': '-1'},
    {'ready_qty': '5.0001'},
    {'ready_qty': '1.'},
    {'requested_qty': '0'},
    {'source_kind': 'other'},
    {'inventory_item_id': 7},
    {'expected_available_date': 7},
    {'expected_available_date': 'later'},
    {'expected_available_date': '2026-02-31'},
  ]) {
    test('strict decoder rejects malformed sourcing line $patch', () {
      expect(
        () => YorksV1SourcingLine.fromJson({..._lineJson(), ...patch}),
        throwsA(_error(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    });
  }

  test('read-only scope loads latest arrangement but cannot publish', () async {
    final repo = _Repository()..readResult = _progress();
    final controller = YorksV1SourcingProgressController(repo, (
      requestId: 'request-1',
      arrangementId: null,
    ));
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state.progress!.arrangementId, 'arrangement-1');
    expect(
      await controller.save(
        requestVersion: 2,
        arrangementVersion: 1,
        lines: [_line],
      ),
      isFalse,
    );
    expect(repo.keys, isEmpty);
  });

  for (final identity in [
    (request: 'other-request', arrangement: 'arrangement-1'),
    (request: 'request-1', arrangement: 'other-arrangement'),
  ]) {
    test('load rejects cross-scope response $identity', () async {
      final repo = _Repository()
        ..readResult = YorksV1SourcingProgress.fromJson(
          _json(request: identity.request, arrangement: identity.arrangement),
        );
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.state.progress, isNull);
      expect(
        controller.state.error,
        _error(YorksV1DomainErrorCode.unexpectedResponse),
      );
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isFalse,
      );
      expect(repo.keys, isEmpty);
    });
  }

  test(
    'a rejected edit keeps only confirmed progress and never looks saved',
    () async {
      final prior = _progress();
      final pending = Completer<YorksV1SourcingProgress>();
      final repo = _Repository()
        ..readResult = prior
        ..saveHook = (_, _) => pending.future;
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      final save = controller.save(
        requestVersion: 2,
        arrangementVersion: 1,
        lines: [_line],
      );
      expect(controller.state.saving, isTrue);
      expect(controller.state.progress, same(prior));
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isFalse,
      );
      expect(repo.keys, hasLength(1));
      pending.completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      );
      expect(await save, isFalse);
      expect(controller.state.saving, isFalse);
      expect(controller.state.progress, same(prior));
      expect(
        controller.state.error,
        _error(YorksV1DomainErrorCode.invalidInput),
      );
    },
  );

  test(
    'stale revision blocks another edit until refresh confirms current revision',
    () async {
      final repo = _Repository()
        ..readResult = _progress()
        ..saveHook = (_, _) => Future.error(
          const YorksV1DomainException(YorksV1DomainErrorCode.conflict),
        );
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isFalse,
      );
      expect(controller.state.progress!.revision, 1);
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isFalse,
      );
      expect(repo.keys, hasLength(1));
      repo.readResult = _progress(revision: 2);
      repo.saveHook = (_, _) async => _progress(revision: 3);
      await controller.load();
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isTrue,
      );
      expect(repo.payloads.last['expected_revision'], 2);
      expect(controller.state.progress!.revision, 3);
    },
  );

  test('exact retry reuses key and changed payload gets a new key', () async {
    final repo = _Repository()
      ..readResult = _progress()
      ..saveHook = (_, _) => Future.error(
        const YorksV1DomainException(YorksV1DomainErrorCode.backendUnavailable),
      );
    final controller = YorksV1SourcingProgressController(repo, _scope);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.save(
      requestVersion: 2,
      arrangementVersion: 1,
      lines: [_line],
    );
    await controller.save(
      requestVersion: 2,
      arrangementVersion: 1,
      lines: [_line],
    );
    expect(repo.keys[1], repo.keys[0]);
    expect(repo.payloads[1], repo.payloads[0]);
    await controller.save(
      requestVersion: 3,
      arrangementVersion: 1,
      lines: [_line],
    );
    expect(repo.keys[2], isNot(repo.keys[0]));
  });

  test(
    'unauthorized save clears protected prior projection and blocks retry',
    () async {
      final repo = _Repository()
        ..readResult = _progress()
        ..saveHook = (_, _) => Future.error(
          const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
        );
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.save(
        requestVersion: 2,
        arrangementVersion: 1,
        lines: [_line],
      );
      expect(controller.state.progress, isNull);
      expect(
        controller.state.error,
        _error(YorksV1DomainErrorCode.unauthorized),
      );
      await controller.save(
        requestVersion: 2,
        arrangementVersion: 1,
        lines: [_line],
      );
      expect(repo.keys, hasLength(1));
    },
  );

  test(
    'mismatched save response never replaces confirmed data or claims success',
    () async {
      final prior = _progress();
      final repo = _Repository()
        ..readResult = prior
        ..saveHook = (_, _) async =>
            YorksV1SourcingProgress.fromJson(_json(request: 'other'));
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      expect(
        await controller.save(
          requestVersion: 2,
          arrangementVersion: 1,
          lines: [_line],
        ),
        isFalse,
      );
      expect(controller.state.progress, same(prior));
      expect(
        controller.state.error,
        _error(YorksV1DomainErrorCode.unexpectedResponse),
      );
    },
  );

  test('newer read wins when responses arrive out of order', () async {
    final first = Completer<YorksV1SourcingProgress?>();
    final second = Completer<YorksV1SourcingProgress?>();
    var calls = 0;
    final repo = _Repository()
      ..readHook = (_) => calls++ == 0 ? first.future : second.future;
    final controller = YorksV1SourcingProgressController(repo, _scope);
    addTearDown(controller.dispose);
    final oldLoad = controller.load();
    final currentLoad = controller.load();
    second.complete(_progress(revision: 3));
    await currentLoad;
    first.complete(_progress(revision: 1));
    await oldLoad;
    expect(controller.state.progress!.revision, 3);
  });

  test('disposal ignores late read and late save responses', () async {
    final read = Completer<YorksV1SourcingProgress?>();
    final repo = _Repository()..readHook = (_) => read.future;
    final controller = YorksV1SourcingProgressController(repo, _scope);
    final loading = controller.load();
    controller.dispose();
    read.complete(_progress());
    await loading;
    final saving = Completer<YorksV1SourcingProgress>();
    final nextRepo = _Repository()
      ..readResult = _progress()
      ..saveHook = (_, _) => saving.future;
    final next = YorksV1SourcingProgressController(nextRepo, _scope);
    await next.load();
    final pending = next.save(
      requestVersion: 2,
      arrangementVersion: 1,
      lines: [_line],
    );
    next.dispose();
    saving.complete(_progress(revision: 2));
    expect(await pending, isFalse);
  });

  test(
    'identity change clears old projection and ignores old actor response',
    () async {
      final actor = StateProvider<String?>((ref) => 'actor-1');
      final first = Completer<YorksV1SourcingProgress?>();
      final next = Completer<YorksV1SourcingProgress?>();
      var actorRead = 0;
      final repo = _Repository()
        ..readHook = (_) => actorRead++ == 0 ? first.future : next.future;
      final container = ProviderContainer(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWith((ref) => ref.watch(actor)),
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1SourcingProgressRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final provider = yorksV1SourcingProgressProvider(_scope);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      container.read(actor.notifier).state = 'actor-2';
      expect(container.read(provider).progress, isNull);
      await _tick();
      next.complete(_progress(revision: 2));
      await _tick();
      first.complete(_progress(revision: 1));
      await _tick();
      expect(container.read(provider).progress!.revision, 2);
      final calls = repo.readScopes.length;
      container.read(actor.notifier).state = null;
      expect(container.read(provider).progress, isNull);
      await _tick();
      expect(
        repo.readScopes,
        hasLength(calls),
        reason: 'signed-out identity must not read protected data',
      );
    },
  );

  test(
    'explicit denial clears data and fences a late successful response',
    () async {
      final pending = Completer<YorksV1SourcingProgress>();
      final repo = _Repository()
        ..readResult = _progress()
        ..saveHook = (_, _) => pending.future;
      final controller = YorksV1SourcingProgressController(repo, _scope);
      addTearDown(controller.dispose);
      await controller.load();
      final save = controller.save(
        requestVersion: 2,
        arrangementVersion: 1,
        lines: [_line],
      );
      controller.deny();
      expect(controller.state.progress, isNull);
      pending.complete(_progress(revision: 2));
      expect(await save, isFalse);
      expect(controller.state.progress, isNull);
      expect(
        controller.state.error,
        _error(YorksV1DomainErrorCode.unauthorized),
      );
    },
  );

  testWidgets(
    'read-only panel shows confirmed count and optional details at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _Repository()..readResult = _progress();
      await tester.pumpWidget(_panel(repo));
      await tester.pumpAndSettle();
      expect(find.text('0 ready · 1 partly ready · 0 waiting'), findsOneWidget);
      expect(find.text('Update team'), findsNothing);
      expect(find.textContaining('Procurement user'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Access door'), findsOneWidget);
      expect(find.text('Ready now 2 / 5'), findsOneWidget);
      expect(find.text('Expected 2026-10-15'), findsOneWidget);
      expect(repo.keys, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outdated panel cannot imply its quantities are currently ready',
    (tester) async {
      final repo = _Repository()
        ..readResult = YorksV1SourcingProgress.fromJson({
          ..._json(),
          'is_current': false,
        });
      await tester.pumpWidget(_panel(repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('Earlier preparation update'), findsOneWidget);
      expect(find.text('0 ready · 1 partly ready · 0 waiting'), findsNothing);
      expect(find.text('Ready now 2 / 5'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading and read failure do not masquerade as empty or completed progress',
    (tester) async {
      final pending = Completer<YorksV1SourcingProgress?>();
      final repo = _Repository()..readHook = (_) => pending.future;
      var updates = 0;
      await tester.pumpWidget(_panel(repo, onUpdate: () => updates++));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('No preparation update yet'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Update team'))
            .onPressed,
        isNull,
      );
      pending.completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
      );
      await tester.pumpAndSettle();
      expect(find.text('No preparation update yet'), findsNothing);
      expect(
        find.textContaining('Preparation progress is unavailable'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Update team'))
            .onPressed,
        isNull,
      );
      expect(updates, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader polls only online in foreground and pauses on loading or failure',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final online = DefaultConnectivity();
      addTearDown(online.dispose);
      final repo = _Repository()..readResult = _progress();
      final container = _readerContainer(repo, online);
      const scope = (requestId: 'request-1', arrangementId: null);
      final provider = yorksV1SourcingProgressProvider(scope);
      final subscription = container.listen(provider, (_, _) {});
      await tester.pump();
      expect(repo.readScopes, hasLength(1));
      await tester.pump(const Duration(seconds: 59));
      expect(repo.readScopes, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(repo.readScopes, hasLength(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(repo.readScopes, hasLength(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      expect(repo.readScopes, hasLength(3));
      online.setOnline(false);
      await tester.pump(const Duration(minutes: 1));
      expect(repo.readScopes, hasLength(3));
      online.setOnline(true);
      final pending = Completer<YorksV1SourcingProgress?>();
      repo.readHook = (_) => pending.future;
      await tester.pump(const Duration(minutes: 1));
      expect(repo.readScopes, hasLength(4));
      expect(container.read(provider).loading, isTrue);
      expect(
        container.read(provider).progress!.revision,
        1,
        reason: 'routine refresh keeps the confirmed version visible',
      );
      await tester.pump(const Duration(minutes: 2));
      expect(repo.readScopes, hasLength(4));
      pending.complete(_progress(revision: 2));
      await tester.pump();
      expect(container.read(provider).progress!.revision, 2);
      repo.readHook = (_) => Future.error(
        const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(repo.readScopes, hasLength(5));
      expect(container.read(provider).progress, isNull);
      expect(
        container.read(provider).error,
        _error(YorksV1DomainErrorCode.unauthorized),
      );
      await tester.pump(const Duration(minutes: 2));
      expect(repo.readScopes, hasLength(5));
      subscription.close();
      container.dispose();
      await tester.pump(const Duration(minutes: 2));
      expect(repo.readScopes, hasLength(5));
    },
  );

  testWidgets(
    'editing scope never polls its shared revision in the background',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final online = DefaultConnectivity();
      addTearDown(online.dispose);
      final repo = _Repository()..readResult = _progress();
      final container = _readerContainer(repo, online);
      final subscription = container.listen(
        yorksV1SourcingProgressProvider(_scope),
        (_, _) {},
      );
      await tester.pump();
      expect(repo.readScopes, hasLength(1));
      await tester.pump(const Duration(minutes: 4));
      expect(repo.readScopes, hasLength(1));
      subscription.close();
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  test('repository uses only protected read and save RPC contracts', () async {
    final rpc = _Rpc()..result = _json();
    final connectivity = DefaultConnectivity();
    addTearDown(connectivity.dispose);
    final repo = YorksV1SupabaseSourcingProgressRepository(
      connectivity: connectivity,
      rpc: rpc,
    );
    await repo.read(_scope);
    expect(rpc.calls.single.$1, 'v1_get_arrangement_sourcing_progress');
    expect(rpc.calls.single.$2, {
      'p_request_id': 'request-1',
      'p_arrangement_id': 'arrangement-1',
    });
    final payload = {
      'request_id': 'request-1',
      'lines': [_line.toJson()],
    };
    await repo.save(payload, 'command-key');
    expect(rpc.calls.last.$1, 'v1_save_arrangement_sourcing_progress');
    expect(rpc.calls.last.$2, {
      'p_payload': payload,
      'p_idempotency_key': 'command-key',
    });
    rpc.result = null;
    expect(await repo.read(_scope), isNull);
    await expectLater(
      repo.save(payload, 'command-key'),
      throwsA(_error(YorksV1DomainErrorCode.unexpectedResponse)),
    );
  });

  test('offline and missing backend fail before any RPC', () async {
    final rpc = _Rpc();
    final offline = DefaultConnectivity(online: false);
    final online = DefaultConnectivity();
    addTearDown(offline.dispose);
    addTearDown(online.dispose);
    await expectLater(
      YorksV1SupabaseSourcingProgressRepository(
        connectivity: offline,
        rpc: rpc,
      ).read(_scope),
      throwsA(_error(YorksV1DomainErrorCode.offline)),
    );
    await expectLater(
      YorksV1SupabaseSourcingProgressRepository(
        connectivity: online,
      ).read(_scope),
      throwsA(_error(YorksV1DomainErrorCode.backendUnavailable)),
    );
    expect(rpc.calls, isEmpty);
  });

  for (final entry in {
    '42501': YorksV1DomainErrorCode.unauthorized,
    '40001': YorksV1DomainErrorCode.conflict,
    '22023': YorksV1DomainErrorCode.invalidInput,
    'XX000': YorksV1DomainErrorCode.serverRejected,
  }.entries) {
    test(
      'repository maps SQL ${entry.key} without optimistic success',
      () async {
        final rpc = _Rpc()
          ..error = PostgrestException(message: 'Rejected', code: entry.key);
        final online = DefaultConnectivity();
        addTearDown(online.dispose);
        final repo = YorksV1SupabaseSourcingProgressRepository(
          connectivity: online,
          rpc: rpc,
        );
        await expectLater(repo.save({}, 'key'), throwsA(_error(entry.value)));
      },
    );
  }

  testWidgets('repository bounds a stalled protected read', (tester) async {
    final rpc = _Rpc()..pending = Completer<Object?>();
    final online = DefaultConnectivity();
    addTearDown(online.dispose);
    final repo = YorksV1SupabaseSourcingProgressRepository(
      connectivity: online,
      rpc: rpc,
    );
    final result = expectLater(
      repo.read(_scope),
      throwsA(_error(YorksV1DomainErrorCode.backendUnavailable)),
    );
    await tester.pump(const Duration(seconds: 21));
    await result;
  });
}

class _Repository implements YorksV1SourcingProgressRepository {
  YorksV1SourcingProgress? readResult;
  Future<YorksV1SourcingProgress?> Function(YorksV1SourcingScope)? readHook;
  Future<YorksV1SourcingProgress> Function(Map<String, Object?>, String)?
  saveHook;
  final readScopes = <YorksV1SourcingScope>[];
  final payloads = <Map<String, Object?>>[];
  final keys = <String>[];
  @override
  Future<YorksV1SourcingProgress?> read(YorksV1SourcingScope scope) {
    readScopes.add(scope);
    return readHook?.call(scope) ?? Future.value(readResult);
  }

  @override
  Future<YorksV1SourcingProgress> save(
    Map<String, Object?> payload,
    String key,
  ) {
    payloads.add(payload);
    keys.add(key);
    return saveHook?.call(payload, key) ?? Future.value(_progress(revision: 2));
  }
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  Object? result;
  Object? error;
  Completer<Object?>? pending;
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) {
    calls.add((functionName, parameters));
    if (error != null) return Future.error(error!);
    return pending?.future ?? Future.value(result);
  }
}

Widget _panel(_Repository repository, {VoidCallback? onUpdate}) =>
    ProviderScope(
      overrides: [
        yorksV1AuthUserIdProvider.overrideWithValue('actor'),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(),
          ),
        ),
        yorksV1SourcingProgressRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: YorksV1SourcingProgressPanel(
              scope: _scope,
              language: AppLanguage.english,
              itemLabels: const {'line-1': 'Access door'},
              onUpdate: onUpdate,
            ),
          ),
        ),
      ),
    );

ProviderContainer _readerContainer(
  _Repository repository,
  DefaultConnectivity connectivity,
) => ProviderContainer(
  overrides: [
    yorksV1AuthUserIdProvider.overrideWithValue('actor'),
    yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
    yorksV1CurrentPermissionSnapshotProvider.overrideWith(
      (ref) => YorksV1TestPermissionController(
        yorksV1TrustedFeaturePermissionState(),
      ),
    ),
    yorksV1SourcingProgressRepositoryProvider.overrideWithValue(repository),
    connectivityProvider.overrideWithValue(connectivity),
    yorksV1MaterialRequestRealtimeRevisionProvider.overrideWith(
      (ref) => YorksV1MaterialRequestRealtimeNotifier(
        enabled: false,
        authUserId: null,
        client: null,
      ),
    ),
  ],
);

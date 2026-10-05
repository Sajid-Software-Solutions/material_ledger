import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_reference_advisory_repository.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  test(
    'normalization preserves leading zeroes and excludes edit identity',
    () async {
      final client = _DataClient()..immediateResult = true;
      final repository = YorksV1ProjectReferenceAdvisoryRepository(
        dataClient: client,
      );
      expect(
        await repository.check(
          reference: '  yra-00017  ',
          projectId: ' edit-id ',
        ),
        YorksV1ProjectReferenceAdvisory.duplicateVisible,
      );
      expect(client.calls.single.reference, 'YRA-00017');
      expect(client.calls.single.projectId, 'edit-id');
    },
  );

  test('no visible match reports accessible scope only', () async {
    final client = _DataClient()..immediateResult = false;
    expect(
      await YorksV1ProjectReferenceAdvisoryRepository(
        dataClient: client,
      ).check(reference: '003', projectId: ''),
      YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope,
    );
    expect(client.calls.single.reference, '003');
    expect(client.calls.single.projectId, isNull);
  });

  test('blank, absent backend and read failure return unavailable', () async {
    final client = _DataClient()..failure = StateError('Denied');
    final repository = YorksV1ProjectReferenceAdvisoryRepository(
      dataClient: client,
    );
    expect(
      await repository.check(reference: ' '),
      YorksV1ProjectReferenceAdvisory.unavailable,
    );
    expect(client.calls, isEmpty);
    expect(
      await repository.check(reference: 'YRA-001'),
      YorksV1ProjectReferenceAdvisory.unavailable,
    );
    expect(
      await const YorksV1ProjectReferenceAdvisoryRepository().check(
        reference: 'YRA-001',
      ),
      YorksV1ProjectReferenceAdvisory.unavailable,
    );
  });

  testWidgets('350ms debounce cancels replaced reference before read', (
    tester,
  ) async {
    final client = _DataClient()..immediateResult = false;
    final container = _container(client);
    addTearDown(container.dispose);
    final first = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider((
        reference: 'YRA-01',
        projectId: null,
      )),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(client.calls, isEmpty);
    first.close();
    await tester.pump(const Duration(milliseconds: 1));
    final next = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider((
        reference: 'YRA-002',
        projectId: null,
      )),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(client.calls.single.reference, 'YRA-002');
    expect(
      container
          .read(
            yorksV1ProjectReferenceAdvisoryProvider((
              reference: 'YRA-002',
              projectId: null,
            )),
          )
          .valueOrNull,
      YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope,
    );
    next.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('late disposed response cannot replace current reference', (
    tester,
  ) async {
    final client = _DataClient();
    final container = _container(client);
    addTearDown(container.dispose);
    final first = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider((
        reference: 'YRA-01',
        projectId: null,
      )),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    first.close();
    await tester.pump(const Duration(milliseconds: 1));
    final next = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider((
        reference: 'YRA-002',
        projectId: null,
      )),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    client.pending[1].complete(false);
    await tester.pump();
    client.pending[0].complete(true);
    await tester.pump();
    expect(
      container
          .read(
            yorksV1ProjectReferenceAdvisoryProvider((
              reference: 'YRA-002',
              projectId: null,
            )),
          )
          .valueOrNull,
      YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope,
    );
    next.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('exact role revocation cancels pending authority response', (
    tester,
  ) async {
    final client = _DataClient();
    final container = _container(client);
    addTearDown(container.dispose);
    const query = (reference: 'YRA-01', projectId: null);
    final subscription = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider(query),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    container.read(_role.notifier).state = YorksV1Role.procurement;
    await tester.pump(const Duration(milliseconds: 1));
    client.pending.single.complete(true);
    await tester.pump();
    expect(
      container
          .read(yorksV1ProjectReferenceAdvisoryProvider(query))
          .valueOrNull,
      YorksV1ProjectReferenceAdvisory.unavailable,
    );
    expect(client.calls, hasLength(1));
    subscription.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('permission revision rechecks and ignores the retired response', (
    tester,
  ) async {
    final client = _DataClient();
    final container = _container(client);
    addTearDown(container.dispose);
    const query = (reference: 'YRA-01', projectId: null);
    final subscription = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider(query),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    container.read(_revision.notifier).state = 2;
    await tester.pump(const Duration(milliseconds: 1));
    client.pending[0].complete(true);
    await tester.pump();
    expect(
      container.read(yorksV1ProjectReferenceAdvisoryProvider(query)).isLoading,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(client.calls, hasLength(2));
    client.pending[1].complete(false);
    await tester.pump();
    expect(
      container
          .read(yorksV1ProjectReferenceAdvisoryProvider(query))
          .valueOrNull,
      YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope,
    );
    subscription.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('sign-out discards a pending signed-in response', (tester) async {
    final client = _DataClient();
    final container = _container(client);
    addTearDown(container.dispose);
    const query = (reference: 'YRA-01', projectId: null);
    final subscription = container.listen(
      yorksV1ProjectReferenceAdvisoryProvider(query),
      (_, _) {},
    );
    await tester.pump(const Duration(milliseconds: 350));
    container.read(_owner.notifier).state = null;
    await tester.pump(const Duration(milliseconds: 1));
    client.pending.single.complete(true);
    await tester.pump();
    expect(
      container
          .read(yorksV1ProjectReferenceAdvisoryProvider(query))
          .valueOrNull,
      YorksV1ProjectReferenceAdvisory.unavailable,
    );
    expect(client.calls, hasLength(1));
    subscription.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final _role = StateProvider<YorksV1Role>((ref) => YorksV1Role.projectEngineer);
final _owner = StateProvider<String?>((ref) => 'auth-user');
final _revision = StateProvider<int>((ref) => 1);

ProviderContainer _container(_DataClient client) => ProviderContainer(
  overrides: [
    yorksV1ProjectReferenceAdvisoryDataClientProvider.overrideWithValue(client),
    yorksV1AuthUserIdProvider.overrideWith((ref) => ref.watch(_owner)),
    yorksV1CurrentRoleProvider.overrideWith((ref) => ref.watch(_role)),
    yorksV1CurrentPermissionSnapshotProvider.overrideWith(
      (ref) => YorksV1TestPermissionController(
        _permissionState(ref.watch(_revision)),
      ),
    ),
  ],
);

YorksV1CurrentPermissionSnapshotState _permissionState(int revision) {
  final state = yorksV1TrustedFeaturePermissionState();
  final original = state.snapshot!;
  return state.copyWith(
    snapshot: YorksV1CurrentPermissionSnapshot(
      schemaVersion: original.schemaVersion,
      authorizationMode: original.authorizationMode,
      generatedAt: original.generatedAt,
      user: original.user,
      revision: revision,
      capabilities: original.capabilities,
      projectAccess: original.projectAccess,
    ),
  );
}

class _DataClient implements YorksV1ProjectReferenceAdvisoryDataClient {
  bool? immediateResult;
  Object? failure;
  final calls = <YorksV1ProjectReferenceAdvisoryQuery>[];
  final pending = <Completer<bool>>[];

  @override
  Future<bool> hasVisibleActiveReference({
    required String normalizedReference,
    String? excludingProjectId,
  }) async {
    calls.add((reference: normalizedReference, projectId: excludingProjectId));
    if (failure != null) throw failure!;
    if (immediateResult != null) return immediateResult!;
    final result = Completer<bool>();
    pending.add(result);
    return result.future;
  }
}

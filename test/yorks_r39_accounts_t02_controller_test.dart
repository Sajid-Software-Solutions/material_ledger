import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_controller.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_models.dart';
import 'package:material_ledger/features/accounts/presentation/widgets/yorks_accounts_progress_action_sheet.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('original save recovery is reachable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository(failFirstSuggest: true);
      final controller = await _controller(repository);
      await controller.suggestProgress(_progressInput());
      final projection = _protectedProgress();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksAccountsProjectControllerProvider(
              'project-1',
            ).overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () => showYorksAccountsProgressActionSheet(
                      context,
                      projectId: 'project-1',
                      entry: projection.progress.single,
                      projection: projection,
                      language: AppLanguage.english,
                    ),
                    child: const Text('Open fixture'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open fixture'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Check original save'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Check original save'));
      await tester.pumpAndSettle();
      expect(repository.commandKeys, hasLength(2));
      expect(repository.commandKeys.first, repository.commandKeys.last);
      expect(find.text('Check original save'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('denial purges the entire previously authorized projection', () async {
    final repository = _Repository();
    final controller = await _controller(repository);
    expect(await controller.load(), isTrue);
    expect(controller.state.hasProtectedValues, isTrue);

    repository.readError = const YorksV1DomainException(
      YorksV1DomainErrorCode.unauthorized,
    );
    expect(await controller.load(), isFalse);

    expect(controller.state.status, YorksAccountsViewStatus.forbidden);
    expect(controller.state.hasProtectedValues, isFalse);
    expect(controller.state.baseline, isNull);
    expect(controller.state.progress, isNull);
  });

  test(
    'value downgrade purge keeps base facts but disables stale actions',
    () async {
      final controller = await _controller(_Repository());
      await controller.load();

      controller.purgeProtectedValues();

      expect(controller.state.baseline, isNotNull);
      expect(controller.state.progress, isNotNull);
      expect(controller.state.hasProtectedValues, isFalse);
      expect(controller.state.baseline!.capabilities.canConfigure, isFalse);
      expect(controller.state.baseline!.capabilities.canSuggest, isFalse);
      expect(controller.state.progress!.capabilities.canConfirm, isFalse);
      expect(controller.state.progress!.capabilities.canReview, isFalse);
    },
  );

  test('mid-load value downgrade cannot retain baseline money', () async {
    final controller = await _controller(
      _Repository(downgradeProgressValues: true),
    );

    expect(await controller.load(), isTrue);
    expect(controller.state.status, YorksAccountsViewStatus.success);
    expect(controller.state.hasProtectedValues, isFalse);
    expect(controller.state.baseline!.baseline!.contractValue, isNull);
    expect(controller.state.progress!.totals!.contractValue, isNull);
    expect(controller.state.baseline!.capabilities.canConfigure, isFalse);
    expect(controller.state.progress!.capabilities.canConfirm, isFalse);
  });

  test(
    'authorized action-only engineer retains progress commands without money',
    () async {
      final controller = await _controller(_Repository(actionOnly: true));
      expect(await controller.load(), isTrue);
      expect(controller.state.hasProtectedValues, isFalse);
      expect(controller.state.baseline!.baseline!.contractValue, isNull);
      expect(controller.state.progress!.totals!.contractValue, isNull);
      expect(controller.state.progress!.capabilities.canSuggest, isTrue);
      expect(
        controller.state.progress!.commands.allows('suggest_progress'),
        isTrue,
      );
    },
  );

  test(
    'lost command response is uncertain and retries with same key',
    () async {
      final repository = _Repository(failFirstSuggest: true);
      final controller = await _controller(repository);
      final input = _progressInput();

      expect(await controller.suggestProgress(input), isNull);
      expect(controller.state.status, YorksAccountsViewStatus.uncertain);
      expect(repository.commandKeys, hasLength(1));

      final result = await controller.suggestProgress(input);
      expect(result, isNotNull);
      expect(repository.commandKeys, hasLength(2));
      expect(repository.commandKeys[1], repository.commandKeys[0]);
      expect(controller.state.status, YorksAccountsViewStatus.success);
    },
  );

  test(
    'different payload cannot replace an uncertain command intent',
    () async {
      final repository = _Repository(failEverySuggest: true);
      final controller = await _controller(repository);

      await controller.suggestProgress(_progressInput(percent: '25'));
      await controller.suggestProgress(_progressInput(percent: '30'));

      expect(repository.commandKeys, hasLength(1));
      expect(controller.state.hasPendingCommand, isTrue);
      await controller.reconcilePendingCommand();
      expect(repository.commandKeys, hasLength(2));
      expect(repository.commandKeys[0], repository.commandKeys[1]);
    },
  );

  test('concurrent clicks invoke the repository once', () async {
    final repository = _Repository();
    final controller = await _controller(repository);
    final first = controller.suggestProgress(_progressInput());
    final duplicate = controller.suggestProgress(_progressInput());
    expect(await duplicate, isNull);
    expect(await first, isNotNull);
    expect(repository.commandKeys, hasLength(1));
  });

  test(
    'successful progress action refreshes the active workbench filters',
    () async {
      final repository = _Repository();
      final controller = await _controller(repository);
      await controller.load(
        buildingScopeId: 'building-1',
        stageKey: 'material_supply',
        actionOwner: 'site_engineer',
        hasEvidence: true,
      );
      expect(await controller.suggestProgress(_progressInput()), isNotNull);
      expect(repository.progressReads, hasLength(2));
      expect(repository.progressReads.last, repository.progressReads.first);
      expect(repository.progressReads.last.buildingScopeId, 'building-1');
      expect(repository.progressReads.last.stageKey, 'material_supply');
    },
  );

  test('refresh does not resolve an unknown command outcome', () async {
    final repository = _Repository(failFirstSuggest: true);
    final controller = await _controller(repository);
    await controller.suggestProgress(_progressInput());
    await controller.load();
    expect(controller.state.status, YorksAccountsViewStatus.uncertain);
    expect(controller.state.hasPendingCommand, isTrue);
    expect(await controller.reconcilePendingCommand(), isNotNull);
    expect(repository.commandKeys[0], repository.commandKeys[1]);
    expect(controller.state.hasPendingCommand, isFalse);
  });

  test('revocation clears pending intent and protected projections', () async {
    final repository = _Repository(failFirstSuggest: true);
    final controller = await _controller(repository);
    await controller.suggestProgress(_progressInput());
    repository.readError = const YorksV1DomainException(
      YorksV1DomainErrorCode.unauthorized,
    );
    await controller.load();
    expect(controller.state.hasPendingCommand, isFalse);
    expect(controller.state.progress, isNull);
    expect(await controller.reconcilePendingCommand(), isNull);
    expect(repository.commandKeys, hasLength(1));
  });

  test(
    'project-scoped controller rejects cross-project command intent',
    () async {
      final repository = _Repository();
      final controller = await _controller(repository);
      final input = YorksAccountsProgressInput(
        projectId: 'project-2',
        progressEntryId: 'progress-1',
        expectedVersion: 1,
        percent: YorksAccountsDecimal.parse('25'),
        evidenceSummary: 'Inspection',
        evidenceDocumentIds: const ['document-1'],
        reason: 'Site progress',
      );

      expect(await controller.suggestProgress(input), isNull);
      expect(repository.commandKeys, isEmpty);
      expect(controller.state.status, YorksAccountsViewStatus.failure);
      expect(controller.state.error?.code, YorksV1DomainErrorCode.invalidInput);
    },
  );

  test('loads typed append-only revision history through controller', () async {
    final controller = await _controller(_Repository());

    expect(await controller.loadRevisionHistory('progress-1'), isTrue);
    expect(controller.state.revisionHistory!.revisions, hasLength(1));
    expect(
      controller.state.revisionHistory!.revisions.single.revisionNumber,
      1,
    );
  });

  test('maps offline, conflict, session expiry and disabled states', () async {
    final cases = <YorksV1DomainErrorCode, YorksAccountsViewStatus>{
      YorksV1DomainErrorCode.offline: YorksAccountsViewStatus.offline,
      YorksV1DomainErrorCode.conflict: YorksAccountsViewStatus.conflict,
      YorksV1DomainErrorCode.unauthenticated:
          YorksAccountsViewStatus.sessionExpired,
      YorksV1DomainErrorCode.featureDisabled:
          YorksAccountsViewStatus.unavailable,
    };
    for (final entry in cases.entries) {
      final repository = _Repository()
        ..readError = YorksV1DomainException(entry.key);
      final controller = await _controller(repository);
      expect(await controller.load(), isFalse);
      expect(controller.state.status, entry.value);
    }
  });

  test(
    'permission revision rebuilds and purges protected provider state',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _Repository();
      final epoch = StateProvider<YorksAccountsPermissionEpoch>(
        (ref) => (
          revision: 1,
          trusted: true,
          stale: false,
          revisionSignalHealthy: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1AuthUserIdProvider.overrideWithValue('actor-1'),
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.accountant),
          yorksAccountsRepositoryProvider.overrideWithValue(repository),
          yorksAccountsPermissionEpochProvider.overrideWith(
            (ref) => ref.watch(epoch),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = yorksAccountsProjectControllerProvider('project-1');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final original = container.read(provider.notifier);
      await original.load();
      expect(container.read(provider).hasProtectedValues, isTrue);

      container.read(epoch.notifier).state = (
        revision: 2,
        trusted: false,
        stale: true,
        revisionSignalHealthy: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(provider.notifier), isNot(same(original)));
      expect(container.read(provider).hasProtectedValues, isFalse);
      expect(container.read(provider).status, YorksAccountsViewStatus.idle);
    },
  );
}

Future<YorksAccountsProjectController> _controller(
  _Repository repository,
) async {
  return YorksAccountsProjectController(
    projectId: 'project-1',
    repository: repository,
    commandKeys: YorksV1CriticalCommandKeyStore(
      preferences: await SharedPreferences.getInstance(),
      actorAuthUserId: 'actor-1',
    ),
  );
}

YorksAccountsProgressInput _progressInput({String percent = '25'}) =>
    YorksAccountsProgressInput(
      projectId: 'project-1',
      progressEntryId: 'progress-1',
      expectedVersion: 1,
      percent: YorksAccountsDecimal.parse(percent),
      evidenceSummary: 'Inspection complete',
      evidenceDocumentIds: const ['document-1'],
      reason: 'Site progress',
    );

final class _Repository implements YorksAccountsRepository {
  _Repository({
    this.failFirstSuggest = false,
    this.failEverySuggest = false,
    this.downgradeProgressValues = false,
    this.actionOnly = false,
  });

  final bool failFirstSuggest;
  final bool failEverySuggest;
  final bool downgradeProgressValues;
  final bool actionOnly;
  YorksV1DomainException? readError;
  final List<String> commandKeys = [];
  final List<
    ({
      String? buildingScopeId,
      String? stageKey,
      String? actionOwner,
      bool? hasEvidence,
    })
  >
  progressReads = [];

  @override
  Future<YorksAccountsBaselineProjection> getBaseline(String projectId) async {
    if (readError case final error?) throw error;
    return actionOnly ? _actionOnlyBaseline() : _protectedBaseline();
  }

  @override
  Future<YorksAccountsProgressProjection> listProgress(
    String projectId, {
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async {
    if (readError case final error?) throw error;
    progressReads.add((
      buildingScopeId: buildingScopeId,
      stageKey: stageKey,
      actionOwner: actionOwner,
      hasEvidence: hasEvidence,
    ));
    final progress = _protectedProgress();
    return actionOnly
        ? _actionOnlyProgress()
        : downgradeProgressValues
        ? progress.withoutProtectedValues()
        : progress;
  }

  @override
  Future<YorksAccountsProgressRevisionProjection> listProgressRevisions(
    String projectId,
    String progressEntryId, {
    int? beforeRevisionNumber,
    int limit = 50,
  }) async => YorksAccountsProgressRevisionProjection.fromRpcJson({
    'schema_version': 2,
    'project_id': projectId,
    'progress_entry_id': progressEntryId,
    'revisions': [
      {
        'revision_id': 'revision-1',
        'revision_number': 1,
        'action': 'suggested',
        'previous_suggested_percent': '0.0000',
        'new_suggested_percent': '20.0000',
        'previous_confirmed_percent': '0.0000',
        'new_confirmed_percent': '0.0000',
        'previous_review_status': 'not_required',
        'new_review_status': 'not_required',
        'evidence_summary': 'Inspection',
        'evidence_document_ids': ['document-1'],
        'reason': 'Site progress',
        'actor_auth_user_id': 'actor-1',
        'actor_role': 'engineer',
        'actor_exact_role': 'site_engineer',
        'occurred_at': '2026-08-25T12:00:00Z',
      },
    ],
    'next_cursor': null,
    'capabilities': _capabilities(),
  });

  @override
  Future<YorksAccountsCommandResult> suggestProgress(
    YorksAccountsProgressInput input, {
    required String idempotencyKey,
  }) async {
    commandKeys.add(idempotencyKey);
    if (failEverySuggest || (failFirstSuggest && commandKeys.length == 1)) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return _result();
  }

  @override
  Future<YorksAccountsCommandResult> confirmProgress(
    YorksAccountsProgressInput input, {
    required String idempotencyKey,
  }) async => _result();

  @override
  Future<YorksAccountsCommandResult> initializeBaseline(
    YorksAccountsBaselineInput input, {
    required String idempotencyKey,
  }) async => _result();

  @override
  Future<YorksAccountsCommandResult> reviseBaseline(
    YorksAccountsBaselineInput input, {
    required String idempotencyKey,
  }) async => _result();

  @override
  Future<YorksAccountsCommandResult> reviewProgress(
    YorksAccountsReviewInput input, {
    required String idempotencyKey,
  }) async => _result();
}

YorksAccountsBaselineProjection _protectedBaseline() =>
    YorksAccountsBaselineProjection.fromRpcJson({
      'schema_version': 2,
      'project_id': 'project-1',
      'baseline': {
        'revision_id': 'revision-1',
        'revision_number': 1,
        'record_version': 1,
        'status': 'current',
        'contract_value': '8400000.00',
        'currency_code': 'AED',
        'vat_rate': '5.0000',
        'payment_terms_days': 20,
        'reminder_lead_days': 10,
        'management_review_policy': <String, Object?>{
          'always_required': false,
          'threshold_amount': null,
          'confirming_exact_roles': <String>[],
        },
      },
      'building_allocations': <Object?>[],
      'stage_allocations': <Object?>[],
      'capabilities': _capabilities(),
      'commands': <String, bool>{},
    });

YorksAccountsProgressProjection _protectedProgress() =>
    YorksAccountsProgressProjection.fromRpcJson({
      'schema_version': 2,
      'project_id': 'project-1',
      'baseline_revision_id': 'revision-1',
      'baseline_revision_number': 1,
      'progress': [
        {
          'progress_entry_id': 'progress-1',
          'project_id': 'project-1',
          'baseline_revision_id': 'revision-1',
          'building_scope_id': 'building-1',
          'stage_key': 'design',
          'stage_position': 1,
          'record_version': 1,
          'suggested_percent': '20.0000',
          'confirmed_percent': '10.0000',
          'review_status': 'not_required',
          'evidence_document_ids': <Object?>[],
          'action_owner': 'project_engineer',
          'revisions': <Object?>[],
          'next_actions': <Object?>[],
          'stage_value': '840000.00',
          'confirmed_eligible': '84000.00',
          'previously_claimed_amount': '0.00',
          'available_to_claim': '84000.00',
        },
      ],
      'totals': {
        'confirmed_percent': '10.0000',
        'contract_value': '8400000.00',
        'confirmed_eligible': '84000.00',
        'available_to_claim': '84000.00',
      },
      'capabilities': _capabilities(),
      'commands': <String, bool>{},
      'next_actions': <Object?>[],
    });

const _actionOnlyCapabilities = YorksAccountsCapabilities(
  canView: true,
  canViewValues: false,
  canConfigure: false,
  canSuggest: true,
  canConfirm: false,
  canReview: false,
);

YorksAccountsBaselineProjection _actionOnlyBaseline() {
  final safe = _protectedBaseline().withoutProtectedValues();
  return YorksAccountsBaselineProjection(
    schemaVersion: safe.schemaVersion,
    projectId: safe.projectId,
    baseline: safe.baseline,
    physicalBuildings: safe.physicalBuildings,
    stageTemplates: safe.stageTemplates,
    buildingAllocations: safe.buildingAllocations,
    stageAllocations: safe.stageAllocations,
    capabilities: _actionOnlyCapabilities,
    commands: YorksAccountsCommandAvailability.fromRpcJson(const {}),
  );
}

YorksAccountsProgressProjection _actionOnlyProgress() {
  final safe = _protectedProgress().withoutProtectedValues();
  return YorksAccountsProgressProjection(
    schemaVersion: safe.schemaVersion,
    projectId: safe.projectId,
    baselineRevisionId: safe.baselineRevisionId,
    baselineRevisionNumber: safe.baselineRevisionNumber,
    progress: safe.progress,
    totals: safe.totals,
    capabilities: _actionOnlyCapabilities,
    commands: YorksAccountsCommandAvailability.fromRpcJson(const {
      'suggest_progress': true,
    }),
    nextActions: safe.nextActions,
  );
}

Map<String, dynamic> _capabilities() => {
  'can_view': true,
  'can_view_values': true,
  'can_configure': true,
  'can_suggest': true,
  'can_confirm': true,
  'can_review': true,
};

YorksAccountsCommandResult _result() => YorksAccountsCommandResult.fromRpcJson({
  'replayed': false,
  'project_id': 'project-1',
  'entity_id': 'progress-1',
  'record_version': 2,
  'status': 'confirmed',
  'updated_at': '2026-08-25T12:00:00Z',
});

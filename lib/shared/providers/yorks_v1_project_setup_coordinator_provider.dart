import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../controllers/yorks_v1_project_setup_coordinator.dart';
import '../models/yorks_v1_project_setup_operation.dart';
import '../models/yorks_v1_project_creation_draft.dart';
import '../repositories/yorks_v1_project_repository.dart';
import '../repositories/yorks_v1_project_setup_journal_store.dart';
import '../repositories/yorks_v1_project_creation_draft_catalogue.dart';
import '../controllers/yorks_v1_project_creation_draft_controller.dart';
import '../services/analytics_service.dart';
import 'yorks_v1_project_creation_draft_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_project_repository_provider.dart';

final yorksV1ProjectReviewedCommandRepositoryProvider =
    Provider<YorksV1ProjectReviewedCommandRepository>((ref) {
      final repository = ref.watch(yorksV1ProjectRepositoryProvider);
      if (repository is YorksV1ProjectReviewedCommandRepository) {
        return repository as YorksV1ProjectReviewedCommandRepository;
      }
      throw StateError('Project repository does not support reviewed intents');
    });

typedef YorksV1ProjectSetupScope = ({
  String ownerAuthUserId,
  String draftId,
  String? projectId,
});

final yorksV1ProjectSetupCoordinatorProvider =
    StateNotifierProvider.family<
      YorksV1ProjectSetupCoordinator,
      YorksV1ProjectSetupState,
      YorksV1ProjectSetupScope
    >((ref, scope) => _coordinator(ref, scope));

/// Only the explicit original-slot recovery route follows its historical
/// pointer. Ordinary Create/Resume always reads the selected exact journal.
final yorksV1ProjectLegacyRecoveryCoordinatorProvider =
    StateNotifierProvider.family<
      YorksV1ProjectSetupCoordinator,
      YorksV1ProjectSetupState,
      YorksV1ProjectSetupScope
    >((ref, scope) => _coordinator(ref, scope, legacyRecovery: true));

YorksV1ProjectSetupCoordinator _coordinator(
  Ref ref,
  YorksV1ProjectSetupScope scope, {
  bool legacyRecovery = false,
}) {
  final YorksV1ProjectCreationDraftController draftController;
  if (scope.projectId != null) {
    if (legacyRecovery) {
      throw StateError('Creation recovery cannot edit a project');
    }
    draftController = ref.watch(
      yorksV1ProjectEditDraftProvider(
        YorksV1ProjectEditDraftContext(
          ownerAuthUserId: scope.ownerAuthUserId,
          projectId: scope.projectId!,
        ),
      ).notifier,
    );
  } else if (legacyRecovery) {
    draftController = ref.watch(
      yorksV1ProjectLegacyRecoveryDraftControllerProvider(
        scope.ownerAuthUserId,
      ),
    );
  } else {
    final legacy = yorksV1ProjectSetupCreationDraftProvider(
      scope.ownerAuthUserId,
    );
    final useCurrentLegacy =
        ref.exists(legacy) && ref.read(legacy).draftId == scope.draftId;
    final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
    final storage = ref.watch(yorksV1ProjectDraftAtomicStorageProvider);
    final catalogue = YorksV1ProjectCreationDraftCatalogue(
      scopeKey: yorksV1ProjectDraftStorageKey(
        backendIdentity: backend,
        ownerAuthUserId: scope.ownerAuthUserId,
        mode: YorksV1ProjectDraftMode.create,
      ),
      ownerAuthUserId: scope.ownerAuthUserId,
      backendIdentity: backend,
    );
    var completedFollowUp = false;
    try {
      final key = catalogue.resolveRecordKey(storage.read, scope.draftId);
      final raw = storage.read(key);
      var missingOrRetired = raw == null;
      if (raw != null) {
        final record = jsonDecode(raw) as Map;
        final draft = YorksV1ProjectCreationDraft.fromJson(
          Map<String, dynamic>.from(record['draft'] as Map),
        );
        missingOrRetired =
            record['recordVersion'] == 1 &&
            record['retired'] == true &&
            draft.ownerAuthUserId == scope.ownerAuthUserId &&
            draft.backendIdentity == backend &&
            draft.mode == YorksV1ProjectDraftMode.create &&
            draft.projectId == null &&
            draft.draftId == scope.draftId;
      }
      if (missingOrRetired) {
        final original = YorksV1ProjectSetupJournalStore(
          storage: storage,
          journalKey: '${catalogue.scopeKey}:journal:${scope.draftId}',
          backendIdentity: backend,
          ownerAuthUserId: scope.ownerAuthUserId,
          draftId: scope.draftId,
          expectedMode: YorksV1ProjectSetupMode.create,
          atomicOwned: <T>(_) => throw StateError('Read-only intent check'),
        ).read();
        completedFollowUp = original?.coreSucceeded == true;
      }
    } catch (_) {
      // Unknown/corrupt outcomes cannot borrow a different proposal's writer.
    }
    if (useCurrentLegacy) {
      draftController = ref.watch(legacy.notifier);
    } else if (completedFollowUp) {
      draftController = ref.watch(
        yorksV1ProjectLegacyRecoveryDraftControllerProvider(
          scope.ownerAuthUserId,
        ),
      );
    } else {
      draftController = ref.watch(
        yorksV1ProjectSetupCreationDraftByIdProvider(
          YorksV1ProjectCreationDraftContext(
            ownerAuthUserId: scope.ownerAuthUserId,
            draftId: scope.draftId,
          ),
        ).notifier,
      );
    }
  }
  final followsPointer = scope.projectId != null || legacyRecovery;
  final store = YorksV1ProjectSetupJournalStore(
    storage: ref.watch(yorksV1ProjectDraftAtomicStorageProvider),
    journalKey: '${draftController.journalScopeKey}:journal:${scope.draftId}',
    latestOperationKey: followsPointer
        ? '${draftController.journalScopeKey}:latest_operation'
        : null,
    backendIdentity: ref.watch(yorksV1ProjectDraftBackendIdentityProvider),
    ownerAuthUserId: scope.ownerAuthUserId,
    draftId: scope.draftId,
    expectedMode: scope.projectId == null
        ? YorksV1ProjectSetupMode.create
        : YorksV1ProjectSetupMode.edit,
    projectId: scope.projectId,
    restoreConfirmedFollowUps: false,
    preferLatestOperation: legacyRecovery,
    updateLatestOperation:
        followsPointer && draftController.currentDraftId == scope.draftId,
    atomicOwned: <T>(work) {
      if (ref.read(yorksV1AuthUserIdProvider) != scope.ownerAuthUserId ||
          !draftController.hasCrossProcessOwnership) {
        throw const YorksV1ProjectSetupRecoveryException(
          YorksV1ProjectSetupRecoveryError.recoveryBlocked,
        );
      }
      return draftController.atomicOwned((tx) {
        if (ref.read(yorksV1AuthUserIdProvider) != scope.ownerAuthUserId) {
          throw const YorksV1ProjectSetupRecoveryException(
            YorksV1ProjectSetupRecoveryError.recoveryBlocked,
          );
        }
        return work(tx);
      });
    },
  );
  return YorksV1ProjectSetupCoordinator(
    store: store,
    repository: ref.watch(yorksV1ProjectReviewedCommandRepositoryProvider),
    keyFactory: const Uuid().v4,
    analytics: ref.watch(analyticsServiceProvider),
  );
}

typedef YorksV1ProjectSetupPendingProjectContext = ({
  String ownerAuthUserId,
  String projectId,
});

typedef YorksV1ProjectSetupPendingOperation = ({
  YorksV1ProjectSetupScope scope,
  YorksV1ProjectSetupOperation operation,
});

/// Owner-scoped discovery only. The existing authorized project route must
/// guard presentation; mutations still use the exact historical coordinator
/// scope and the active local writer fence, never a reconstructed file intent.
final yorksV1ProjectSetupPendingOperationsProvider =
    Provider.family<
      List<YorksV1ProjectSetupPendingOperation>,
      YorksV1ProjectSetupPendingProjectContext
    >((ref, context) {
      if (ref.watch(yorksV1AuthUserIdProvider) != context.ownerAuthUserId) {
        return const [];
      }
      final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
      final storage = ref.watch(yorksV1ProjectDraftAtomicStorageProvider);
      final operations = <YorksV1ProjectSetupPendingOperation>[];
      for (final mode in YorksV1ProjectSetupMode.values) {
        final editing = mode == YorksV1ProjectSetupMode.edit;
        final scopeKey = yorksV1ProjectDraftStorageKey(
          backendIdentity: backend,
          ownerAuthUserId: context.ownerAuthUserId,
          mode: editing
              ? YorksV1ProjectDraftMode.edit
              : YorksV1ProjectDraftMode.create,
          projectId: editing ? context.projectId : null,
        );
        for (final operation
            in YorksV1ProjectSetupJournalStore.completedForProject(
              storage: storage,
              scopeKey: scopeKey,
              backendIdentity: backend,
              ownerAuthUserId: context.ownerAuthUserId,
              projectId: context.projectId,
              mode: mode,
            )) {
          operations.add((
            scope: (
              ownerAuthUserId: context.ownerAuthUserId,
              draftId: operation.draftId,
              projectId: editing ? context.projectId : null,
            ),
            operation: operation,
          ));
        }
      }
      return List.unmodifiable(operations);
    });

/// Kept separate from lifecycle so presentation can identify known partial
/// success without treating an upload or activation error as a failed create.
String yorksV1ProjectSetupOutcome(YorksV1ProjectSetupOperation operation) =>
    operation.filesPending
    ? 'saved_files_pending'
    : operation.mode == YorksV1ProjectSetupMode.edit
    ? 'updated'
    : operation.project?.state.wireValue == 'active'
    ? 'active'
    : 'draft_pending_activation';

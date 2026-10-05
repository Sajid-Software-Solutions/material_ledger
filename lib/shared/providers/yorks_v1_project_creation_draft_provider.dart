import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../controllers/yorks_v1_project_creation_draft_controller.dart';
import '../controllers/yorks_v1_legacy_project_creation_draft_controller.dart';
import '../models/yorks_v1_project_creation_draft.dart';
import '../repositories/yorks_v1_project_draft_storage_platform.dart';
import '../repositories/yorks_v1_project_draft_store.dart';
import '../repositories/yorks_v1_project_creation_draft_catalogue.dart';
import '../services/analytics_service.dart';
import '../repositories/storage.dart';
import 'language_provider.dart';

/// Exact configured backend identity, never an editable project field. Tests
/// can override this to exercise staging/production isolation on one device.
final yorksV1ProjectDraftBackendIdentityProvider = Provider<String>((ref) {
  const configured = String.fromEnvironment('SUPABASE_URL');
  if (configured.trim().isEmpty) return 'local';
  return configured.trim().replaceFirst(RegExp(r'/+$'), '');
});

final yorksV1ProjectDraftAtomicStorageProvider =
    Provider<ProjectDraftAtomicStorage>(
      (ref) =>
          createProjectDraftAtomicStorage(ref.watch(sharedPreferencesProvider)),
    );

String yorksV1ProjectDraftStorageKey({
  required String backendIdentity,
  required String ownerAuthUserId,
  required YorksV1ProjectDraftMode mode,
  String? projectId,
}) {
  final context = jsonEncode([
    backendIdentity,
    ownerAuthUserId,
    mode.name,
    projectId,
  ]);
  return 'yorks_project_setup_v2_${sha256.convert(utf8.encode(context))}';
}

final yorksV1ProjectSetupCreationDraftProvider =
    StateNotifierProvider.family<
      YorksV1ProjectCreationDraftController,
      YorksV1ProjectCreationDraft,
      String
    >(
      (ref, ownerAuthUserId) => _controller(
        ref,
        ownerAuthUserId: ownerAuthUserId,
        mode: YorksV1ProjectDraftMode.create,
      ),
    );

enum YorksV1ProjectCreationDraftEntry { newProposal, resume }

/// Entry policy affects the first construction only. The selected proposal
/// remains one provider/lease when a fresh URL is anchored to its durable ID.
class YorksV1ProjectCreationDraftContext {
  const YorksV1ProjectCreationDraftContext({
    required this.ownerAuthUserId,
    required this.draftId,
    this.entry = YorksV1ProjectCreationDraftEntry.resume,
  });
  final String ownerAuthUserId;
  final String draftId;
  final YorksV1ProjectCreationDraftEntry entry;

  @override
  bool operator ==(Object other) =>
      other is YorksV1ProjectCreationDraftContext &&
      other.ownerAuthUserId == ownerAuthUserId &&
      other.draftId == draftId;
  @override
  int get hashCode => Object.hash(ownerAuthUserId, draftId);
}

/// Explicit selection can reuse the original legacy controller already held
/// by this container (for example after deliberate quarantine adoption). This
/// reads existence first and never constructs/claims a singleton to decide.
final yorksV1ProjectSelectedDraftUsesLegacyProvider =
    Provider.family<bool, YorksV1ProjectCreationDraftContext>((ref, context) {
      final legacy = yorksV1ProjectSetupCreationDraftProvider(
        context.ownerAuthUserId,
      );
      return ref.exists(legacy) && ref.watch(legacy).draftId == context.draftId;
    });

final yorksV1ProjectSetupCreationDraftByIdProvider =
    StateNotifierProvider.family<
      YorksV1ProjectCreationDraftController,
      YorksV1ProjectCreationDraft,
      YorksV1ProjectCreationDraftContext
    >((ref, context) {
      final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
      final storage = ref.watch(yorksV1ProjectDraftAtomicStorageProvider);
      final catalogue = YorksV1ProjectCreationDraftCatalogue(
        scopeKey: yorksV1ProjectDraftStorageKey(
          backendIdentity: backend,
          ownerAuthUserId: context.ownerAuthUserId,
          mode: YorksV1ProjectDraftMode.create,
        ),
        ownerAuthUserId: context.ownerAuthUserId,
        backendIdentity: backend,
      );
      String key;
      var requireExisting =
          context.entry == YorksV1ProjectCreationDraftEntry.resume;
      try {
        key = context.entry == YorksV1ProjectCreationDraftEntry.newProposal
            ? catalogue.recordKey(context.draftId)
            : catalogue.resolveRecordKey(storage.read, context.draftId);
        if (context.entry == YorksV1ProjectCreationDraftEntry.newProposal &&
            storage.read(key) == null &&
            (catalogue.resolveRecordKey(storage.read, context.draftId) ==
                    catalogue.scopeKey ||
                storage.read(
                      '${catalogue.scopeKey}:journal:${context.draftId}',
                    ) !=
                    null)) {
          // A new entry cannot reuse a legacy/historical command identity.
          // Its generated UUID must be independent; an explicit collision is
          // guarded instead of shadowing the saved original in discovery.
          requireExisting = true;
        }
      } catch (_) {
        // Invalid route IDs and unreadable storage remain a guarded recovery
        // entry. This unreachable keyed record never aliases the legacy slot.
        key = '${catalogue.scopeKey}:invalid_selection';
        requireExisting = true;
      }
      const uuid = Uuid();
      return YorksV1ProjectCreationDraftController(
        ownerAuthUserId: context.ownerAuthUserId,
        backendIdentity: backend,
        storageKey: key,
        storage: storage,
        initialDraftId: context.draftId,
        requireExistingRecord:
            requireExisting ||
            !YorksV1ProjectCreationDraftCatalogue.validDraftId(context.draftId),
        catalogue: catalogue,
        journalScopeKey: catalogue.scopeKey,
        idempotencyKeyFactory: uuid.v4,
        analytics: ref.watch(analyticsServiceProvider),
      );
    });

typedef _CreationDraftProvider =
    StateNotifierProvider<
      YorksV1ProjectCreationDraftController,
      YorksV1ProjectCreationDraft
    >;

/// A non-owning alias: generic original-slot recovery can reuse a selected
/// controller already holding that same slot instead of creating another
/// writer in this tab. Unsupported original bytes still use its old boundary.
final yorksV1ProjectLegacyRecoveryDraftSourceProvider =
    Provider.family<_CreationDraftProvider, String>((ref, owner) {
      final legacy = yorksV1ProjectSetupCreationDraftProvider(owner);
      final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
      final storage = ref.watch(yorksV1ProjectDraftAtomicStorageProvider);
      final root = yorksV1ProjectDraftStorageKey(
        backendIdentity: backend,
        ownerAuthUserId: owner,
        mode: YorksV1ProjectDraftMode.create,
      );
      try {
        final raw = storage.read(root);
        if (raw != null) {
          final record = jsonDecode(raw) as Map;
          final draft = YorksV1ProjectCreationDraft.fromJson(
            Map<String, dynamic>.from(record['draft'] as Map),
          );
          if (record['recordVersion'] == 1 &&
              record['retired'] == false &&
              draft.ownerAuthUserId == owner &&
              draft.backendIdentity == backend &&
              draft.mode == YorksV1ProjectDraftMode.create &&
              draft.projectId == null) {
            if (ref.exists(legacy) &&
                ref.watch(legacy).draftId == draft.draftId) {
              return legacy;
            }
            final selected = yorksV1ProjectSetupCreationDraftByIdProvider(
              YorksV1ProjectCreationDraftContext(
                ownerAuthUserId: owner,
                draftId: draft.draftId,
              ),
            );
            if (ref.exists(selected) &&
                ref.watch(selected).draftId == draft.draftId &&
                ref.read(selected.notifier).storageKey == root) {
              return selected;
            }
          }
        }
      } catch (_) {
        // No corrupt/foreign record can select a different local proposal.
      }
      return legacy;
    });

final yorksV1ProjectLegacyRecoveryDraftControllerProvider =
    Provider.family<YorksV1ProjectCreationDraftController, String>((
      ref,
      owner,
    ) {
      final source = ref.watch(
        yorksV1ProjectLegacyRecoveryDraftSourceProvider(owner),
      );
      return ref.watch(source.notifier);
    });

final yorksV1ProjectLegacyRecoveryDraftProvider =
    Provider.family<YorksV1ProjectCreationDraft, String>((ref, owner) {
      final source = ref.watch(
        yorksV1ProjectLegacyRecoveryDraftSourceProvider(owner),
      );
      return ref.watch(source);
    });

class YorksV1ProjectEditDraftContext {
  const YorksV1ProjectEditDraftContext({
    required this.ownerAuthUserId,
    required this.projectId,
  });
  final String ownerAuthUserId;
  final String projectId;

  @override
  bool operator ==(Object other) =>
      other is YorksV1ProjectEditDraftContext &&
      other.ownerAuthUserId == ownerAuthUserId &&
      other.projectId == projectId;
  @override
  int get hashCode => Object.hash(ownerAuthUserId, projectId);
}

final yorksV1ProjectEditDraftProvider =
    StateNotifierProvider.family<
      YorksV1ProjectCreationDraftController,
      YorksV1ProjectCreationDraft,
      YorksV1ProjectEditDraftContext
    >(
      (ref, context) => _controller(
        ref,
        ownerAuthUserId: context.ownerAuthUserId,
        mode: YorksV1ProjectDraftMode.edit,
        projectId: context.projectId,
      ),
    );

YorksV1ProjectCreationDraftController _controller(
  Ref ref, {
  required String ownerAuthUserId,
  required YorksV1ProjectDraftMode mode,
  String? projectId,
}) {
  final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  const uuid = Uuid();
  return YorksV1ProjectCreationDraftController(
    ownerAuthUserId: ownerAuthUserId,
    backendIdentity: backend,
    mode: mode,
    projectId: projectId,
    storage: ref.watch(yorksV1ProjectDraftAtomicStorageProvider),
    storageKey: yorksV1ProjectDraftStorageKey(
      backendIdentity: backend,
      ownerAuthUserId: ownerAuthUserId,
      mode: mode,
      projectId: projectId,
    ),
    // This raw read bypasses legacy row-skipping. Unverified data is preserved
    // for explicit reconciliation instead of silently restored to a backend.
    legacyRaw: mode == YorksV1ProjectDraftMode.create
        ? prefs.getString('yorks_v1_project_creation_draft_v1_$ownerAuthUserId')
        : null,
    idempotencyKeyFactory: uuid.v4,
    analytics: ref.watch(analyticsServiceProvider),
  );
}

/// Accepted R35 recovery stays on its original key while the new setup flag is
/// off. It does not unexpectedly quarantine existing users' local input.
final yorksV1ProjectCreationDraftProvider =
    StateNotifierProvider.family<
      YorksV1LegacyProjectCreationDraftController,
      YorksV1ProjectCreationDraft,
      String
    >((ref, ownerAuthUserId) {
      final store = ref
          .watch(storageProvider)
          .collection<YorksV1ProjectCreationDraft>(
            'yorks_v1_project_creation_draft_v1_$ownerAuthUserId',
            toJson: (draft) => draft.toJson(),
            fromJson: YorksV1ProjectCreationDraft.fromJson,
          );
      const uuid = Uuid();
      return YorksV1LegacyProjectCreationDraftController(
        ownerAuthUserId: ownerAuthUserId,
        store: store,
        idempotencyKeyFactory: uuid.v4,
      );
    });

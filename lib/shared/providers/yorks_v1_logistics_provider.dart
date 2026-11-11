import '../models/yorks_v1_inventory_register_query.dart';
import '../models/yorks_v1_inventory_history.dart';
import 'dart:async';
import 'yorks_v1_identity_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_logistics.dart';
import '../models/yorks_v1_material_return_candidates.dart';
import '../models/yorks_v1_material_return_workflow.dart';
import '../models/yorks_v1_material_request.dart';
import '../models/yorks_v1_project_material_summary.dart';
import '../repositories/yorks_v1_logistics_repository.dart';
import 'yorks_v1_logistics_repository_provider.dart';
import 'yorks_v1_material_request_provider.dart';

final yorksV1InventoryWorkspaceProvider = FutureProvider.autoDispose
    .family<YorksV1InventoryWorkspace, String?>((ref, search) {
      _listenForInventoryRefresh(ref);
      return ref
          .watch(yorksV1LogisticsRepositoryProvider)
          .getInventory(search: search);
    });

final yorksV1InventoryItemDetailProvider = FutureProvider.autoDispose
    .family<YorksV1InventoryItemDetail, String>((ref, inventoryItemId) {
      _listenForInventoryRefresh(ref);
      return ref
          .watch(yorksV1LogisticsRepositoryProvider)
          .getInventoryItem(inventoryItemId);
    });

final yorksV1InventoryCategorySuggestionsProvider = FutureProvider.autoDispose
    .family<List<YorksV1InventoryCategorySearchResult>, String>((
      ref,
      query,
    ) async {
      final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
      if (repository is! YorksV1InventoryCategorySuggestionRepository ||
          query.trim().isEmpty) {
        return const [];
      }
      final suggestionRepository =
          repository as YorksV1InventoryCategorySuggestionRepository;
      return suggestionRepository.suggestInventoryCategories(query);
    });

final yorksV1LogisticsWorkspaceProvider = FutureProvider.autoDispose
    .family<YorksV1LogisticsWorkspace, String>((ref, requestId) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null &&
            previous != next &&
            yorksV1MaterialRequestRefreshIncludes(ref, const {
              YorksV1MaterialRequestRefreshReason.materialRequest,
              YorksV1MaterialRequestRefreshReason.arrangement,
              YorksV1MaterialRequestRefreshReason.dispatch,
              YorksV1MaterialRequestRefreshReason.receiptReview,
              YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
            })) {
          ref.invalidateSelf();
        }
      });
      return ref
          .watch(yorksV1LogisticsRepositoryProvider)
          .getWorkspace(requestId);
    });

final yorksV1ProjectMaterialMovementsProvider = FutureProvider.autoDispose
    .family<List<YorksV1ProjectMaterialMovement>, String>((ref, projectId) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null &&
            previous != next &&
            yorksV1MaterialRequestRefreshIncludes(ref, const {
              YorksV1MaterialRequestRefreshReason.dispatch,
              YorksV1MaterialRequestRefreshReason.receiptReview,
              YorksV1MaterialRequestRefreshReason.materialReturn,
              YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
            })) {
          ref.invalidateSelf();
        }
      });
      return ref
          .watch(yorksV1LogisticsRepositoryProvider)
          .getProjectMaterialMovements(projectId);
    });

/// Read-only project Material Summary for one filter combination. Realtime
/// workflow revisions refresh it, so new requests and dispatches appear
/// without a manual reload.
final yorksV1ProjectMaterialSummaryProvider = FutureProvider.autoDispose
    .family<YorksV1ProjectMaterialSummary, YorksV1MaterialSummaryQuery>((
      ref,
      query,
    ) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
      if (repository is! YorksV1ProjectMaterialSummaryRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1ProjectMaterialSummaryRepository)
          .getProjectMaterialSummary(query);
    });

final yorksV1ReturnsDocumentsWorkspaceProvider = FutureProvider.autoDispose
    .family<YorksV1ReturnsDocumentsWorkspace, String>((ref, requestId) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null &&
            previous != next &&
            yorksV1MaterialRequestRefreshIncludes(ref, const {
              YorksV1MaterialRequestRefreshReason.dispatch,
              YorksV1MaterialRequestRefreshReason.receiptReview,
              YorksV1MaterialRequestRefreshReason.deliveryOrder,
              YorksV1MaterialRequestRefreshReason.materialReturn,
              YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
            })) {
          ref.invalidateSelf();
        }
      });
      return ref
          .watch(yorksV1LogisticsRepositoryProvider)
          .getReturnsDocumentsWorkspace(requestId);
    });

class YorksV1MaterialReturnRegisterQuery {
  const YorksV1MaterialReturnRegisterQuery({
    this.projectId,
    this.state,
    this.search,
  });

  final String? projectId;
  final String? state;
  final String? search;

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialReturnRegisterQuery &&
      other.projectId == projectId &&
      other.state == state &&
      other.search == search;

  @override
  int get hashCode => Object.hash(projectId, state, search);
}

final yorksV1MaterialReturnRegisterProvider = FutureProvider.autoDispose
    .family<
      List<YorksV1MaterialReturnRegisterItem>,
      YorksV1MaterialReturnRegisterQuery
    >((ref, query) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null &&
            previous != next &&
            yorksV1MaterialRequestRefreshIncludes(ref, const {
              YorksV1MaterialRequestRefreshReason.materialReturn,
              YorksV1MaterialRequestRefreshReason.receiptReview,
              YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
            })) {
          ref.invalidateSelf();
        }
      });
      return _projectReturnRepository(ref).listProjectMaterialReturns(
        projectId: query.projectId,
        state: query.state,
        search: query.search,
      );
    });

final yorksV1MaterialReturnProjectsProvider =
    FutureProvider.autoDispose<List<YorksV1MaterialRequestProjectOption>>(
      (ref) => _projectReturnRepository(ref).listMaterialReturnProjects(),
    );

final yorksV1ProjectMaterialReturnProvider = FutureProvider.autoDispose
    .family<YorksV1ProjectMaterialReturn, String>((ref, returnId) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null &&
            previous != next &&
            yorksV1MaterialRequestRefreshIncludes(ref, const {
              YorksV1MaterialRequestRefreshReason.materialReturn,
              YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
            })) {
          ref.invalidateSelf();
        }
      });
      return _projectReturnRepository(ref).getProjectMaterialReturn(returnId);
    });

typedef YorksV1MaterialReturnCreationKey = ({
  String projectId,
  String? returnId,
});

final yorksV1MaterialReturnCreationWorkspaceProvider = FutureProvider
    .autoDispose
    .family<
      YorksV1MaterialReturnCreationWorkspace,
      YorksV1MaterialReturnCreationKey
    >((ref, key) {
      return _projectReturnRepository(ref).getMaterialReturnCreationWorkspace(
        projectId: key.projectId,
        returnId: key.returnId,
      );
    });

/// Grouped, searchable delivered material for the return composer. Keyed by
/// project, draft, search text and optional building.
final yorksV1MaterialReturnItemCandidatesProvider = FutureProvider.autoDispose
    .family<
      YorksV1MaterialReturnItemCandidates,
      YorksV1MaterialReturnCandidatesQuery
    >((ref, query) {
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
      if (repository is! YorksV1MaterialReturnItemCandidatesRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialReturnItemCandidatesRepository)
          .getMaterialReturnItemCandidates(query);
    });

YorksV1ProjectMaterialReturnRepository _projectReturnRepository(Ref ref) {
  final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
  if (repository is! YorksV1ProjectMaterialReturnRepository) {
    throw const YorksV1DomainException(YorksV1DomainErrorCode.featureDisabled);
  }
  return repository as YorksV1ProjectMaterialReturnRepository;
}

void _listenForInventoryRefresh(Ref ref) {
  ref.watch(yorksV1AuthUserIdProvider);
  ref.watch(yorksV1CurrentRoleProvider);
  Timer? refresh;
  ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
    previous,
    next,
  ) {
    if (previous == null || previous == next) return;
    refresh?.cancel();
    refresh = Timer(const Duration(milliseconds: 300), ref.invalidateSelf);
  });
  ref.onDispose(() => refresh?.cancel());
}

final yorksV1InventoryHistoryProvider = FutureProvider.autoDispose
    .family<YorksV1InventoryHistoryPage, YorksV1InventoryHistoryQuery>((
      ref,
      query,
    ) {
      _listenForInventoryRefresh(ref);
      final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
      if (repository is! YorksV1InventoryHistoryRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1InventoryHistoryRepository)
          .getInventoryHistory(query);
    });

final yorksV1InventoryRegisterProvider = FutureProvider.autoDispose
    .family<YorksV1InventoryWorkspace, YorksV1InventoryRegisterQuery>((
      ref,
      query,
    ) {
      _listenForInventoryRefresh(ref);
      final repository = ref.watch(yorksV1LogisticsRepositoryProvider);
      return repository is YorksV1InventoryRegisterRepository
          ? (repository as YorksV1InventoryRegisterRepository).getInventoryPage(
              query,
            )
          : repository.getInventory();
    });

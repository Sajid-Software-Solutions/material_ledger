import 'yorks_v1_inventory_import_recovery_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/yorks_v1_inventory_import_controller.dart';
import '../models/yorks_v1_logistics.dart';
import '../services/yorks_v1_inventory_workbook_service.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_logistics_provider.dart';
import 'yorks_v1_inventory_supplier_provider.dart';
import 'yorks_v1_logistics_repository_provider.dart';

final yorksV1InventoryWorkbookFileServiceProvider =
    Provider<YorksV1InventoryWorkbookFileService>(
      (_) => const YorksV1PlatformInventoryWorkbookFileService(),
    );

final yorksV1InventoryImportControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksV1InventoryImportController,
      YorksV1InventoryImportState
    >((ref) {
      ref.watch(yorksV1AuthUserIdProvider);
      ref.watch(yorksV1CurrentRoleProvider);
      final recovery = ref.watch(yorksV1InventoryImportRecoveryProvider);
      final controller = YorksV1InventoryImportController(
        persistPending: recovery?.persist,
        canExecute: recovery == null ? null : () => recovery.active,
        repository: ref.watch(yorksV1LogisticsRepositoryProvider),
        fileService: ref.watch(yorksV1InventoryWorkbookFileServiceProvider),
        r38_9Commit: ref.watch(yorksV1FeatureFlagsProvider).inventorySuppliers
            ? ({required payload, required idempotencyKey}) async {
                final result = await ref
                    .read(yorksV1InventorySupplierRepositoryProvider)
                    .importPrepared(
                      payload: payload,
                      idempotencyKey: idempotencyKey,
                    );
                return YorksV1InventoryImportResult(
                  importBatchId: result.importBatchId,
                  rowCount: result.rowCount,
                  createdItems: result.createdItems,
                  updatedItems: result.updatedItems,
                  createdCategories: result.createdCategories,
                  createdSuppliers: result.createdSuppliers,
                  receiptBatches: result.receiptBatches,
                  movements: result.movements,
                  warningCount: result.warningCount,
                  excludedCount: result.excludedCount,
                  unknownSupplierRows: result.unknownSupplierRows,
                  unitTotals: [
                    for (final total in result.unitTotals)
                      YorksV1InventoryImportUnitTotal(
                        unit: total.unit,
                        acceptedQuantity: total.acceptedQuantity,
                        damagedQuantity: total.damagedQuantity,
                        rejectedQuantity: total.rejectedQuantity,
                      ),
                  ],
                );
              }
            : null,
      );
      // Retain the exact import command while navigation is blocked by the
      // router. Invalidation is triggered only by a confirmed success.
      void Function()? releasePending;
      final stop = controller.addListener((state) {
        if (state.status == YorksV1InventoryImportStatus.committing ||
            state.hasUnconfirmedCommit) {
          releasePending ??= ref.keepAlive().close;
        } else {
          releasePending?.call();
          releasePending = null;
        }
        if (state.status == YorksV1InventoryImportStatus.succeeded) {
          ref.invalidate(yorksV1InventoryWorkspaceProvider);
          ref.invalidate(yorksV1InventoryRegisterProvider);
          ref.invalidate(yorksV1InventoryItemDetailProvider);
          ref.invalidate(yorksV1InventoryHistoryProvider);
          ref.invalidate(yorksV1InventorySupplierDirectoryProvider);
          ref.invalidate(yorksV1InventorySupplierFolderProvider);
        }
      }, fireImmediately: false);
      ref.onDispose(stop);
      return controller;
    });

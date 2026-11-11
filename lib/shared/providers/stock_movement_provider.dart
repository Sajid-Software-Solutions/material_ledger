import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/stock_movement.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';

const _kStockMovementsKey = 'stock_movements_v2';
const _uuid = Uuid();

/// The append-only stock ledger. Records accrue from stock actions and are never
/// edited or deleted (a correction is a new, opposite entry).
final stockMovementsProvider =
    StateNotifierProvider<StockMovementsNotifier, List<StockMovement>>((ref) {
      return StockMovementsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<StockMovement>(
              _kStockMovementsKey,
              toJson: (m) => m.toJson(),
              fromJson: StockMovement.fromJson,
            ),
      );
    });

class StockMovementsNotifier extends StateNotifier<List<StockMovement>> {
  StockMovementsNotifier(this._ref, this._store) : super(_store.readAll());

  final Ref _ref;
  final CollectionStore<StockMovement> _store;

  /// Newest-first movements for one material.
  List<StockMovement> forMaterial(String materialId) =>
      state.where((m) => m.materialId == materialId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Future<void> record({
    required String materialId,
    required String materialName,
    required MovementType type,
    required double delta,
    required double resultingBalance,
    String? refId,
    String? actor,
  }) async {
    if (delta == 0) return; // a no-op change isn't ledgered
    final mv = StockMovement(
      id: 'mov-${_uuid.v4().substring(0, 8)}',
      materialId: materialId,
      materialName: materialName,
      type: type,
      delta: delta,
      resultingBalance: resultingBalance,
      refId: refId,
      actor: actor,
      timestamp: DateTime.now(),
    );
    state = [mv, ...state];
    await _store.writeAll(state);
    // The ledger is the shared audit trail → sync it (transactional).
    await _ref.enqueueSync(
      collection: 'stockMovements',
      docId: mv.id,
      kind: 'stockMovement.record',
      label: 'Stock movement',
      payload: mv.toJson(),
      transactional: true,
    );
  }
}

/// Newest-first movements across all materials (drives the Stock History screen).
final recentStockMovementsProvider = Provider<List<StockMovement>>((ref) {
  final all = [...ref.watch(stockMovementsProvider)];
  all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return all;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/material_return.dart';
import '../models/stock_movement.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';
import 'inventory_provider.dart';
import 'material_request_provider.dart';

const _kReturnsKey = 'material_returns_list_v2';
const _uuid = Uuid();

/// All material returns raised by the engineer (FR-083).
final returnsProvider =
    StateNotifierProvider<ReturnsNotifier, List<MaterialReturn>>((ref) {
      return ReturnsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<MaterialReturn>(
              _kReturnsKey,
              toJson: (r) => r.toJson(),
              fromJson: MaterialReturn.fromJson,
            ),
      );
    });

class ReturnsNotifier extends StateNotifier<List<MaterialReturn>> {
  ReturnsNotifier(this._ref, this._store) : super(_store.readAll());

  final Ref _ref;
  final CollectionStore<MaterialReturn> _store;

  Future<void> _persist() => _store.writeAll(state);

  /// Quantity of [materialId] still eligible to return against [projectName]:
  /// everything dispatched to that project, minus what's already been returned.
  /// Guards against returning more than was actually issued (which would inflate
  /// on-hand stock out of thin air).
  double _netReturnable(String projectName, String materialId) {
    var dispatched = 0.0;
    for (final r in _ref.read(materialRequestsProvider)) {
      if (r.projectName != projectName) continue;
      for (final l in r.lineItems) {
        if (l.materialId == materialId) dispatched += l.qtyDispatched ?? 0;
      }
    }
    var returned = 0.0;
    for (final ret in state) {
      if (ret.projectName != projectName) continue;
      for (final it in ret.items) {
        if (it.materialId == materialId) returned += it.quantity;
      }
    }
    return (dispatched - returned).clamp(0, double.infinity).toDouble();
  }

  /// Raise a return and restock the inventory for every line that maps to a
  /// known material (FR-083). Each stock-mapped line is CLAMPED to what's still
  /// returnable for the project (issued − already returned), so a return can
  /// never put back more than left the store. Damaged stock is recorded but not
  /// put back on the shelf; surplus and wrong-item stock is restocked at cost.
  Future<void> addReturn({
    required String projectName,
    required String projectNameSecondary,
    required List<ReturnItem> items,
  }) async {
    final clamped = <ReturnItem>[];
    for (final it in items) {
      if (it.materialId == null) {
        clamped.add(it); // free-text/custom — nothing to reconcile against
      } else {
        final cap = _netReturnable(projectName, it.materialId!);
        clamped.add(
          it.copyWith(quantity: it.quantity.clamp(0, cap).toDouble()),
        );
      }
    }

    final r = MaterialReturn(
      id: 'ret-${_uuid.v4().substring(0, 8)}',
      projectName: projectName,
      projectNameSecondary: projectNameSecondary,
      items: clamped,
      status: ReturnStatus.restocked,
      createdAt: DateTime.now(),
    );

    final inventory = _ref.read(materialsProvider.notifier);
    for (final item in clamped) {
      if (item.materialId == null) continue;
      if (item.reason == ReturnReason.damaged) continue; // not resalable
      if (item.quantity <= 0) continue; // nothing left returnable
      // Restock at the current weighted-average cost (ledgered as a return-in).
      await inventory.receiveStock(
        item.materialId!,
        item.quantity,
        type: MovementType.returnIn,
        refId: r.id,
      );
    }

    state = [r, ...state];
    await _persist();
    // Restocks inventory → transactional (atomic stock change on the server).
    await _ref.enqueueSync(
      collection: 'returns',
      docId: r.id,
      kind: 'return.create',
      label: 'Material return',
      payload: r.toJson(),
      transactional: true,
    );
  }
}

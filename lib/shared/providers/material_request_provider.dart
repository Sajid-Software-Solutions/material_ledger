import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/material_item.dart';
import '../models/material_request.dart';
import '../models/project.dart';
import '../models/stock_movement.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';
import 'inventory_provider.dart';
import 'session_provider.dart';

const _kRequestsKey = 'material_requests_list_v3';

/// Request statuses that actively hold a stock reservation. Single source of
/// truth for the notifier's release logic AND the reservation reconciler.
const kHoldingRequestStatuses = {
  RequestStatus.pending,
  RequestStatus.sourcing,
  RequestStatus.partial,
  RequestStatus.onHold,
  RequestStatus.dispatched,
};

/// All material requests for the engineer.
final materialRequestsProvider =
    StateNotifierProvider<MaterialRequestsNotifier, List<MaterialRequest>>((
      ref,
    ) {
      return MaterialRequestsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<MaterialRequest>(
              _kRequestsKey,
              toJson: (r) => r.toJson(),
              fromJson: MaterialRequest.fromJson,
            ),
      );
    });

/// Notifier that manages the list of material requests with persistence.
class MaterialRequestsNotifier extends StateNotifier<List<MaterialRequest>> {
  MaterialRequestsNotifier(this._ref, this._store) : super(_load(_store)) {
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<MaterialRequest> _store;
  static const _uuid = Uuid();

  static List<MaterialRequest> _load(CollectionStore<MaterialRequest> store) {
    final all = store.isSeeded ? store.readAll() : _seedRequests;
    return all.where((r) => !r.deleted).toList();
  }

  MaterialsNotifier get _inventory => _ref.read(materialsProvider.notifier);

  /// Reserve stock only for lines that map to a REAL inventory material
  /// (FR-094). Custom / not-yet-stocked items (no matching [MaterialItem]) hold
  /// no reservation — they must be received into inventory before they can be
  /// reserved or dispatched.
  Future<void> _reserveLines(List<RequestLineItem> lines) async {
    for (final l in lines) {
      if (_inventory.byId(l.materialId) == null) continue;
      await _inventory.reserve(l.materialId, l.quantity);
    }
  }

  /// Release reservations for every line that holds one (cancel / supersede).
  /// Only the still-reserved outstanding quantity is freed, and only for real
  /// inventory items — so this never over-releases or touches custom items.
  Future<void> _releaseLines(List<RequestLineItem> lines) async {
    for (final l in lines) {
      if (_inventory.byId(l.materialId) == null) continue;
      await _inventory.release(l.materialId, l.qtyOutstanding);
    }
  }

  Future<void> _persist() => _store.writeAll(state);

  /// Route a request write through the durable outbox so it survives offline,
  /// retries until the server confirms, and can never be duplicated on resend
  /// (idempotent on the client-generated [MaterialRequest.id]). [transactional]
  /// marks writes that move stock/reservations so the backend applies them in an
  /// atomic Firestore transaction.
  Future<void> _sync(
    MaterialRequest r, {
    required String kind,
    required String label,
    bool transactional = false,
  }) {
    return _ref.enqueueSync(
      collection: 'materialRequests',
      docId: r.id,
      kind: kind,
      label: label,
      payload: r.toJson(),
      transactional: transactional,
    );
  }

  /// Add a new material request (submitted). Returns the created request so the
  /// caller can deep-link a notification to it (FR-064).
  Future<MaterialRequest> addRequest({
    required String projectName,
    required String projectNameSecondary,
    required int itemCount,
    String? projectId,
    List<RequestLineItem> lineItems = const [],
    RequestPriority priority = RequestPriority.normal,
    String? siteLocation,
    String? notes,
  }) async {
    final request = MaterialRequest(
      id: 'req-${_uuid.v4().substring(0, 8)}',
      projectId: projectId,
      projectName: projectName,
      projectNameSecondary: projectNameSecondary,
      status: RequestStatus.pending,
      requestDate: DateTime.now(),
      itemCount: itemCount,
      lineItems: lineItems,
      priority: priority,
      siteLocation: siteLocation,
      notes: notes,
      engineerId: _ref.read(currentUserProvider)?.id,
    );
    state = [request, ...state];
    await _persist();
    // Submitting commits the stock — reserve it so it can't be promised twice.
    await _reserveLines(lineItems);
    await _sync(
      request,
      kind: 'request.create',
      label: 'Material request',
      transactional: true, // reserves stock
    );
    return request;
  }

  /// Save a request as draft.
  Future<void> saveDraft({
    required String projectName,
    required String projectNameSecondary,
    required int itemCount,
    String? projectId,
    List<RequestLineItem> lineItems = const [],
    RequestPriority priority = RequestPriority.normal,
    String? siteLocation,
    String? notes,
  }) async {
    final request = MaterialRequest(
      id: 'req-${_uuid.v4().substring(0, 8)}',
      projectId: projectId,
      projectName: projectName,
      projectNameSecondary: projectNameSecondary,
      status: RequestStatus.draft,
      requestDate: DateTime.now(),
      itemCount: itemCount,
      lineItems: lineItems,
      priority: priority,
      siteLocation: siteLocation,
      notes: notes,
      engineerId: _ref.read(currentUserProvider)?.id,
    );
    state = [request, ...state];
    await _persist();
    await _sync(request, kind: 'request.draft', label: 'Draft request');
  }

  /// Statuses that are actively holding a stock reservation.
  static const _holdingStatuses = kHoldingRequestStatuses;

  MaterialRequest? _byId(String id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Submit a draft request (change status to pending) and reserve its stock.
  Future<void> submitDraft(String id) async {
    final req = _byId(id);
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(status: RequestStatus.pending) else r,
    ];
    await _persist();
    if (req != null && req.status == RequestStatus.draft) {
      await _reserveLines(req.lineItems);
    }
    final updated = _byId(id);
    if (updated != null) {
      await _sync(
        updated,
        kind: 'request.submit',
        label: 'Material request',
        transactional: true, // reserves stock
      );
    }
  }

  /// Remove a request by ID, releasing any reservation it still holds. Soft-
  /// deletes (tombstones) rather than physically dropping the row, since the
  /// sync outbox only ever upserts — a bare local removal would resurrect the
  /// request the next time another device's write hydrates back here.
  Future<void> removeRequest(String id) async {
    final req = _byId(id);
    if (req == null) return;
    final tombstone = req.copyWith(deleted: true);
    state = state.where((r) => r.id != id).toList();
    await _persist();
    await _sync(tombstone, kind: 'request.delete', label: 'Material request');
    if (_holdingStatuses.contains(req.status)) {
      await _releaseLines(req.lineItems);
    }
  }

  /// Update status of a request. Cancelling releases the held reservation.
  Future<void> updateStatus(String id, RequestStatus newStatus) async {
    final req = _byId(id);
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(status: newStatus) else r,
    ];
    await _persist();
    if (req != null &&
        newStatus == RequestStatus.cancelled &&
        _holdingStatuses.contains(req.status)) {
      await _releaseLines(req.lineItems);
    }
    final updated = _byId(id);
    if (updated != null) {
      await _sync(
        updated,
        kind: 'request.status',
        label: 'Material request',
        transactional: newStatus == RequestStatus.cancelled, // releases stock
      );
    }
  }

  /// True when a line's full outstanding quantity is physically on hand and so
  /// can be dispatched. A custom/un-stocked line (no material) or one with less
  /// stock than outstanding is NOT dispatchable — the shortfall must be arranged
  /// (restocked) or the engineer must reduce the request first.
  bool canDispatchLine(RequestLineItem line) {
    if (line.qtyOutstanding <= 0) return false;
    final item = _inventory.byId(line.materialId);
    if (item == null) return false;
    return _freeForLine(item, line) >= line.qtyOutstanding;
  }

  /// Stock free to dispatch to THIS line = on-hand minus the reservations held
  /// by OTHER open requests. This line's own reservation is released on
  /// dispatch, so it doesn't count against itself — but another request's
  /// reservation must not be consumed here (FR-094).
  static double _freeForLine(MaterialItem item, RequestLineItem line) {
    final othersReserved = (item.reservedQty - line.qtyOutstanding)
        .clamp(0, double.infinity)
        .toDouble();
    return item.quantity - othersReserved;
  }

  /// Procurement dispatches a request to site. Stock physically leaves the store
  /// here: on-hand decrements and the matching reservation is freed for the
  /// dispatched quantity. A request can be fulfilled across several dispatches
  /// (some lines now, others once arranged), so it lands in `partial` until
  /// every line is out.
  ///
  /// IMPORTANT — a line is all-or-nothing against availability: it ships only
  /// when the full outstanding quantity is on hand (see [canDispatchLine]). We
  /// never ship a short quantity for an under-stocked line; that shortfall must
  /// be arranged or the engineer must edit the request down. [dispatchByIndex]
  /// is the quantity per line; omit/short to default each line to its
  /// outstanding quantity.
  Future<void> dispatch(String id, [List<double>? dispatchByIndex]) async {
    final req = _byId(id);
    if (req == null) return;

    var movedAny = false;
    final newLines = <RequestLineItem>[];
    for (var i = 0; i < req.lineItems.length; i++) {
      final line = req.lineItems[i];
      final item = _inventory.byId(line.materialId);
      var requested = (dispatchByIndex != null && i < dispatchByIndex.length)
          ? dispatchByIndex[i]
          : line.qtyOutstanding;
      requested = requested.clamp(0, line.qtyOutstanding).toDouble();

      double d;
      if (item == null || _freeForLine(item, line) < line.qtyOutstanding) {
        // Blocked: not stocked, or not enough AVAILABLE — the rest is on hand
        // but reserved for other open requests. Never ship a short line or eat
        // another request's reservation; leave it outstanding.
        d = 0;
      } else {
        // Fully available — ship what's asked (≤ outstanding ≤ available).
        d = requested;
      }
      if (d > 0) {
        // Leave the store (ledgered as a dispatch), then free that reservation.
        await _inventory.adjustQuantity(
          line.materialId,
          -d,
          type: MovementType.dispatch,
          refId: id,
        );
        await _inventory.release(line.materialId, d);
        movedAny = true;
      }
      newLines.add(line.copyWith(qtyDispatched: (line.qtyDispatched ?? 0) + d));
    }

    // Nothing could be dispatched (every line blocked) → leave the request as
    // it was so it stays in the queue; don't fake a "partial".
    if (!movedAny) return;

    final fullyDispatched = newLines.every(
      (l) => (l.qtyDispatched ?? 0) >= l.quantity,
    );
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            status: fullyDispatched
                ? RequestStatus.dispatched
                : RequestStatus.partial,
            lineItems: newLines,
          )
        else
          r,
    ];
    await _persist();
    final updated = _byId(id);
    if (updated != null) {
      // Stock physically left the store — atomic (transactional). Coalescing on
      // docId means repeated partial dispatches sync the latest cumulative state
      // without duplicating or losing any.
      await _sync(
        updated,
        kind: 'request.dispatch',
        label: 'Dispatch',
        transactional: true,
      );
    }
  }

  /// Re-point a request line from a custom/placeholder material id onto a REAL
  /// inventory material that procurement just created & stocked, then reserve the
  /// outstanding quantity. After this the line is a normal, dispatchable item.
  Future<void> relinkLine(
    String requestId,
    String oldMaterialId, {
    required String newMaterialId,
    required String newName,
  }) async {
    final req = _byId(requestId);
    if (req == null) return;
    RequestLineItem? relinked;
    final newLines = <RequestLineItem>[];
    for (final l in req.lineItems) {
      if (l.materialId == oldMaterialId) {
        final nl = l.copyWith(materialId: newMaterialId, materialName: newName);
        relinked = nl;
        newLines.add(nl);
      } else {
        newLines.add(l);
      }
    }
    if (relinked == null) return;
    state = [
      for (final r in state)
        if (r.id == requestId) r.copyWith(lineItems: newLines) else r,
    ];
    await _persist();
    // Reserve the now-real material for what's still outstanding on this line.
    await _inventory.reserve(newMaterialId, relinked.qtyOutstanding);
    final updated = _byId(requestId);
    if (updated != null) {
      await _sync(
        updated,
        kind: 'request.relink',
        label: 'Material request',
        transactional: true,
      );
    }
  }

  /// Append a comment to a request's discussion thread (engineer ↔ procurement).
  Future<void> addRequestComment(
    String id, {
    required String text,
    required String authorName,
    required String authorRole,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final comment = RequestComment(
      authorName: authorName,
      authorRole: authorRole,
      text: trimmed,
      timestamp: DateTime.now(),
    );
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(comments: [...r.comments, comment]) else r,
    ];
    await _persist();
    final updated = _byId(id);
    if (updated != null) {
      await _sync(updated, kind: 'request.comment', label: 'Material request');
    }
  }

  /// Engineer edits an outstanding line's quantity (e.g. reduce to what's
  /// available). Never below what's already been dispatched. The reservation is
  /// adjusted by the delta so stock promises stay accurate.
  Future<void> updateRequestLine(
    String id,
    String materialId,
    double newQuantity,
  ) async {
    final req = _byId(id);
    if (req == null) return;
    final newLines = <RequestLineItem>[];
    for (final l in req.lineItems) {
      if (l.materialId == materialId) {
        final dispatched = l.qtyDispatched ?? 0;
        final q = newQuantity.clamp(dispatched, double.infinity).toDouble();
        final delta = l.quantity - q; // > 0 means reduced
        if (delta != 0 && _inventory.byId(materialId) != null) {
          if (delta > 0) {
            await _inventory.release(materialId, delta);
          } else {
            await _inventory.reserve(materialId, -delta);
          }
        }
        newLines.add(l.copyWith(quantity: q));
      } else {
        newLines.add(l);
      }
    }
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(lineItems: newLines) else r,
    ];
    await _persist();
    final updated = _byId(id);
    if (updated != null) {
      await _sync(
        updated,
        kind: 'request.edit',
        label: 'Material request',
        transactional: true, // adjusts reservation
      );
    }
  }

  /// Engineer drops a line from the request entirely, releasing its remaining
  /// reservation.
  Future<void> removeRequestLine(String id, String materialId) async {
    final req = _byId(id);
    if (req == null) return;
    RequestLineItem? target;
    for (final l in req.lineItems) {
      if (l.materialId == materialId) {
        target = l;
        break;
      }
    }
    if (target == null) return;
    final newLines = req.lineItems
        .where((l) => l.materialId != materialId)
        .toList();
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(lineItems: newLines, itemCount: newLines.length)
        else
          r,
    ];
    await _persist();
    if (_holdingStatuses.contains(req.status) &&
        _inventory.byId(materialId) != null) {
      await _inventory.release(materialId, target.qtyOutstanding);
    }
    final updated = _byId(id);
    if (updated != null) {
      await _sync(
        updated,
        kind: 'request.edit',
        label: 'Material request',
        transactional: true, // releases reservation
      );
    }
  }

  /// Procurement puts a request on hold with a note (FR). Reservation stays.
  Future<void> putOnHold(String id, String note) async {
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            status: RequestStatus.onHold,
            notes: note.trim().isEmpty ? r.notes : note.trim(),
          )
        else
          r,
    ];
    await _persist();
    final updated = _byId(id);
    if (updated != null) {
      await _sync(updated, kind: 'request.hold', label: 'Material request');
    }
  }

  /// Engineer confirms on-site receipt, recording the quantity actually
  /// received per line and flagging any shortfall (FR-088/FR-089). Stock and
  /// reservation were already settled at dispatch, so this only records.
  ///
  /// A received quantity can never exceed what was dispatched to site (you can't
  /// receive valves that never shipped). And a request only closes to `received`
  /// when every line is fully dispatched — if any line still has an outstanding
  /// back-order it stays `partial` so it remains in procurement's queue rather
  /// than being silently closed.
  Future<void> confirmReceipt(String id, List<double> receivedByIndex) async {
    final req = _byId(id);
    if (req == null) return;
    final newLines = <RequestLineItem>[];
    for (var i = 0; i < req.lineItems.length; i++) {
      final l = req.lineItems[i];
      final dispatched = l.qtyDispatched ?? 0;
      final raw = i < receivedByIndex.length ? receivedByIndex[i] : dispatched;
      newLines.add(
        l.copyWith(qtyReceived: raw.clamp(0, dispatched).toDouble()),
      );
    }
    // Any line not yet fully dispatched keeps the request live (queue-eligible).
    final backOrderOpen = newLines.any((l) => l.qtyOutstanding > 0);
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(
            status: backOrderOpen
                ? RequestStatus.partial
                : RequestStatus.received,
            confirmedReceiptAt: DateTime.now(),
            lineItems: newLines,
          )
        else
          r,
    ];
    await _persist();
    final updated = _byId(id);
    if (updated != null) {
      // Records the on-site receipt only (stock already settled at dispatch).
      await _sync(updated, kind: 'request.receipt', label: 'Receipt confirmed');
    }
  }
}

/// Count of open (pending + available) requests across all projects —
/// used by the Engineer Dashboard "Open requests" stat tile.
final openRequestCountProvider = Provider<int>((ref) {
  final all = ref.watch(materialRequestsProvider);
  return all
      .where(
        (r) =>
            r.status == RequestStatus.pending ||
            r.status == RequestStatus.sourcing ||
            r.status == RequestStatus.partial ||
            r.status == RequestStatus.onHold ||
            r.status == RequestStatus.dispatched,
      )
      .length;
});

/// Statuses that put a request in procurement's dispatch queue (the same set
/// the procurement workspace lists). Single source of truth for the count.
const dispatchQueueStatuses = {
  RequestStatus.pending,
  RequestStatus.sourcing,
  RequestStatus.partial,
  RequestStatus.onHold,
};

/// Requests waiting on procurement to dispatch — drives the Home "Awaiting you"
/// KPI and the Materials-hub Procurement badge.
final dispatchQueueCountProvider = Provider<int>((ref) {
  return ref
      .watch(materialRequestsProvider)
      .where((r) => dispatchQueueStatuses.contains(r.status))
      .length;
});

/// Sum of still-outstanding (undispatched) quantities per material across all
/// requests currently holding stock — the authoritative reservation figure.
Map<String, double> _reservationsFrom(List<MaterialRequest> requests) {
  final map = <String, double>{};
  for (final r in requests) {
    if (!kHoldingRequestStatuses.contains(r.status)) continue;
    for (final l in r.lineItems) {
      if (l.qtyOutstanding <= 0) continue;
      map[l.materialId] = (map[l.materialId] ?? 0) + l.qtyOutstanding;
    }
  }
  return map;
}

/// Keeps inventory reservations in lock-step with open requests. Watch it once
/// at the app root: it recomputes and applies reservations whenever the request
/// list changes — first launch (fixing seed requests that reserved nothing),
/// every local edit, and every realtime merge from another device. Reservations
/// are derived, so this is the self-healing source of truth for `reservedQty`.
final inventoryReconcilerProvider = Provider<void>((ref) {
  ref.listen<List<MaterialRequest>>(materialRequestsProvider, (_, next) {
    final reservations = _reservationsFrom(next);
    // Defer out of the listener frame so we never mutate one provider while
    // another is building.
    Future.microtask(
      () =>
          ref.read(materialsProvider.notifier).applyReservations(reservations),
    );
  }, fireImmediately: true);
});

// ─── Seed Data (used on first launch) ───────────────────────────────

// No pre-seeded demo requests — engineers raise real requests as they
// come in during testing/production use.
final _seedRequests = <MaterialRequest>[];

# GodownPro — Architecture & Backend Portability

> **LEGACY — NOT CURRENT PRODUCT AUTHORITY.** This document explains the
> pre-R35 GodownPro/legacy SharedPreferences architecture and is retained only
> as migration evidence. Use [`../AGENTS.md`](../AGENTS.md),
> [`yorks-v1/README.md`](yorks-v1/README.md) and the Yorks V1 contract instead.

This document explains how the app is layered and **exactly how to move it off
local storage onto a real backend (Firebase, or a custom ASP.NET / Node / etc.
server) with minimal, isolated change.** The guiding principle: the UI and
domain logic never know where data lives.

---

## 1. Layers

```
UI (screens, widgets)
        │  watch / read
        ▼
Providers (Riverpod StateNotifiers)      ← app state + business rules
        │  readAll() / writeAll()
        ▼
CollectionStore<T>  (abstract interface)  ← the ONE persistence boundary
        ▲
        │ implemented by
   LocalCollectionStore (SharedPreferences)   ← swap target for Firestore / REST
        │ created by
   Storage  (storageProvider)               ← the SINGLE swap point
```

- **Models** (`lib/shared/models/`) — pure Dart, no Flutter/back-end imports.
  Each has `toJson` / `fromJson`. These are the wire format for any backend.
- **Repositories** (`lib/shared/repositories/`):
  - `CollectionStore<T>` — the abstract port: `readAll()`, `writeAll(items)`,
    `isSeeded`.
  - `LocalCollectionStore<T>` — the local adapter (a JSON list per key in
    `SharedPreferences`).
  - `Storage` + `storageProvider` — a factory that hands a provider its
    `CollectionStore` for a named collection. **This is the only place a concrete
    backend is chosen.**
- **Providers** (`lib/shared/providers/`) — the Riverpod surface the UI watches.
  Every domain provider gets its store from `storageProvider` and calls
  `readAll`/`writeAll`. None of them import `SharedPreferences` (or any backend).
- **UI** — watches providers only.

Device-local settings (selected language, currency, onboarding flag, auth/role
session) deliberately stay on `SharedPreferences` directly — they are
per-device preferences, not backend collections.

## 2. The single swap point

`lib/shared/repositories/storage.dart`:

```dart
final storageProvider = Provider<Storage>((ref) {
  return LocalStorage(ref.watch(sharedPreferencesProvider)); // ← change this line
});
```

To move the **entire app** to a new backend you implement `Storage` +
`CollectionStore<T>` once and return it here. No provider, model, screen, or
widget changes.

## 3. Swapping to Firebase (Firestore)

1. Add a `FirestoreCollectionStore<T> implements CollectionStore<T>`:
   - `writeAll` → a batched set on `collection(name)` (or write deltas).
   - `readAll` → return the latest cached snapshot; attach a `snapshots()`
     listener to keep the provider live.
2. Add `FirestoreStorage implements Storage` returning those stores.
3. Point `storageProvider` at `FirestoreStorage`.
4. Roles come from the Firebase Auth **custom claim** (`request.auth.token.role`)
   — wire it into `currentRoleProvider` and drop the dev role-switcher.
5. Deploy `firestore.rules` (already in the repo root) — it mirrors the in-app
   capability matrix and makes the audit log non-deletable server-side.

## 4. Swapping to a custom server (ASP.NET / REST)

The models' `toJson`/`fromJson` already match a REST contract. Implement:

```dart
class RestCollectionStore<T> implements CollectionStore<T> {
  // readAll()  -> cached list from the last GET /api/{name}
  // writeAll() -> PUT /api/{name}  (or POST/PATCH per item)
}
class RestStorage implements Storage { /* holds baseUrl + auth token */ }
```

- One controller per collection on the server: `GET /api/{collection}` and
  `PUT /api/{collection}` (or finer-grained item endpoints) returning/accepting
  the same JSON the models emit.
- Auth: a bearer token (JWT) carrying the role claim; the server enforces the
  same role × collection × operation matrix that `firestore.rules` documents.
- The audit log (`activityLog`) is server-written and read-only to clients —
  enforce with an endpoint that rejects client writes/deletes.
- Point `storageProvider` at `RestStorage`. Done.

## 5. Going async (when the real backend lands)

The local store is synchronous because `SharedPreferences` is pre-loaded. A
network backend is async. Two clean options:

- **Cache-then-stream (smallest change):** the remote store keeps an in-memory
  snapshot so `readAll()` stays synchronous; a stream listener pushes updates
  into the provider via a small `refresh()` hook. Providers stay
  `StateNotifier`.
- **Async-first (cleaner long term):** migrate the domain providers to
  `AsyncNotifier<List<T>>` and have screens render `AsyncValue`
  (loading/error/data). Larger UI change (loading states everywhere) but the
  idiomatic Riverpod approach for remote data.

Either way the change is confined to the repository layer + provider base class;
models, business rules, routes and most widgets are untouched.

## 6. Conventions that keep it portable

- All persistence goes through `CollectionStore` — never call `SharedPreferences`
  from a provider.
- Every model is pure Dart with `toJson`/`fromJson` (the backend contract).
- Collection keys are versioned (`*_v1`, `materials_list_v3`) so a schema bump is
  a key bump + reseed; with a server these become collection/table names.
- Every mutation funnels through a notifier method and writes an audit entry via
  `ref.logAudit(...)` — so the audit trail survives any backend.
- Atomic-style stock/reservation mutations live in notifier methods (documented
  to become Firestore transactions / server transactions).

## 7. Performance notes

- Lists render with `ListView.builder` / `.separated` (lazy); no full-list
  rebuilds.
- Providers are granular; widgets watch the narrowest provider they need.
  Reach for `ref.watch(p.select(...))` if a widget depends on one field of a big
  object.
- `const` constructors are used throughout to cut rebuild cost.
- `writeAll` rewrites a whole collection — fine for local prototype scale; the
  Firestore/REST adapters should switch to per-item/delta writes for large
  collections.

---

## 8. Offline-first sync (the outbox)

Built for unreliable UAE site connectivity: **every critical write is durable,
idempotent, ordered, and auto-retried until the server confirms it — zero data
loss, zero duplicates.** The whole machinery lives in `lib/shared/sync/` and is
backend-agnostic; it drives a `SyncBackend` that is `LocalSyncBackend` today and
becomes a Firestore/REST adapter with a one-line provider swap.

```
notifier mutation (e.g. addRequest, dispatch, recordPayment)
        │  writes local cache (source of truth) + ref.enqueueSync(...)
        ▼
Outbox (durable queue, persisted via storageProvider, key sync_outbox_v1)
        │  SyncEngine drains in order
        ▼
SyncBackend.apply(op)   ← LocalSyncBackend now │ Firestore/REST later
```

### Pieces
- **`MutationOp`** — one durable unit of work: client-generated `docId`,
  deterministic `idempotencyKey`, target `collection`, `payload` (the record's
  `toJson()`), `kind`/`label`, `isTransactional`, retry `attempts`/`nextAttemptAt`,
  `status`. Persisted (survives restarts).
- **`OutboxNotifier`** (`outboxProvider`) — the queue. **Coalescing enqueue:** a
  second write with the same `idempotencyKey` (default `collection:docId`) updates
  the queued op's payload to the latest snapshot instead of appending — so rapid
  repeated writes to one record (e.g. two partial dispatches) never duplicate and
  never lose the later state.
- **`SyncEngine`** (`syncEngineProvider`, started once in `app.dart`) — drains
  ready ops oldest-first; on success removes them; on `PermanentSyncException`
  (e.g. permission denied) dead-letters them (`status = failed`) for a Retry;
  on anything else (transient/timeout) keeps and backs off
  (`2^attempts`, capped 64s). Flushes on enqueue, on reconnect, and on a 5s
  heartbeat. `retry(id)` / `retryAll()` recover dead-letters.
- **`ConnectivityService`** (`connectivityProvider`, `isOnlineProvider`) —
  abstracted reachability. `DefaultConnectivity` ships now (toggleable via the
  dev "Simulate offline" switch in Settings); `PlusConnectivity`
  (`connectivity_plus`) is the documented production impl.
- **UX** — `SyncStatusBanner` (top of both shells) shows
  Syncing / Offline·queued / Needs-attention(+Retry); `PendingSyncBadge(docId)`
  marks individual rows; `showSyncSnack(...)` never claims server success while
  offline ("Saved offline — will sync when back online").

### Guarantees & where they're proven
- **No loss** — ops persist through `storageProvider`; survive restart; transient
  failures retry forever.
- **No duplicates** — client `docId` + idempotent backend `set`, plus queue-level
  coalescing on `idempotencyKey`.
- **Atomic stock/balance** — ops that move stock or money set `isTransactional`;
  the Firestore adapter applies these in a `runTransaction` (see scaffold in
  `sync_backend.dart`).
- **Ordering** — drained by `createdAt`, oldest first.
- Verified in `test/sync_test.dart` (engine: offline→reconnect, dedupe,
  coalescing, mid-write transient retry, permanent dead-letter+retry) and
  `test/sync_integration_test.dart` (real notifiers across roles:
  queue-offline → flush-once-on-reconnect, zero loss/dupes).

### Enabling Firestore (the only changes needed)
1. Add `firebase_core` + `cloud_firestore`; init in `main()` and set
   `Settings(persistenceEnabled: true, …)` (web: `enablePersistence`).
2. Implement `FirestoreSyncBackend` (scaffold in `sync_backend.dart`) and point
   `syncBackendProvider` at it.
3. Implement `PlusConnectivity` (scaffold in `connectivity_service.dart`) and
   point `connectivityProvider` at it.
4. Swap `storageProvider` to a Firestore-backed `Storage` so reads stream from
   the offline cache (§3). Notifiers, UI, and the outbox are untouched.

# Inventory audit and improvement plan — 8 October 2026

## Scope and conclusion

Audit only, requested by the owner. No application changes, deployment, hosted stock writes, imports, adjustments or permission changes were made. Source inspected at `b9f6b41` (released application source `1a503cf`); live read-only inspection used the production Yorks application. Screens reviewed include Inventory overview, items and item detail, stock commands, categories, reservations, movement history, supplier directory/folder, and the import/export flow. Repositories, providers, models, relevant migrations and focused tests were traced alongside presentation code.

The transactional foundation is substantially stronger than the user experience. Server-side locking, quantity checks, permissions and audit history should be preserved. However, the interface can omit reservations, show stale values, hide older history and handle uncertain saves poorly. Correct these before a visual refresh. This audit identifies concrete defects; it does not certify the entire application as bug-free.

## Findings, ordered by priority

Evidence labels: **reproduced** means a focused local test demonstrated the behavior; **source-confirmed** means the current code establishes the behavior, without a production mutation; **observed** means read-only live browser inspection.

### 1. P1 — Company reservations are absent from the reservation list

**Reproduced locally.** Company requests reserve quantities in the shared inventory reservation table. The Inventory workspace's reservation projection inner-joins only project Material Requests, so company reservations disappear from this list. Balance calculations still include them: an item can show reserved quantity without showing all the demand responsible for it.

- [Workspace projection](../../supabase/migrations/20260809162519_yorks_v1_smart_inventory_categories.sql), `v1_inventory_workspace_projection`, reservation join around line 502.
- [Company fulfilment](../../supabase/migrations/20260917193012_company_material_request_fulfilment_lifecycle.sql), shared reservation ownership and `request_kind`.
- [Company hardening](../../supabase/migrations/20260917201854_company_material_request_end_to_end_hardening.sql), company reservation insertion.

**Impact:** users cannot fully explain reserved stock or identify its owner. This is a visibility defect, not proof that the server allows over-dispatch.

**Fix:** return a role-safe reservation owner shape supporting both Project and Company demand, with correct reference, destination and drill-down. Test that visible reservation quantities reconcile with the stock projection for mixed demand and after cancellation/dispatch.

### 2. P1 — Stock commands lose their retry identity after an uncertain response

**Reproduced for the adjustment form.** Both create-item and adjustment handlers generate a fresh UUID on each Save attempt. A local widget probe simulated a lost response and confirmed that identical adjustment retries used different idempotency keys.

- [Inventory screen](../../lib/features/materials/presentation/screens/yorks_v1_inventory_screen.dart), create-item save around 3354–3400; adjustment save around 4029–4081.
- Compare metadata editing in the same file around 6116–6181, which already retains a command identity for the same payload.

**Impact:** an acknowledged failure and an unknown outcome are presented similarly. For adjustments, expected-version protection normally makes a second new command conflict after the first succeeds; this is **not evidence of an automatic double stock increment**. Nevertheless, the user cannot safely resolve the original result through the intended idempotent retry. Create-item retries need their own lost-response test.

**Fix:** retain the exact pending payload and key until its outcome is known. Separate validation rejection, permission denial, version conflict and unconfirmed network outcome. Reconcile/replay the same command before allowing a new command. Never imply that a timeout proves nothing was saved.

### 3. P1 — Import can be exited while the stock commit is pending

**Source-confirmed; not exercised against production.** The import footer disables actions during commit, but the header Cancel remains connected. The route has no equivalent exit guard, and the import controller is auto-disposed. Leaving can discard the in-memory command/result while the server continues committing.

- [Import screen](../../lib/features/materials/presentation/screens/yorks_v1_inventory_import_screen.dart), header around 211 and 682; busy footer around 4044–4071.
- [Import provider](../../lib/shared/providers/yorks_v1_inventory_workbook_provider.dart), auto-disposed controller.
- [Import controller](../../lib/shared/controllers/yorks_v1_inventory_import_controller.dart), `commit`.
- [Router](../../lib/app/router.dart), Inventory import route around 2054.

**Fix:** use one route-level pending-command policy for header Cancel, shell Back, browser Back and mobile navigation. Preserve enough recovery identity to resolve a pending import after navigation/reload. Existing server fingerprint and ordinary retry protections must remain. Test a delayed successful response, delayed rejection, retry, route disposal and reopening; no success banner before server confirmation.

### 4. P2 — Negative corrections are rejected by the form

**Reproduced locally.** Client validation rejects every quantity at or below zero, while the server permits a signed, nonzero correction. The save button also remains “Add / Receive Stock” when a different action is selected.

- [Inventory screen](../../lib/features/materials/presentation/screens/yorks_v1_inventory_screen.dart), validation around 4036 and action button around 3989.
- [Stock command SQL](../../supabase/migrations/20260809174308_yorks_v1_inventory_category_families_commands.sql), `v1_adjust_inventory_stock`, around 458–532.

**Fix:** align client/server semantics and action labels. Show current quantity, change and resulting quantity before submission. Keep removal and correction distinct in movement history, require the correct reason, and preserve the reserved-stock floor. Do not introduce “physical count” semantics without explicitly designing their conversion to a server-checked delta.

### 5. P2 — Inventory lacks a consistent freshness contract

**Source-confirmed.** Workspace and item-detail providers fetch from the repository but do not subscribe to the refresh revision used by neighboring logistics providers. Own-screen commands invalidate some data, but the import commit provider does not invalidate the Inventory workspace. Exact stale duration depends on retained routes and subsequent navigation.

- [Logistics providers](../../lib/shared/providers/yorks_v1_logistics_provider.dart), first two providers, lines 11–24.
- [Import provider](../../lib/shared/providers/yorks_v1_inventory_workbook_provider.dart), successful commit mapping.

**Fix:** add authority-scoped, coalesced refresh signals and explicit invalidation after successful commands/imports. Refresh on foreground return where appropriate. Show “Updated …” and a stale/retrying state; a connection indicator must not imply that stock is current. Test changes made by another user, returning from import, reconnect, and permission/account changes. Cache isolation on authority changes remains an explicit verification requirement, not a confirmed leak finding.

### 6. P2 — History is incomplete globally and unbounded per item

**Source-confirmed.** The workspace returns only the latest 100 movements; the history screen filters that subset locally without a way to load older records. Conversely, item detail aggregates all movements for an item without pagination.

- [Workspace SQL](../../supabase/migrations/20260809162519_yorks_v1_smart_inventory_categories.sql), `recent_movements`, `limit 100` around 481.
- [Item detail SQL](../../supabase/migrations/20260802040000_yorks_v1_batch7_logistics.sql), movement aggregation around 316–364.
- [Movement UI](../../lib/features/materials/presentation/screens/yorks_v1_inventory_screen.dart), `_MovementsTab`, around 2424.

**Impact:** “no results” can mean “not in the newest 100,” while a busy item's detail can grow expensive indefinitely.

**Fix:** server-filtered, cursor-paged movement history with date range, actor/type/reference filters, explicit result scope and load-more. Use stable timestamp/ID ordering. Paginate item history independently of its stock summary. Preserve immutable facts and role-safe responses.

### 7. P2 — Movement export produces a stock register

**Source-confirmed.** The shared export callback invokes `saveStockRegister` and is also passed to the movement screen. It exports the stock snapshot rather than the history currently being explored. Current local filters do not define that export's scope.

- [Inventory screen](../../lib/features/materials/presentation/screens/yorks_v1_inventory_screen.dart), export around 239, callback passed around 435 and movement toolbar around 2580.

**Fix:** separate “Export stock” and “Export movements,” with explicit current-filter/all-records scope. Provide the same dataset and units for Excel and print. Test contents and permissions, not just whether a file downloads. Do not silently truncate exported movement history to 100 rows.

## UI and UX assessment

### What to retain

- Universal Yorks navigation, permission-based actions and familiar internal sections.
- Clear on-hand, reserved and available quantities in item detail.
- Lazy `ListView.separated` item builders on desktop and mobile; this is not an eager-render-every-row problem.
- Import review before commit, row-level feedback, supplier receipt provenance and separate quantities by unit.
- Supplier search already has debounce and paged results; reuse that approach.

### Friction observed

- At 360px, the heading, explanatory paragraph and four full-width actions consume much of the first screen. Finding stock is not the first obvious task.
- Horizontal navigation clips later sections. Reservations and Suppliers are less discoverable on a phone.
- Repeated actions across page header, quick tools and table toolbar compete for attention. Suppliers has multiple entry points.
- The desktop stock table uses a 1600px minimum width, forcing horizontal movement at ordinary office widths; the identity column is not frozen horizontally.
- Supplier pages can show the shell breadcrumb as Overview rather than the Inventory location. Returning should retain search, filters and scroll position.
- The supplier folder hero gives long explanatory totals more space than the working list. Keep quantities separated by unit, but show them compactly.
- “Healthy” with no configured minimum can be mistaken for evaluated stock health. Show “No minimum set” separately from “Above minimum.”
- Historical Unknown Supplier review counts need an explanation and a valid next action. The approved contract does not authorize silently reassigning historical supplier identity.
- Read failures reuse wording about an unconfirmed save. Empty, loading, forbidden, stale and failed states need distinct messages.

### Proposed structure

Keep one **Inventory** entry in the universal sidebar. Inside it use **Stock**, **Reservations**, **History**, and **Suppliers**; offer a compact overview without forcing it before stock lookup. Categories and other administration sit under a secondary menu for permitted users.

**Desktop:** restrained Codex-like spacing and typography using existing Yorks tokens; one primary action, search and compact filters above a readable table; sticky item identity and header; keyboard focus and predictable Enter/Escape; item detail in a consistent panel or full page. Group Import, Export and Print in clearly labeled menus rather than scattering them.

**Mobile:** search near the top, compact stock cards with item/unit/available/reserved, a visible section selector, and one accessible primary action. Open a focused item/action screen instead of shrinking the desktop grid. Use 44px minimum targets, short plain-language labels and progressive disclosure for optional metadata. Explain quantities with labels, not color alone. Preserve English and configured secondary languages, RTL and reduced-motion behavior.

The HCI priorities are recognition over recall, visible system status, consistent navigation, error prevention, recovery after mistakes, and less competing information. Test the proposed screens with warehouse staff doing real lookup, receiving and correction tasks before broad rollout.

## Performance assessment

One production read returned **1,157 items**; observed response-header timing was approximately **2.11 seconds**, with about **93,412 encoded bytes**. This includes network/server wait and is one sample, not database execution time, a percentile or a general service-level claim.

The main workspace loads the whole inventory and applies UI filters locally. SQL invokes item projections and correlated movement calculations; parent filtering scans loaded items on each search change. Combined with unbounded item history, this is a scaling concern even though row rendering is lazy.

Recommended work:

1. Separate small summary reads from paged stock, reservations and history queries.
2. Move filtering/sorting to authorized server queries; debounce search and discard stale responses.
3. Inspect local representative `EXPLAIN (ANALYZE, BUFFERS)` results before selecting indexes or rewriting SQL; avoid speculative indexing.
4. Preserve loaded results during background refresh and coalesce events instead of refetching on every event.
5. Benchmark web import preparation with representative larger files. `compute` alone does not prove work is off the browser's main thread; assess chunking/worker options only if measurements warrant it.
6. Measure load/search latency, errors, retry resolution and export/import completion. Actual stock searches currently filter locally while repository search telemetry depends on a nonempty server query, leaving a measurement gap. Record durations/counts/outcomes rather than raw search text or sensitive stock contents.

Proposed acceptance targets must be established against a documented device/network and representative inventory sizes. Record p50/p95, request count, payload size and input responsiveness before and after; do not declare success from a single faster sample.

## Backend, security and maintainability

The reviewed stock command rechecks authority, claims idempotency, locks the balance, checks version and quantity constraints, and writes audit/history server-side. Preserve these. Realtime is a refresh signal only. Do not replace trusted commands with generic JSON updates or optimistic stock changes.

Maintain exact permissions: Admin/Procurement mutations and supplier access; Senior Mechanical Engineer's authorized Inventory read does not confer stock/supplier mutation rights. Positive and negative role tests must cover direct API/RPC paths as well as hidden buttons. Preserve commercial response boundaries, immutable history, supplier provenance, import fingerprints, opening-balance cutoffs, unit precision and damaged/rejected quantity rules.

The Inventory, import and supplier presentation files collectively contain roughly **15,900 lines**. Large widgets make command lifecycle and navigation mistakes harder to isolate. Extract action controllers, shared operation-state handling and small presentation components incrementally alongside regression tests. Do not undertake a broad architectural rewrite or alter unrelated modules.

## Implementation sequence and acceptance

| Phase | Scope | Acceptance gate |
| --- | --- | --- |
| 1 — Correctness | Company reservations; stable stock retry; signed correction; pending import navigation | Mixed-demand reconciliation; lost-response replay; competing writers; negative/positive correction; exit/reopen while committing; role denial tests |
| 2 — Trustworthy reads | Refresh/invalidation; paged history; matching exports | Two-user refresh; foreground/reconnect; old movement retrieval; exact filtered export/print dataset; no cross-authority cache reuse |
| 3 — Simple workflows | Stock-first layout; mobile item/action views; consistent supplier navigation; labels and error states | Desktop and 360px evidence; keyboard and touch tasks; secondary-language/RTL review; staff task completion with fewer steps and no assistance |
| 4 — Measured performance | Query shape, paging, debounce, render/import profiling and telemetry | Repeatable before/after measurements; no permission/quantity regressions; large-data and slower-device tests |
| 5 — Release | Staging review, scoped regression gates and production authorization | Existing Flutter/database gates; focused personas; migration preservation/rollback notes; verified deployed artifact and read-only live smoke |

Each phase should be a coherent small change. Existing live data stays intact. Additive migrations only where needed. Keep the current implementation available for rollback. This audit is not authorization to import stock or release these proposed changes.

## Verification and limitations

Current audit checks:

- `flutter analyze`: **no issues**.
- Seven focused Inventory Flutter suites: **125 passed, 3 existing skips**.
- Eight local database test files: **219 passed**.
- Additional rollback-only Company reservation probe: **17 checks, one deliberate failing expectation**, demonstrating that an expected company reservation is absent.
- Additional widget characterization probe: **passed**, demonstrating fresh retry keys and blocked negative correction. This records existing behavior; it is not a regression fix.
- Live desktop and 360px inspection, with read-only network timing. No production stock mutation.

Evidence is stored locally in `/private/tmp/yorks-inventory-audit-20261008/`: desktop home, item detail, supplier directory/folder and 360px home screenshots; `company-reservation-probe.sql`; `stock-retry-probe.dart`. Logs: `/tmp/yorks-inventory-audit-tests.log`, `/tmp/yorks-inventory-audit-db.log`, `/tmp/yorks-inventory-audit-probe-db.log`, `/tmp/yorks-inventory-audit-probe-ui.log`, `/tmp/yorks-inventory-audit-analyze.log`. Temporary test code was removed from the application worktree.

Not claimed: fresh full-repository test/build gates, production write-path reproduction, every live role persona, physical-device coverage, prolonged multi-user/offline testing, large-import stress testing, or a database load benchmark. These belong to implementation acceptance. Focused passing tests do not negate the reproduced coverage gaps above.

Exact additional migration reference: `supabase/migrations/20260917201854_company_material_request_end_to_end_hardening.sql` (company reservation insertion).

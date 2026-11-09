# Procurement workspace review and improvement plan

Date: 8 October 2026
Status: **historical audit and approved proposal**. Subsequent implementation and staging evidence are tracked in [PROCUREMENT_IMPLEMENTATION_20261008.md](PROCUREMENT_IMPLEMENTATION_20261008.md).
Reviewed source: `2290cf5` on `codex/workforce-mobile-attendance`
Priority confirmed by the product owner: **desktop for both arrangement and dispatch**.

## 1. Recommendation

Make Procurement a focused workspace inside the existing Material Request
experience. The daily job should be easy to follow:

**Open work → arrange materials → review and save arrangement → prepare dispatch
→ review and dispatch → preview or print the delivery document.**

Use the existing office sidebar, top bar, seven-stage context, typography and
controls. Give most of the working area to the materials and their quantities.
Place request information and occasional actions in an optional side panel.

The underlying system already has important controls: protected commands,
decimal quantities, reservations, expected versions, idempotency and immutable
document revisions. However, these do not yet produce a consistently safe,
efficient editing experience. Fix the stock defect and unfinished-work recovery
before changing the layout.

### Scope and evidence boundaries

- Reviewed the supplied Procurement screenshot, current arrangement, dispatch,
  dispatch-centre and document source, their providers/repositories, critical
  command persistence, effective local dispatch SQL and relevant tests.
- Inspected the supplied staging request. The current browser session showed
  Local Admin, while the user's arrangement screenshot showed Procurement.
  This is not a complete live Procurement-persona acceptance test.
- Ran 64 focused Flutter tests successfully. Reproduced the shared-stock defect
  through local RPCs in a transaction that was rolled back.
- No production incident, stock discrepancy or production-data impact has been
  established by this audit. No remote mutations, release or application fixes
  were performed.
- Performance findings below identify code paths to measure. They are not
  measured production latency or frame-rate results.

## 2. Preserve the current workflow contract

The [current operating guide](CURRENT_MATERIAL_REQUEST_USER_GUIDE.md) and
[approval-first decision](MATERIAL_REQUEST_FLOW_REVISION_2026-08-13.md) govern
new requests: Engineering approves the need first; Procurement's complete
arrangement makes positive quantities ready for dispatch. Do not introduce a
routine second Engineering approval. Preserve the legacy arrangement-approval
lane for historical records.

Preserve these rules throughout the redesign:

- Full, Partial and Cannot Provide Now remain explicit per-line decisions.
  Partial/unavailable reasons remain required; unavailable lines remain visible.
- Warehouse and External Supplier remain the supported source choices. This
  proposal does not add split sourcing within one request line, RFQs or POs.
- Requested identity remains immutable evidence. Procurement clarification of
  the effective item/model follows the existing controlled revision and
  Engineering review lock.
- Saving progress is private work, with no reservation or workflow effect.
  Saving the final arrangement changes reservations atomically.
- Dispatch is a server-confirmed stock transaction. A receipt and a return
  remain separate facts with their existing responsibilities.
- Supplier-name optionality and external readiness requirements follow current
  published policy; presentation changes do not silently create new requirements.
- Commercial data remains capability-controlled in reads, state, caches,
  documents and exports. Never recover unit costs from browser preferences.
- Project and Company Use may share presentation components, but retain their
  separate authority, beneficiaries and command contracts.

This plan extends the existing proposed
[Arrangement Workbench SRS](ARRANGEMENT_WORKBENCH_SRS.md) and
[A0–A6 implementation plan](ARRANGEMENT_WORKBENCH_IMPLEMENTATION_PLAN.md).
Their recovery and parity requirements still apply. Those documents are plans,
not evidence that Save progress already exists.

## 3. Findings, ordered by importance

| ID | Finding and evidence | Effect | Priority / action |
|---|---|---|---|
| F1 | **Reproduced locally:** dispatch validates warehouse availability separately for each line before updating balances. Two replacement lines using the same stock item can together consume another request's reservation. | Another request can retain a reservation greater than the stock left to fulfil it. A nonnegative balance alone does not prevent this. | **P1, first fix.** Group the proposed quantities by inventory item under the existing locks and validate the complete transaction. |
| F2 | **Confirmed in source:** arrangement and dispatch text buffers are screen-owned and disposed on exit. The arrangement modal is dismissible; editor PopScope protects busy work, not dirty work. The final arrangement command is the only save exposed. | Procurement can lose unfinished sourcing, quantities and delivery details by leaving or reloading. | **P1.** Private Save progress, explicit save status, safe navigation and exact recovery. |
| F3 | **Confirmed in source:** dispatch adds only positive parsed quantities to the payload. A valid negative number is silently skipped if another line is positive. | The user can believe a line was included when it was omitted. The server correctly rejects negatives it receives, but this client drops them first. | **P1.** Reject negative input on the exact row; explicitly distinguish excluded rows from invalid quantities. |
| F4 | **Confirmed in source:** the Dispatch Centre's Ready count/classification includes approved and partially dispatched only. The logistics projection also permits partially received requests, where replacements may be outstanding. | Ready counts can understate Procurement's work. Such records can still appear under Attention/receipt review; they are not entirely inaccessible. | **P2.** Derive actionable dispatch/replacement cues from authorized server projections and remaining quantities. |
| F5 | **Confirmed in source:** a selected warehouse item gets a green check when its available quantity is positive, rather than sufficient for the planned quantity. Search ranks all same-unit items and returns eight even when the query matches none. | The picker can suggest confidence or relevance that has not been established. Long labels also hide identity and availability in the screenshot. | **P2.** Separate identity, selection confirmation and quantity sufficiency; show genuine no-match results. |
| F6 | **Confirmed in screenshot/source:** a large modal, nested cards, five summary tiles, a persistent rule banner and repeated per-row actions consume the working area. The desktop table builds every row inside scroll views. | Only a few materials are visible; users scroll and repeatedly interpret controls. Large requests have a credible rendering cost. | **P2.** Full-width workspace, compact rows, sticky identity/header, focused detail panel and measured list virtualization. |
| F7 | **Confirmed code gap; race not reproduced:** command-key storage retains fingerprint/UUID, not the complete editable input. Both editors unlock after a caught failure without a dedicated uncertain-outcome state. Arrangement request version can refresh while same-arrangement input retains its old base. | Timeout, refresh and competing edits are difficult to understand or safely resume. Existing version/idempotency guards still matter; this is not proof of duplicate stock commits. | **P1 design requirement.** Freeze the exact pending intent, reconcile its outcome, then allow explicit rebase/edit. |
| F8 | **Confirmed in source:** the delivery-document card renders and exports the current revision. Current revision can become a receipt-reviewed report; the original dispatch snapshot remains historical. | Procurement needs a clearer choice between what was sent and what the site accepted. | **P2.** Explicit document kind/revision selector, original dispatch note and latest receipt report. |

### F1: local stock witness

The fixture used the current approval-first RPC flow, not a synthetic direct
balance overwrite:

1. Request A has two lines for the same warehouse item, four units each.
2. Dispatch all eight; the site reports both lines fully missing. A's original
   reservations are consumed, and both lines are replacement-eligible.
3. Replenish six units. Request B reserves four. Two are available to A.
4. Ask to dispatch two units for each A line: four in total.
5. Each individual line passes the two-unit availability check. The command
   commits, leaving **two on hand while B still reserves four**.

Observed local output:

```text
BEFORE: on_hand=6.0000, other_request_reserved=4.0000
AFTER: rejected=f, on_hand=2.0000, other_request_reserved=4.0000
ROLLBACK
```

This used the local database with 191 migrations through `20261008080029`.
The fixture creates setup through trusted RPCs with seeded local actor claims;
the harness is run by the local test database owner. It is a transaction-logic
witness, not an independent authenticated RLS test. Follow-up checks found zero
remaining audit projects and zero audit inventory items.

The [reproduction script](evidence/procurement-review-20261008/shared_stock_repro.sql)
and [evidence record](evidence/procurement-review-20261008/README.md) preserve the
case. A fix must add a failing regression test first, then cover Project and
Company reservations, retries and competing writers.

### What already works and should be retained

- Arrangement already validates totals across lines using the same warehouse
  item and accounts for eligible existing reservations. F1 concerns dispatch;
  it is not evidence that arrangement lacks its aggregate validation.
- The picker already restricts candidates to matching units.
- Current arrangement tests cover optional external supplier names, readiness,
  zero stock, retained reservations, clarification and 360px behavior.
- Server commands already enforce positive quantities, approved caps, roles,
  state/version checks, locks, idempotency and stock movements.
- Delivery output already uses immutable revisions and shared rendering/export
  services. Extend those, rather than introducing another document generator.

## 4. Target desktop experience

### 4.1 Home and navigation

Use Material Requests → My Work as the main entry point. Keep the familiar
seven-stage context and direct Arrange / Continue arrangement / Dispatch
actions. Dispatch Centre remains an alternate cross-project view of the same
work, with consistent labels and actions.

Each request shows its project/scope, request number, required date when set,
current owner and next action. Use useful filters such as arrangement needed,
ready to dispatch and replacements; derive them from protected action data.
Do not manufacture overdue SLA dates or new workflow statuses.

Preserve the originating view, filters and scroll position when the user returns.
Use the universal top-bar Back button through the same pending-work guard as
route/browser navigation. Avoid another permanent header or duplicate Back row.

### 4.2 Arrangement workspace

Open a full-width workspace under the existing Yorks shell. A compact header
provides request context, current stage, save status and Request information.
The information panel is closed by default and remembers the user's choice.

Conceptual layout:

```text
Yorks universal sidebar and top bar
Arrange materials        MR number · Project / Building       Saved progress
Existing seven-stage context                         Request information

Search materials…       All · Needs attention · Warehouse · External
──────────────────────────────────────────────────────────────────────────
Item / identity | Requested | Decision | Source / Available | Supply | Cost*
──────────────────────────────────────────────────────────────────────────
Compact editable material rows; active row can open a details panel
──────────────────────────────────────────────────────────────────────────
48 of 50 lines ready · 2 need attention       Save progress   Review arrangement

* Only when authorized
```

#### Main table

- Keep the item identity and column header visible during scrolling.
- Show requested quantity beside arranged quantity, always with its unit.
- Use compact, consistent decision/source controls. Required exceptions expand
  in place or in the focused row panel, with a visible row marker.
- Move repeated Edit item details and Create inventory item actions into the
  relevant row/picker menu. Do not hide required reasons or stock shortages.
- Search across visible item identity, brand, size and planning model. Filters
  never change the scope of validation: all request lines are still checked.
- Counts become useful filters or one short progress sentence. Show the stock
  rule as contextual help, rather than a full-width permanent banner.
- Focus the first invalid cell on review, with a linked summary of all affected
  rows. Preserve the user's input when stock or server validation rejects it.

#### Warehouse picker and stock explanation

Show item code and description on one line, with brand/unit/stock information
below. Keep selected identity readable after the menu closes. Exact matches
rank first; unrelated items must not masquerade as search matches. An empty
search may offer clearly labelled suggestions.

Show distinct facts where relevant:

- **Selected item:** confirms the catalogue link only.
- **Available to this request:** authorized current stock after other claims.
- **Planned across this request:** total across every line mapped to this item.
- **Short by:** the difference requiring action.

For example, if two lines plan 21 and 11 against 27 available, show “32 planned
across 2 lines · short by 5” on both affected rows. This is an explanatory
example, not a conclusion that the screenshot's two Access Doors share an ID.

Availability has loading, current, stale and unavailable states. An unknown
quantity must not be shown as zero or as sufficient. Refresh does not silently
change the selected inventory item, quantity or decision.

#### External supplier and clarification

Show supplier/reference/expected date/readiness only for External Supplier.
Requiredness comes from the current policy; optional fields remain optional.
Partial and unavailable reasons appear beside the affected line. Use everyday
language and existing localized strings.

Keep the original request available for comparison. If an item clarification
requires Engineering review, show the changed fields and the review state;
prevent operational final save until that exact revision is accepted.

### 4.3 Save, resume and review

Expose two distinct actions with visible outcomes:

| Action | Meaning | User feedback |
|---|---|---|
| Save progress | Saves incomplete private work; does not reserve stock or move the request | Saved time, location and owner; explicit failure if not saved |
| Review arrangement → Save arrangement | Validates every line, refreshes relevant authority/stock, then explicitly commits the arrangement | Server-confirmed reservation/workflow result and next action |

Use the existing proposed three-layer model: noncommercial device recovery,
owner-private protected server checkpoint including permitted commercial fields,
and the final arrangement transaction. Show these truthfully; a device recovery
copy is not a server checkpoint and neither is a completed arrangement.

All exit paths share one guard. A dirty editor offers Save progress and leave,
Keep editing, or deliberate Discard. Browser termination relies on previously
persisted recovery, not an asynchronous unload save. Never silently discard
corrupt/unknown recovery records.

During a final command, freeze its input and key. If the response is lost, show
“Checking whether this was saved” and resolve that attempt before accepting a
different final command. Retry the same intent/key; do not automatically submit
on reconnect. On a version conflict, retain permitted input and show the changed
server facts before an explicit rebase.

The review screen summarizes Full/Partial/Unavailable decisions, shortages,
external readiness and authorized cost totals. The final button remains a
deliberate action; ordinary Enter or Save-progress shortcuts never reserve stock.

### 4.4 Dispatch workspace

Present the chosen request and destination prominently, followed by one compact
line table. Default quantities can remain useful suggestions, but must be
allocated across shared stock rather than independently per line.

Suggested columns:

**Include · Item · Approved remaining · In transit · Available · Send now · Unit**

Show source and replacement context on the affected row. “Approved remaining”
must follow the canonical good-received/in-transit calculation, not a casual
requested-minus-dispatched subtraction. Do not silently shrink a user's entry
after a refresh.

- Explicit inclusion controls distinguish “not sending” from malformed input.
  Reject negatives and excess quantities on the exact row. Never silently omit
  an entered negative quantity.
- Let users select all eligible lines or clear the selection, with local Undo.
  Show how many lines and which quantities will be sent.
- Keep the current required delivery reference. Label driver/vehicle/date
  consistently with current rules; do not make optional metadata compulsory.
- Use Save progress for an unfinished manifest without creating a dispatch.
- The sticky primary action is **Review dispatch**. Review shows destination,
  metadata, included quantities, omitted lines and the stock effect. **Confirm
  dispatch** performs the existing trusted transaction once.
- The confirmed result shows the dispatch number, next owner/action and
  **Preview delivery note / Print / Download**. Document generation failure
  retries the document operation, never the already committed dispatch.
- A timeout follows the same frozen-intent and outcome-reconciliation pattern
  as arrangement. An unconfirmed operation is never displayed as successful.

A printable picking list is useful before dispatch, but must be clearly marked
as a draft preparation document. Printing it must not deduct stock or create an
official Delivery Order. This can follow the core flow if user testing confirms
it is useful.

### 4.5 Delivery note and receipt report

Use a clean preview with a small toolbar: **Print · Download PDF · Export Excel**
and a document-kind/revision selector. Show request, dispatch, document number,
date, project/scope and destination in consistent positions.

Clearly distinguish:

1. **Delivery Order — dispatched quantities:** immutable evidence of what was sent.
2. **Delivery Report — receipt-reviewed quantities:** the later immutable report
   showing good-received quantities and its review context.

The [existing decision](PRODUCT_DECISIONS.md) permits the current printable
revision to become the receipt report. Keep it; also make the retained original
dispatch revision accessible. Do not reconstruct a historical document from
today's editable inventory or treat returns as edits to its original quantities.

Preserve the approved four columns (S.No, Description, Qty, Unit), frozen
size/planning-model data and protected commercial omission. Preview, PDF, Excel
and print must show the same selected revision. Printing an older version must
keep its identity clear. Never imply a physical signature or site confirmation
exists because someone generated a document.

## 5. Desktop efficiency and accessibility

- Use shared AppColors, AppSpacing, AppTypography and controls. Prefer quiet
  surfaces, restrained borders, clear text and a single primary action.
- Tab/Shift+Tab move between editable cells; Enter/Shift+Enter move predictably
  between rows when not selecting a dropdown or entering multiline text.
  Arrow behavior must respect text editing and dropdown navigation.
- Cmd/Ctrl+S saves private progress only. Cmd/Ctrl+Z and platform-standard redo
  affect uncommitted edits; never offer Undo for a committed stock transaction.
  Batch changes have their own undo boundary and visible affected-row count.
- Show platform-appropriate shortcut hints. Escape closes a picker/panel before
  navigating away; dirty navigation still uses the shared guard.
- Maintain visible focus, labelled controls, accessible error associations and
  status announcements. Color alone must not communicate stock sufficiency.
- Test long names, 200% text zoom, keyboard-only operation, English and the
  configured secondary language/RTL. A screenshot is not a contrast audit.
- Mobile remains a companion: card list, focused one-row editor, persistent
  save/review actions and at least 44×44 tap targets per the Yorks contract.
  It must use the same state/validation logic, not a squeezed desktop table.

These recommendations apply visibility, error prevention, recognition and user
control from [Nielsen's usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/).
Use [WCAG 2.2](https://www.w3.org/TR/WCAG22/) for the accessibility acceptance
review. The 44px mobile target is the repository's design requirement; do not
misstate it as the WCAG AA minimum.

## 6. Technical approach

### Frontend and state

Extract a typed Riverpod editor/controller that owns raw input, stable edit base,
dirty state, validation, private checkpoint state and pending command outcome.
Desktop and mobile compose it. Widgets remain presentation; they do not call
Supabase directly.

Separate server-accepted data, local edits, display filters and an in-flight
intent. Explicitly flush focused input before saving or authority transitions.
Preserve authorized current-owner recovery while clearing revoked protected
projections. Scope all caches and recovery by backend, actor and entity/version.

Retain the current protection against realtime rebuilds destroying controllers.
Realtime should mark data for authorized refresh, then show what changed without
overwriting edits. Do not make refreshing a permission snapshot implicitly
accept a new edit-base version.

### Backend and quantities

- Fix F1 in the effective trusted dispatch function: lock inventory in stable
  order, sum all proposed warehouse quantities per inventory item, subtract
  competing live reservations once, and reject an aggregate shortage before
  allocating numbers or writing movements. Preserve per-line approved caps,
  exact decimal arithmetic and all idempotency checks.
- Verify shared reservations from both Project and Company workflows. Confirm
  that a missing/damaged replacement cannot spend someone else's reservation.
- Add the owner-private checkpoint and outcome-readback contracts described in
  A1. Store authorized commercial fields in protected server storage, using
  explicit omission/clear semantics. Never widen Engineering's reads.
- Progress saves must recheck authority and expected checkpoint versions. Final
  commands recheck workflow versions, stock and state independently.
- Build a bounded protected queue projection for ready/replacement work if the
  existing authorized summary cannot express it. Do not call every request's
  detail projection merely to calculate the home-screen counts.
- Any migration must be additive, preserve IDs/history, include rollback notes
  and ship with positive/negative permission tests. No historical reconciliation
  or automatic stock adjustment is authorized by this audit.

### Performance

Current hotspots are eager row construction, whole-inventory loading and
per-picker sorting, plus Dispatch Centre filtering/paging after receiving the
request list. Prioritize these measured changes:

1. Profile 20/100/500-line requests within supported server limits, with the
   production-shaped catalogue, before setting budgets.
2. Build only visible table rows while keeping editor state outside row widgets.
   Preserve stable focus and scroll during validation and refresh.
3. Use bounded, debounced catalogue search with unit filters and deterministic
   ranking. Retain selected items even if not on the current result page.
   Handle late responses and real zero matches explicitly.
4. Load optional history/documents/information panels on demand. Coalesce
   protected reads and reuse authority-scoped data only where safe.
5. Page large work queues at the server with stable ordering and accurate counts.
   Verify query plans before adding indexes or changing database functions.

Provisional acceptance targets, to calibrate against A0 measurements: visible
typing feedback within 100ms, no lost keystrokes/focus, no UI freezes during row
filtering, and useful loading/error feedback throughout server operations.
Report p50/p95 server time separately from rendering/network time; do not promise
fixed API latency from this source audit.

### Product measurement

Extend existing arrangement/command telemetry with an allowlisted set of counts,
timings, action/result codes, viewport class and recovery outcomes. Measure time
to finish, rows corrected, save/retry failures, resumed progress and successful
document output. Do not log names, supplier text, quantities/cost values, free
text, document contents or raw payloads. Audit replay masking before enabling
any form capture. Telemetry failure must never block Procurement's work.

## 7. Ordered implementation plan

| Slice | Deliverable | Acceptance gate |
|---|---|---|
| A0 + targeted correctness | Freeze current parity; turn F1/F3/F4 into regression cases; correct transaction aggregation, invalid row handling and Ready classification | Shared-item replacements cannot consume competing reservations; every invalid row is identified; authorized replacement work is discoverable |
| A1–A2 recovery foundation | Owner-private progress, noncommercial device recovery, typed editor state, one navigation guard and uncertain-command reconciliation | Save/leave/resume/reload preserves permitted input; private costs remain protected; response loss and competing tabs cannot silently overwrite or duplicate work |
| A3 desktop arrangement | Full-width shell integration, compact spreadsheet, proper picker, conditional details and sticky review/save actions | Complete parity for Full/Partial/Unavailable, external readiness, clarification locks, costs and legacy records; keyboard and large-list evidence |
| D1 desktop dispatch | Shared-stock suggestions, precise validation, manifest review, recoverable preparation and confirmed-result actions | Partial/replacement dispatch, competing stock use, retries and document failures work without extra movements |
| D2 delivery documents | Clear original/current revision choice, consistent preview/print/PDF/Excel and optional draft picking list | Export/print matches selected immutable revision before and after receipt/return; no commercial leaks |
| A4 mobile parity | Focused row editing and compact review using the same controller | 360px/phone usability, keyboard-safe footer, 44px targets, no desktop-grid squeeze |
| A5 verification and staging | Full applicable automated gate, visual/accessibility checks and observed Procurement UAT | No unexplained regression; concrete before/after task results; permissions and Engineering/Company flows retained |
| A6 separate release | Record source, migration/artifact evidence, rollback and explicit owner release authorization | Staging acceptance and deployment verification recorded distinctly |

Deliver each coherent slice independently. The stock fix can be reviewed and
released ahead of the broader UI, with its own gates and release authorization.
Do not wait for a complete redesign to correct a transaction defect.

### Exact surfaces affected when implementation is approved

| Area | Current source / extension point |
|---|---|
| Arrangement and picker | [arrangement screen](../../lib/features/materials/presentation/screens/yorks_v1_arrangement_screen.dart), [provider](../../lib/shared/providers/yorks_v1_arrangement_provider.dart), [repository](../../lib/shared/repositories/yorks_v1_arrangement_repository.dart) |
| Entry/navigation | [Material Request screens](../../lib/features/materials/presentation/screens/yorks_v1_material_request_screens.dart), [router](../../lib/app/router.dart) |
| Dispatch editor and queue | [logistics screen](../../lib/features/materials/presentation/screens/yorks_v1_logistics_screen.dart), [Dispatch Centre](../../lib/features/materials/presentation/screens/yorks_v1_dispatch_centre.dart) |
| Documents | [returns/documents screen](../../lib/features/materials/presentation/screens/yorks_v1_returns_documents_screen.dart), existing logistics document services and protected revision projections |
| Critical commands | [workflow controller](../../lib/shared/controllers/yorks_v1_material_workflow_command_controller.dart), [command key store](../../lib/shared/services/yorks_v1_critical_command_key_store.dart) |
| Server | Effective `v1_dispatch_materials`, stock/reservation helpers, arrangement/progress projection and trusted RPCs; additive files under `supabase/migrations/` |
| Recovery additions | Proposed typed progress model, editor controller/provider, local recovery store and protected progress repository mapped in the existing A1–A2 plan |

## 8. Acceptance tests that matter

### Quantity and workflow

- Same stock item across two or more MR lines; aggregate exactly available,
  above available, shared with another Project MR and with Company Use.
- Replacement after missing/damaged receipt, consumed own reservation,
  partially consumed reservation, mixed sources and decimal quantities.
- Two Procurement users saving/dispatching concurrently; stale versions rejected
  with input preserved; same-key retry returns one result/movement/document.
- Negative, empty, zero, malformed and excess quantities; hidden/filter-excluded
  rows are still included in validation when relevant.
- All-unavailable arrangement, optional supplier name, configured readiness,
  clarification pending/approved/rejected and legacy arrangement approval.

### Recovery and authorization

- Back, Close, click outside old modal, route switch, browser reload, tab close,
  lost connectivity, storage failure/quota and malformed recovery.
- Save progress on one request, work on another, then resume the correct owner
  checkpoint. Simultaneous tabs must not overwrite a newer checkpoint silently.
- Lost response before commit versus after commit; resume and retry using the
  same frozen intent. Change of role/project access during editing or saving.
- Positive/negative Project Engineer, Site Engineer, Procurement and Admin
  tests; Accountant/global-role/scoped capability coverage wherever affected.
- Costs absent from unauthorized responses, caches, recovery, telemetry and
  exports; permission revocation cannot retain a protected projection.

### Documents and presentation

- Original dispatch snapshot versus receipt report, zero-good lines, repeated
  print/export, long descriptions, multiple pages and changes to inventory after
  dispatch. Later returns do not rewrite either document.
- Document generation/output error after successful dispatch; retry generates
  no additional dispatch or stock movement.
- 1366px/1440px desktop, 200% zoom, 360px mobile and configured secondary
  language/RTL; dropdown, keyboard focus, panel resizing and long labels.
- Large requests/catalogues, slow lookups and out-of-order search responses.

### User acceptance

Observe two or three Procurement users completing realistic 10-line and
50-line mixed-source requests. Include a shortage, unavailable line, partial
dispatch, lost connection and replacement. Record baseline and new results:

- completion time and unnecessary clicks/scrolls;
- incorrect source/quantity selections;
- whether users can explain Save progress versus final Save;
- whether they can recover and resume without assistance;
- time to find and print the correct delivery document.

Proposed success target: at least 30% faster median completion on the repeated
50-line task, zero lost-input/duplicate-stock errors, and correct completion
without coaching by every pilot participant. The percentage is a proposed UAT
target, not a measured improvement or a release guarantee.

## 9. Verification completed for this audit

All eight focused files passed: **64 tests**.

```text
test/yorks_v1_arrangement_test.dart
test/yorks_v1_arrangement_layout_test.dart
test/yorks_v1_logistics_test.dart
test/yorks_v1_logistics_screen_test.dart
test/yorks_v1_critical_command_key_store_test.dart
test/yorks_v1_dispatch_centre_golden_test.dart
test/yorks_v1_delivery_order_action_golden_test.dart
test/yorks_v1_logistics_document_service_test.dart
```

The shared-stock witness ran separately and reproduced F1 despite the existing
focused suite passing. That is a coverage gap, not a full-suite failure. No full
Flutter build/analyzer/database reset or release gate was required or performed
for this audit-only change. The prior Inventory release evidence is historical
baseline evidence; it is not a fresh Procurement acceptance run.

This review supports an incremental implementation starting with correctness
and recovery, then the desktop workspace and documents, followed by mobile and
observed UAT. It does not certify the module as bug-free.

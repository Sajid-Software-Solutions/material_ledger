# R39 Accounts Workspace V2 — integration and implementation plan

Status: **approved 5 November 2026; P0 in progress.** Working branch:
`feature/accounts-workspace-v2`. One vertical slice per PR.

Design reference (approved for lead-engineer review, not production code):
[`designs/accounts-workspace-v2-prototype.html`](designs/accounts-workspace-v2-prototype.html).
The printed invoice sample PDF referenced during review is not in the
repository; the printable-invoice spec is taken from the prototype's own
`invoiceDoc` builder and the YRA-322 signed invoices (§12).

Authority: [`../../AGENTS.md`](../../AGENTS.md),
[`R39_ACCOUNTS_FOUNDATION.md`](R39_ACCOUNTS_FOUNDATION.md),
[`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) §23 and §32 and
[`STATE_RPC_RLS_MATRIX.md`](STATE_RPC_RLS_MATRIX.md). This plan changes
**Accounts only**. It does not touch Projects, BOQ, Material Requests,
Procurement, Inventory, Dispatch, Receipt, Delivery Orders, Returns or technical
membership, except through the read-only projections FR-002/FR-003 already
allow.

---

## 1. What we are building, in one paragraph

The prototype is a **specification, not code to embed.** The Yorks website is
the Flutter web build deployed from this repository, so the V2 workspace is
rebuilt as Flutter widgets on top of the existing R39 server (Riverpod →
repository → protected RPC → Postgres). About 90% of what the prototype does
already exists on the server (baselines with revisions, building×stage progress,
claims, invoices, certification, PDCs, payments, supplier bills with three-way
match, documents, audit, exports). V2 adds four server capabilities the
prototype depends on — **item-quantity billing, safe contract editing with
carry-forward, invoice revision (R.n) and a printable tax invoice** — fixes one
P0 correctness defect (the claim cap forgets earlier baseline revisions), and
replaces the seven table-shaped per-project tabs with six job-shaped tabs. It is
gated behind a new default-off flag and the V1 screens remain until V2 is proven.

## 2. Scope boundary

- **In scope:** the **per-project** Accounts workspace — the six tabs that
  replace today's 7-tab `YorksProjectAccountsScreen` embedded in
  `YorksV1ProjectWorkspaceScreen`.
- **Out of scope:** the Accountant **office / portfolio** at `/yorks/accounts/*`
  (`YorksAccountsPortfolioScreen`, `YorksAccountsOfficeScreen`,
  `YorksAccountsControlCentreOverview`, `YorksAccountsReportsScreen`). It is left
  as-is and benefits only from the shared server fix in P1.
- Role/behaviour comes from server capability snapshots and record command
  flags, never from the role label (FR-018). The prototype's "Acting as"
  selector is a demo device only.

## 3. Repository reconciliation (5 November 2026 audit)

Verified against the running code (~40 Dart files in `lib/features/accounts`, 12
R39 SQL migrations, 21 `v1_accounts_*` tables, ~90 RPCs, 18 test files + 28
goldens):

- **Per-project Accounts is not a standalone screen.** It is embedded in
  `YorksV1ProjectWorkspaceScreen`
  (`lib/features/projects/presentation/screens/yorks_v1_projects_screen.dart`,
  which builds `YorksProjectAccountsScreen(projectId, initialTab:)` at ~lines
  5044 and 5961, gated ~3722–3739 by `featureFlags.accounts` +
  `viewProjectAccounts`/`viewSupplierCosts`). The V2 swap happens at that one
  call site behind the new flag — not a Projects redesign.
- Tab enum `YorksProjectAccountsTab {overview, billing, invoices, receiptsPdc,
  supplierBills, documents, activity}` in `yorks_accounts_screens.dart:313`.
- Strings live in `lib/shared/models/yorks_v1_accounts_strings.dart`
  (`YorksV1AccountsStrings.text(language, key)`, en/ar/ur/hi), wrapped by the
  `_t(language, key)` helper.
- Capability keys in `lib/shared/models/yorks_v1_permission_management.dart`
  `class YorksV1CapabilityKeys` (lines 168–181) — 14 of the 15 R39 keys are
  enumerated; `review_commercial_progress` flows via server command flags.
- Flag `accounts` getter at `yorks_v1_feature_flags.dart:152` chains under
  `documents`; the new `YORKS_V1_ACCOUNTS_WORKSPACE_V2` chains under it.
- Money/percent always flow as `YorksAccountsDecimal` text, never floats; all
  reads are server-computed projections rendered by the client.

## 4. Audit — what exists today

| Layer | Exists | Where |
|---|---|---|
| Roles & capabilities | `accountant` role, 15 R39 capability keys (14 client-enumerated), server command flags, 14-key allowlist | T01 `20260825155246_…_t01_foundation.sql`, `YorksV1CapabilityKeys` |
| Contract | Profile + immutable numbered baseline revisions, building % and stage % allocations, VAT/terms/reminder snapshot, review policy | T02 `20260825173645_…`; RPCs `v1_initialize/revise/get_project_commercial_baseline` |
| Progress | One row per (revision, building, stage); suggested vs confirmed %; append-only revisions; evidence = document UUIDs | `v1_accounts_billing_progress(_revisions)`; `v1_suggest/confirm/review_*`, `v1_list_billing_progress` |
| Receivables | Claim root (`draft → ready_for_accounts → invoiced`, `cancelled`), claim line snapshots, invoices (`draft → submitted → under_certification → … → paid`, `returned`, `cancelled`), cumulative certifications, append-only payments, PDCs + events | T03 `20260825194513_…` |
| Supplier bills | Draft/approved/cancelled, server three-way match, append-only payments | T04 `20260826021500_…` |
| Read models | Portfolio, project overview, office register, documents, activity, exports (18 report kinds), due reminders, health | T05–T08, `20260927013207_expand_accounts_project_exports.sql` |
| Flutter | `lib/features/accounts/` — 7 repositories, 7 controllers, embedded `YorksProjectAccountsScreen`, `YorksAccountsReportService` (register PDF/XLSX), `YorksAccountsDecimal` | `lib/features/accounts/**` |
| Tests | pgTAP `yorks_r39_accounts_t01…t08*.test.sql` + YRA-322; Dart `yorks_r39_accounts_t0*_*.dart` + 28 goldens | `supabase/tests/database/`, `test/` |
| Production | `YORKS_V1_ACCOUNTS` enabled on `yorks-r35.vercel.app`; YRA-322 has baseline revision 2, Design 4×100% confirmed, **no claims or invoices** (29 Aug 2026 evidence) | `R39_YRA322_MASTER_FILE_RECONCILIATION.md` |

## 5. Why the current module feels strict, uneditable and confusing

Each cause is a mechanism in the code, not a styling issue.

| # | Cause | Consequence |
|---|---|---|
| R1 | **Editing the contract wipes progress.** `v1_revise_project_commercial_baseline` re-materializes the grid at 0% and never carries confirmed progress forward. | Nobody dares edit the contract. "Uneditable." |
| R2 | **P0: claim cap forgets earlier revisions.** Cap is `eligible − Σ claimed WHERE progress_entry_id = this row`; claims on revision N don't count against revision N+1's new rows. | After a contract edit + re-confirmation, already-invoiced work becomes claimable again. Fix **before** making edits easy. |
| R3 | Evidence is comma-separated document UUIDs; every increase needs an uploaded document per row. | Engineers can't confirm progress without a document-upload detour. |
| R4 | Progress is one building×stage per modal, a single %. | 4 buildings × 5 stages = 20 modals; item quantities still live in Excel. |
| R5 | Seven tabs mirror database tables; every tab shows "Set commercial baseline" until a baseline exists. | Users don't know where to start. |
| R6 | No tax-invoice document; only landscape register exports. Returned invoices can change reference/notes but not amounts. | Yorks keeps issuing invoices from Excel; R.1 revisions impossible in-system. |
| R7 | "Eligible" is recomputed inline in ≥8 functions with two rounding methods. | Reports and claim caps can disagree by cents. |

## 6. Target experience (prototype → product)

| V2 tab | Replaces | Primary users | Job |
|---|---|---|---|
| **Summary** | Overview | Everyone with `view_project_accounts` | Where is the money, what needs attention, what to do next |
| **Contract** | "Set commercial baseline" sheet | Admin / PM / SME with `configure_project_commercials` | Contract, buildings, stages, item breakdown, invoice settings, variations — always editable, every save is a revision |
| **Progress & claims** | Billing Progress + Claims | PE (confirm + prepare claim), SE (suggest only) | Monthly claim workbench by stage → building → item |
| **Invoices & payments** | Claims & Invoices + Receipts & PDC | Accountant | Tracker, certification, payments, cheque register, print, revise |
| **Supplier bills** | Supplier Bills | Procurement (draft), Accountant (approve/pay) | Same server rules, simpler screen |
| **History & files** | Documents + Activity | Everyone permitted | One timeline with filters; files beside it |

The full point-to-point feature inventory per tab (steps strip, KPI set,
money-flow bar, attention logic, heatmap, contract fields, buildings/stages/item
tables, claim workbench grids + Max + site chips + Enter-to-next, claim side
panel pipeline, invoice tracker + PDC register + drawer + certify/pay/revise,
supplier bills, history timeline, printable A4 invoice) is the match target and
is reproduced from the prototype in the plan file and the prototype source.

## 7. Decisions (adopted — recorded in `PRODUCT_DECISIONS.md` §32)

Adopted as the working baseline on 5 November 2026. D2, D6 and D7 change
statements previously frozen in R39 docs and are recorded explicitly.

| ID | Decision | Adopted value |
|---|---|---|
| D1 | Who may edit Contract | `configure_project_commercials` for Admin, Project Manager, Senior Mechanical Engineer; PE/Accountant read-only unless granted |
| D2 | Carry progress forward on contract revision | **Yes**, by stable keys (building scope + stage key [+ item key]). Quantity/percent kept; anything that no longer fits is flagged `needs_review`, never silently dropped. **Supersedes the "never carry forward" stance** (that was migration safety, not a business rule) |
| D3 | Item-quantity billing | Per-stage `measurement_mode`: `percent` (Design, T&C, Energizing) or `items` (Material Supply, Installation) |
| D4 | Rounding | Round each **building×stage claim line** to fils; invoice gross = Σ lines; VAT on gross. (Yorks' Excel rounds only the total; confirm the fil treatment with the owner against YRA32202R.1.) |
| D5 | Evidence for confirmed increases | Accept a controlled document **or** a confirmed Receipt Review / Delivery Order of the same project; decreases need a reason only |
| D6 | VAT default | Published setting `accounts.default_vat_percent = 5` pre-fills the contract form; the user still confirms it explicitly. **The snapshot stays explicit** (R39 forbids an implicit default) |
| D7 | Invoice revision | `R.n` supersede allowed **only before** certification, payment or an active PDC. After that → credit note (out of V2 scope) |
| D8 | Invoice numbering | Per-project prefix + 2-digit sequence (`YRA322` + `03`), editable before issue, unique per project |
| D9 | Letterhead & bank details | New Admin-only company settings `company.trn/address/phone/fax/email/bank_name/bank_iban/bank_account_name`, snapshotted on each issued invoice |
| D10 | Claim ↔ invoice | Keep one-to-one (already enforced by `unique(claim_id)`) |
| D11 | Who issues invoices | Accountant (`manage_client_invoices`); PM "checks" a claim (= existing `v1_submit_client_claim_to_accounts`) |
| D12 | YRA-322 history | Enter YRA32201 and YRA32202R.1 through a controlled source-import migration using the real certification/payment facts Yorks supplies |
| D13 | Nexus payment terms | 45 days on YRA-322's contract; org default stays 90 |
| D14 | Variations | Register only in V2 (approved VOs raise contract value on Summary); VO billing later |

## 8. Server design

All new SQL follows the existing T02/T03 command pattern: `security definer`,
`set search_path = ''`, exact actor/role from Auth, capability check, expected
version, idempotency key + request hash, deterministic row locks, append-only
audit in the same transaction, decimal strings in JSON.

### 8.1 One source of "eligible" and "already claimed" (fixes R2, R7)

```sql
-- Eligible for a progress row, both modes, rounded to fils once.
create or replace function public.v1_accounts_progress_eligible_amount(
  p_progress_entry_id uuid) returns numeric(20,2) ...
--   percent mode: round(v1_accounts_stage_value(id) * confirmed_percent / 100, 2)
--   items mode  : round(Σ item_value_i * confirmed_qty_i / quantity_i, 2)

-- Claimed so far for a stable dimension, across ALL baseline revisions.
create or replace function public.v1_accounts_dimension_claimed_amount(
  p_project_id uuid, p_project_scope_id uuid, p_stage_key text,
  p_excluded_claim_id uuid default null) returns numeric(20,2) ...
--   Σ claim_lines.claimed_amount where claim.status not in ('cancelled','superseded')
```

Re-create, with `create or replace`, every function that computes eligible or
consumed inline so it calls these two: `v1_accounts_validate_claim_lines`,
`v1_accounts_consumed_claim_amount`, `v1_list_billing_progress`,
`v1_get_project_accounts_overview`, `v1_get_accounts_portfolio`,
`v1_get_accounts_export` (latest in `20260927013207_…`),
`v1_get_accounts_office_register`, and the T06 report CTEs. Behaviour for
percent-mode rows is unchanged except the T06 cent drift, which is the point.
`Available = max(eligible(current row) − claimed(dimension), 0)`; if
`claimed > eligible` the projection returns an `over_claimed` blocker and no new
claim is possible on that dimension (credit note out of scope).

### 8.2 Item breakdown (D3)

```sql
alter table public.v1_accounts_baseline_stage_allocations
  add column if not exists measurement_mode text not null default 'percent'
  check (measurement_mode in ('percent','items'));

create table if not exists public.v1_accounts_baseline_stage_items (
  id uuid primary key default gen_random_uuid(),
  baseline_revision_id uuid not null references public.v1_accounts_baseline_revisions(id) on delete restrict,
  project_id uuid not null references public.v1_projects(id) on delete restrict,
  project_scope_id uuid not null references public.v1_project_scopes(id) on delete restrict,
  stage_key text not null check (stage_key ~ '^[a-z][a-z0-9_]*$'),
  item_key text not null check (item_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'), -- stable across revisions
  item_label text not null check (btrim(item_label) <> ''),
  display_order integer not null check (display_order > 0),
  quantity numeric(18,4) not null check (quantity::text <> 'NaN' and quantity > 0),
  unit_code text not null check (btrim(unit_code) <> ''),
  weight_percent_of_contract numeric(9,6) not null
    check (weight_percent_of_contract > 0 and weight_percent_of_contract <= 100),
  created_at timestamptz not null default clock_timestamp(),
  unique (baseline_revision_id, project_scope_id, stage_key, item_key),
  unique (baseline_revision_id, project_scope_id, stage_key, display_order)
);
```

- Weight is **% of total contract**, exactly as the Excel sheets. Server rule per
  (revision, building, items-stage): `Σ weight = building% × stage% / 100`
  within `0.000005`.
- Item value is server-derived by largest-remainder distribution of the
  building×stage value across its items by weight, so Σ item values equals the
  stage value to the fil.
- Items are defined per building; "same items in all buildings" is a UI
  convenience that sends identical rows per building.

```sql
create table if not exists public.v1_accounts_billing_item_progress (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null, baseline_revision_id uuid not null,
  progress_entry_id uuid not null references public.v1_accounts_billing_progress(id) on delete restrict,
  stage_item_id uuid not null references public.v1_accounts_baseline_stage_items(id) on delete restrict,
  project_scope_id uuid not null, stage_key text not null, item_key text not null,
  suggested_qty numeric(18,4) not null default 0,
  confirmed_qty numeric(18,4) not null default 0,   -- 0 ≤ confirmed_qty ≤ item quantity
  confirmed_evidence jsonb not null default '[]',   -- see 8.4
  needs_review boolean not null default false,      -- set by carry-forward
  record_version integer not null default 1,
  unique (baseline_revision_id, stage_item_id)
);
create table if not exists public.v1_accounts_billing_item_progress_revisions (...append-only...);
```

For items-mode rows, `v1_accounts_billing_progress.confirmed_percent` is kept as
a derived display value `round(eligible / stage_value × 100, 4)` so every
existing reader keeps working; eligible always comes from 8.1.

### 8.3 Contract editing that never loses work (fixes R1, D2)

`v1_save_project_commercial_setup(p_project_id, p_expected_profile_version,
p_setup jsonb, p_note text, p_idempotency_key uuid)`

- `p_setup` = contract value, currency, VAT, terms, reminder, review policy,
  buildings, stages (+mode), items, invoice settings (8.6).
- No baseline → initialize (revision 1). Otherwise, if commercial dimensions are
  unchanged → only invoice settings are saved (no revision). If changed → new
  revision; the **reason is server-generated** from the diff, plus the optional
  note.
- Carry-forward inside the same transaction: for every new row whose
  (scope, stage_key) or (scope, stage_key, item_key) existed in the previous
  revision, copy suggested/confirmed facts, append a progress revision
  `source = 'carried_forward'` linked to the source revision, keep its evidence.
  If a new quantity is below the confirmed quantity, cap and set `needs_review`;
  removed dimensions are reported in the response.
- Existing `v1_accounts_mark_claim_drafts_stale` stays; the UI offers **Rebuild
  draft** (8.5) instead of a dead end.
- `v1_initialize_project_commercial_baseline` and
  `v1_revise_project_commercial_baseline` remain for the V1 screens until retired.

### 8.4 Evidence (D5)

`confirmed_evidence` / claim-line evidence becomes a typed array:

```json
[{"kind":"document","id":"<v1_documents.id>"},
 {"kind":"receipt_review","id":"<v1_receipt_reviews.id>"},
 {"kind":"delivery_order_revision","id":"<v1_delivery_order_revisions.id>"},
 {"kind":"note","text":"Site visit 3 Nov, photos in WhatsApp group"}]
```

Validation reuses `v1_accounts_validate_evidence_documents` for documents and
adds a same-project check for receipt reviews / DO revisions. An increase needs
at least one non-`note` entry (D5). The legacy `uuid[]` columns stay populated
with the document subset for older readers.

### 8.5 Claim workbench in one command

`v1_get_claim_workbench(p_project_id, p_claim_id default null)` — one round trip:
every building × stage (× item) with item value, quantity, previously claimed
(dimension-wide), confirmed-to-date, this draft's quantity, evidence,
site-record suggestions (8.8), blockers and command flags. Stage/building
switching in the UI is client-side.

`v1_save_claim_workbench(p_project_id, p_claim_id, p_expected_claim_version,
p_period_start, p_period_end, p_entries jsonb, p_evidence jsonb,
p_idempotency_key)`

- `p_entries`: `{progress_entry_id, confirmed_percent_to_date}` or
  `{stage_item_id, confirmed_qty_to_date}` (UI sends to-date = before + this
  month; the server never trusts its arithmetic).
- Atomically: confirm changed rows (or record **suggestions** only if the actor
  lacks `confirm_billing_progress`), then create/replace the single open draft
  claim with lines `claimed = available(dimension)` for every row with something
  to claim. Requires `prepare_client_claim` + `view_project_commercial_values`.
- At most one open draft per project (server-enforced).
- `v1_rebuild_client_claim_draft` re-runs line derivation on the current
  baseline for a stale draft.
- `v1_reopen_client_claim` returns `ready_for_accounts → draft` while no invoice
  exists ("Back to draft").

### 8.6 Invoice numbering, issue, document and revision

```sql
create table if not exists public.v1_accounts_project_invoice_settings (
  project_id uuid primary key references public.v1_projects(id) on delete restrict,
  invoice_prefix text not null,          -- 'YRA322'
  next_sequence integer not null default 1 check (next_sequence > 0),
  scope_line text,                       -- first line of the invoice table
  bill_to_party_id uuid references public.v1_project_parties(id),
  attention_name text,
  record_version integer not null default 1, ...);

alter table public.v1_accounts_client_invoices
  add column if not exists invoice_date date,
  add column if not exists supersedes_invoice_id uuid references public.v1_accounts_client_invoices(id),
  add column if not exists base_reference text,
  add column if not exists revision_number integer not null default 0;
-- status check gains 'superseded'; v1_accounts_client_claims.status gains 'superseded'.

create table if not exists public.v1_accounts_client_invoice_documents (
  invoice_id uuid primary key references public.v1_accounts_client_invoices(id) on delete restrict,
  document_snapshot jsonb not null,      -- frozen print model, see 9
  snapshot_sha256 text not null,
  controlled_document_id uuid references public.v1_documents(id),  -- issued PDF
  created_at timestamptz not null default clock_timestamp());
```

- `v1_issue_client_invoice(p_project_id, p_claim_id, p_expected_claim_version,
  p_invoice_reference default null, p_invoice_date, p_submission_date,
  p_attention_name, p_idempotency_key)` — one transaction: allocate the number
  (`prefix || lpad(seq,2,'0')`, or supplied override if unique), create + submit
  the invoice (existing internal logic + VAT/terms snapshots), freeze
  `document_snapshot` incl. letterhead + bank settings (D9), increment the
  sequence, audit, notify. Requires `manage_client_invoices`; claim must be
  `ready_for_accounts`.
- `v1_get_client_invoice_document(p_project_id, p_invoice_id)` returns the frozen
  snapshot; `v1_preview_client_invoice_document(p_project_id, p_claim_id)`
  returns the same shape computed live for drafts.
- `v1_revise_client_invoice(p_project_id, p_invoice_id, p_expected_version,
  p_reason, p_idempotency_key)` — only with no certification, net payment or
  `expected/received/deposited` PDC. Creates a successor draft claim cloned from
  the predecessor; the predecessor invoice stays `submitted` until the successor
  is issued. Cap checks for the successor pass the predecessor as
  `p_excluded_claim_id`. Issuing the successor marks predecessor claim + invoice
  `superseded` and sets reference `base_reference || 'R.' || n`. Deleting the
  successor draft abandons the revision with no effect on the original.
- Every status reader must treat `superseded` as terminal and non-contributing:
  due state, PDC exposure, portfolio, office register, exports, reminders,
  `v1_accounts_notify_from_audit`.

### 8.7 Workspace projection (one call for Summary)

`v1_get_project_accounts_workspace(p_project_id)` returns: `steps` (4-step
strip), `money_flow` ex-VAT (paid / invoiced-waiting / done-not-invoiced /
remaining), `kpis` (contract +VAT +approved VOs, invoiced, received cleared,
outstanding, cheques in hand, supplier unpaid/overdue), `attention[]`
(server-derived `{severity, kind, title_key, params, action_key, target_type,
target_id}`), `heatmap[building][stage]` (invoiced % per cell), `cash`
(received vs paid-to-suppliers, only with `view_supplier_costs`). Monetary keys
are **omitted, not zeroed**, without `view_project_commercial_values`
(AT-SEC-001/008); supplier keys need `view_supplier_costs`.

### 8.8 Site-record suggestions (advisory, P8)

`v1_accounts_item_material_links(project_id, project_scope_id null, item_key,
material_key)` maps a commercial item to the normalized description+unit key from
`v1_project_material_summary`. `v1_get_accounts_item_site_evidence(p_project_id)`
returns delivered good quantity per mapped item with its receipt-review / DO
references. It only **suggests**; confirming still goes through 8.5 with that
record as evidence. Package units shipped direct supplier→site have no record —
expected.

### 8.9 Company settings (D9)

Add the setting keys to the configuration allowlist with the existing
`v1_stage_configuration_setting` / `v1_publish_configuration` flow
(`20260814090919_yorks_r38_configuration_centre.sql`); no new admin screen beyond
the existing Configuration Centre fields.

## 9. Printable tax invoice

- **Data**: `v1_get_client_invoice_document` (frozen) or `…_preview_…` (draft).
  The Flutter builder renders exactly that JSON; it never recomputes money.
- **Builder**: new `YorksClientInvoiceDocumentBuilder` in
  `lib/features/accounts/data/v2/client_invoice_document_builder.dart` using the
  existing `pdf`/`printing` packages and the bundled NotoSans/NotoSansArabic
  fonts + Yorks emblem. A4 portrait, three pages as in the prototype's
  `invoiceDoc`: (1) tax invoice, (2) main summary all buildings + by building,
  (3) breakdown per building. Item sheets (Material / Installation per building)
  are optional page 4+ for items-mode stages.
- **Issue-time snapshot**: after `v1_issue_client_invoice` succeeds, the client
  renders the PDF and uploads it through the existing
  `v1_prepare_accounts_document_upload` → `finalize-document-upload` path with
  `document_type = 'client_invoice'`; the server links it in
  `v1_accounts_client_invoice_documents.controlled_document_id`. If upload fails,
  the invoice is still valid (the snapshot is authoritative) and the drawer shows
  "Generate PDF copy" to retry. "Attach signed copy" uploads `client_invoice`
  with the same link target.
- Amount in words, VAT line, due date and `R.n` reference come from the snapshot.
  Bank lines print only from published company settings.

## 10. Flutter integration

### 10.1 Placement and flag
- Accounts stays inside the project workspace at
  `/yorks/projects/:projectId/accounts/*`. New dart-define
  **`YORKS_V1_ACCOUNTS_WORKSPACE_V2`** (default **off**), chained under the
  `accounts` getter in `yorks_v1_feature_flags.dart`. When on, the one embed
  point in `YorksV1ProjectWorkspaceScreen` builds
  `YorksAccountsWorkspaceV2Screen` instead of `YorksProjectAccountsScreen`. V1
  screens stay until V2 has run two weeks in production, then a cleanup PR
  removes them.

### 10.2 Routes (deep links keep working)
| V2 tab | Path | Old paths redirected |
|---|---|---|
| Summary | `…/accounts/overview` (existing) | `…/accounts` |
| Contract | `…/accounts/contract` (new) | — |
| Progress & claims | `…/accounts/claims` (new) | `…/accounts/billing` |
| Invoices & payments | `…/accounts/client-invoices` (existing) | `…/accounts/receipts-pdc` → `?section=cheques` |
| Supplier bills | `…/accounts/supplier-bills` (existing) | — |
| History & files | `…/accounts/history` (new) | `…/accounts/documents` → `?filter=files`, `…/accounts/activity` |

Redirects matter because notification payloads already target the old paths.
Route guards keep using `_isYorksV1AccountsPath` + capability checks in
`router.dart`; add the new paths to that predicate. Only the accounts block of
`router.dart` changes.

### 10.3 Code layout (follows the existing accounts feature convention)

```
lib/features/accounts/
  domain/v2/
    accounts_workspace_models.dart      # Summary projection
    commercial_setup_models.dart        # Contract form model + client-side mirror validation
    claim_workbench_models.dart         # rows, items, evidence, suggestions
    client_invoice_document_models.dart # frozen print model
  data/v2/
    accounts_workspace_repository.dart  # all new RPCs, YorksAccountsRpcClient
    client_invoice_document_builder.dart
  application/v2/
    accounts_workspace_controller.dart  # Summary (keeps previous data while refreshing)
    commercial_setup_controller.dart    # dirty tracking, save → one RPC
    claim_workbench_controller.dart     # local edit buffer, save/rebuild/check
    invoice_actions_controller.dart     # issue, certify, pay, PDC, revise
  presentation/v2/
    yorks_accounts_workspace_v2_screen.dart
    tabs/{summary,contract,claims,invoices,supplier_bills,history}_tab.dart
    widgets/  kpi_tile, money_flow_bar, attention_list, steps_strip,
              stage_tiles, building_tiles, item_claim_grid, lump_claim_grid,
              claim_totals_panel, invoice_tracker_table, cheque_register,
              invoice_drawer, setup_check_panel, history_timeline
```

Rules from `AGENTS.md`: widgets never call Supabase; **no optimistic success**
for issue/certify/pay/PDC/save-claim/save-setup; every label through the accounts
`_t(language, key)` map in English and the secondary language; existing
`AppColors`, `AppSpacing`, `AppTypography`, `StatusChip` and the existing toast
in `lib/core/widgets/yorks_app_toast.dart`.

### 10.4 Prototype tokens → app tokens
| Prototype | App |
|---|---|
| `--pri #2E6BE6`, `--pri-50` | `AppColors.blue`, `AppColors.blueContainer` |
| `--ink`, `--mut`, `--line` | `AppColors.ink`, `AppColors.muted`, `AppColors.line` |
| `--ok`, `--warn`, `--bad` (+`-50`) | `AppColors.success/warning/error` (+`…Container`) |
| `--vio` (cheques) | `AppColors.tertiary`, `tertiaryContainer` |
| Card radius 14, padding 16–20 | `AppSpacing.radiusLg`, `AppSpacing.lg/xl` |
| Buttons 36px / sm 30px | `AppSpacing.controlHeight`; keep ≥44px tap targets on mobile |
| Desktop split 1fr + 340px | `AppSpacing.inspectorWidth` |

### 10.5 Claim workbench behaviour (the screen that must feel fast)
- Opens with one `v1_get_claim_workbench` call; switching stage/building is local
  state only.
- Each row has its own `TextEditingController`; computed cells listen to a per-row
  `ValueNotifier` so typing rebuilds one row, not the grid. Use a virtualized list
  with fixed row height, **not `DataTable`**.
- Preview arithmetic uses `YorksAccountsDecimal` (exact), labelled as preview;
  saved values come back from the server.
- Unsaved buffer persists in the existing local-draft storage so a refresh
  doesn't lose work. **Save draft** sends the whole buffer in one command; a
  version conflict reloads and shows "your changes vs current" before re-applying.
- Desktop: Tab/Shift+Tab, arrows, Enter = next row, "Max" fills remaining. Mobile
  (<720px): one card per item with a focused one-row editor.

### 10.6 Refresh
Accounts audit events already drive notifications; subscribe the V2 controllers
to the same Realtime signal and re-fetch the affected projection (Realtime is a
refresh signal, not authority). Keep the last confirmed data on screen while
re-fetching.

## 11. Phased delivery (one vertical slice per PR)

Effort is engineer-days for one experienced developer using coding agents.

| PR | Scope | Key files | Gate | Days |
|---|---|---|---|---|
| **P0** Decisions & contracts | Record D1–D14 in `PRODUCT_DECISIONS.md` §32; add V2 rows to `STATE_RPC_RLS_MATRIX.md`; copy the prototype to `designs/`; add this plan; link from `README.md` | docs only | `git diff --check`, links | 1–2 |
| **P1** Claim cap & eligible (P0 fix) | 8.1 helpers; re-create dependent functions; pre-flight query; no UI | `supabase/migrations/2026110x_accounts_v2_p1_dimension_claim_cap.sql`, `…/tests/database/yorks_r39_accounts_v2_p1.test.sql` | pgTAP: cross-revision double-claim **denied**; percent-mode byte-identical before/after; T06 report = claim cap to the fil; full `supabase test db` | 3–4 |
| **P2** Items + carry-forward + setup command | 8.2, 8.3, 8.4; extend YRA-322 source import to read item sheets | `…_p2_items_carry_forward.sql`, tests | Σ item values = stage value; YRA-322 DF3W material reproduces 1,549,624.36; carry-forward keeps Design 100% across a revision; cap/needs_review; role negatives | 6–8 |
| **P3** Claim/invoice commands | 8.5, 8.6; `superseded` in all readers | `…_p3_claim_invoice_v2.sql`, tests | idempotent replay / conflict on every command; revise denied after cert/payment/PDC; R.n numbering; superseded excluded everywhere; snapshot hash stable | 6–8 |
| **P4** Workspace & site evidence projections | 8.7 (+ 8.8 read side), company settings keys (8.9) | `…_p4_projections.sql`, tests | response-shape tests per role (no money keys without capability); p95 < 150 ms on YRA-322-sized data | 3–4 |
| **P5** Flutter data layer | domain/v2, repository, controllers, parsing tests | `lib/features/accounts/{domain,data,application}/v2`, `test/yorks_r39_accounts_v2_*` | decimal-string parsing; out-of-order response guard; conflict handling | 3–4 |
| **P6** V2 screens behind flag | 6 tabs, routes/redirects, strings EN + secondary | `presentation/v2/*`, `router.dart` (accounts section only), the one embed in `yorks_v1_projects_screen.dart` | goldens at the six T07 viewports for every tab; router redirect tests; `flutter analyze`; web + APK build | 10–14 |
| **P7** Tax invoice PDF | builder, issue-time upload, print, signed copy | `data/v2/client_invoice_document_builder.dart`, tests | pixel/golden of the 3 pages for YRA32202R.1; Arabic glyph test (`yorks_v1_pdf_arabic_test.dart` pattern) | 3–4 |
| **P8** Site-record suggestions | mapping UI in Contract → items; suggestion chips in workbench | migration + UI | suggestion never changes confirmed values without Save; project isolation | 4–5 |
| **P9** YRA-322 history | source-import migration for claims #01/#02, YRA32201, YRA32202 (superseded) → R.1, cert/payment facts supplied by Yorks (D12) | `…_reconcile_yra322_invoices_01_02.sql` | totals match the signed PDFs; replay is a no-op; refuses if any live Accounts transaction exists | 2 |
| **P10** UAT & release | staging personas (Accountant, PE, SE, Procurement, Admin) on one commit; enable flag on staging → production | evidence doc | five personas pass, no P0/P1 open, release owner sign-off | 3–5 |

Total ≈ **45–60 engineer-days.** P5–P6 can start against fixture JSON as soon as
P0 freezes the RPC shapes, so backend (P1–P4) and Flutter (P5–P7) can run in
parallel; P6 only switches from fixtures to live RPCs after P4 lands.

## 12. Reference numbers (acceptance fixtures)

From `INVOICE#02R.1.xlsx` / `INVOICE#02-R.1-signed.pdf`, contract AED
17,192,000.00, 4 × 25%, stages 10/50/30/5/5:

| Fixture | Expected |
|---|---|
| Stage value DF3W Material Supply | 2,149,000.00 |
| Item value AC Units (4.5%) | 773,640.00 |
| 20 of 55 dampers (1%) | 62,516.36 (unrounded 62,516.3636) |
| Claim #02 lines | DF3W 1,549,624.36 · DF4W 1,549,624.36 · DF6W 1,463,664.36 · DF7W 1,420,684.36 |
| Invoice gross (D4 line rounding) | 5,983,597.44 (Excel prints .45) |
| VAT 5% / net | 299,179.87 / 6,282,777.31 (Excel .33) — confirm D4 with Yorks |
| YRA32201 | 1,719,200.00 + 85,960.00 = 1,805,160.00 |
| Cumulative after #02 | 7,702,797.44 ex VAT, 44.80% |

## 13. Testing gate per PR (from `AGENTS.md`)

```bash
flutter pub get
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze
flutter test test/yorks_r39_accounts_*   # focused, then full suite
supabase db reset && supabase test db
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key ./tool/r35.sh build-web
CI=true YORKS_CI_EPHEMERAL_SIGNING=true R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key ./tool/r35.sh build-apk
```

Mandatory database proofs for V2: positive + negative per role (PE, SE,
Procurement, Accountant, Admin) for every new command; same-key/same-hash replay
and same-key/different-hash conflict; competing writers on
`v1_save_claim_workbench` and `v1_issue_client_invoice` (two sessions, one wins,
no double number, no double claim); response-shape absence of money keys. UI
changes need desktop and 360px evidence. Known unrelated golden drift (see
`R39_YRA322_MASTER_FILE_RECONCILIATION.md`) is reported, not rewritten.

## 14. Data safety and rollback

- Every migration is additive and idempotent. New status values are added by
  replacing check constraints with a superset; no row changes state.
- **Pre-flight for P1** (run read-only on production before merging):
  ```sql
  select c.project_id, l.project_scope_id, l.stage_key,
         count(distinct c.baseline_revision_id) revisions, sum(l.claimed_amount)
  from v1_accounts_client_claim_lines l
  join v1_accounts_client_claims c on c.id = l.claim_id
  where c.status <> 'cancelled'
  group by 1,2,3 having count(distinct c.baseline_revision_id) > 1;
  ```
  Any row means a cross-revision claim already exists → stop and reconcile by
  hand before P1 enforces the dimension cap.
- Rollback: turn off `YORKS_V1_ACCOUNTS_WORKSPACE_V2` (V1 screens return); server
  additions stay (unused by V1). Never delete item, carry-forward,
  invoice-document or superseded records; correct forward with an audited reason.
- Forward-disable snippets follow
  `supabase/snippets/R39_ACCOUNTS_T05_T07_FORWARD_DISABLE.md`.

## 15. Risks

| Risk | Mitigation |
|---|---|
| D4 rounding differs from Excel by fils | Decide before P2; show "Rounded per building line" note on invoice page 2 |
| Carry-forward changes a frozen R39 statement | D2 approval + pgTAP proof that history on the old revision is untouched |
| `superseded` missed in one reader → wrong totals | P3 checklist of every status-reading function (8.6) + a pgTAP that sums portfolio = project = export |
| Router conflicts with parallel work | Touch only the accounts block of `router.dart`; rebase daily |
| Large workbench on mobile | Focused one-row editor; virtualized list; no `DataTable` |
| Production already has cross-revision claims | P1 pre-flight query; stop condition |

## Appendix A — Prototype element → implementation

| Prototype element | Server source | Flutter widget |
|---|---|---|
| 4-step strip | `workspace.steps` | `StepsStrip` |
| "Where the contract money stands" bar | `workspace.money_flow` | `MoneyFlowBar` |
| KPI cards | `workspace.kpis` | `KpiTile` |
| Needs attention | `workspace.attention[]` → action routes | `AttentionList` |
| Cash position | `workspace.cash` (supplier-cost gated) | `CashPositionCard` |
| Building × stage heatmap | `workspace.heatmap` | `InvoicedHeatmap` (tap → claims tab) |
| Contract form + setup check | `v1_get_project_commercial_baseline` + settings; save `v1_save_project_commercial_setup` | `ContractTab`, `SetupCheckPanel` |
| Yorks standard 10/50/30/5/5 | protected stage template (T01) | button pre-fills stages |
| Item breakdown tables | `v1_accounts_baseline_stage_items` | `ItemBreakdownTable` |
| Import Master File | extended source import (P2) | dialog → upload → preview → confirm (scoped in [`ACCOUNTS_V2_IMPORT_MASTER_FILE_SCOPE.md`](ACCOUNTS_V2_IMPORT_MASTER_FILE_SCOPE.md)) |
| Claim cards | `v1_list_client_claims` | `ClaimCardsRow` |
| Stage / building tiles | `v1_get_claim_workbench` | `StageTiles`, `BuildingTiles` |
| Item grid, "Max", purple site chips | workbench rows + `site_evidence` | `ItemClaimGrid`, `LumpClaimGrid` |
| Claim totals panel, pipeline | workbench totals + claim status | `ClaimTotalsPanel` |
| Mark checked / Back to draft | `v1_submit_client_claim_to_accounts` / `v1_reopen_client_claim` | panel buttons |
| Preview / Issue invoice | `v1_preview_client_invoice_document` / `v1_issue_client_invoice` | `IssueInvoiceDialog` |
| Invoice tracker | `v1_list_client_invoices` | `InvoiceTrackerTable` |
| Invoice drawer (timeline, actions) | `v1_get_client_invoice` | `InvoiceDrawer` |
| Record certification | `v1_record_client_certification` | dialog |
| Record payment / cheque | `v1_record_client_payment` / `v1_create_client_pdc` | dialog with type switch |
| Cheque register actions | `v1_transition_client_pdc` (clear = linked payment) | `ChequeRegister` |
| Revise (R.n) | `v1_revise_client_invoice` | confirm dialog |
| Print / Save PDF | `v1_get_client_invoice_document` | `YorksClientInvoiceDocumentBuilder` + `Printing.layoutPdf` |
| Supplier bills | T04 RPCs, `v1_accounts_supplier_match_status` | `SupplierBillsTab` (3 evidence ticks) |
| History & files | `v1_get_accounts_activity` + `v1_get_accounts_documents` | `HistoryTimeline`, `FilesPanel` |
| Export CSV | `v1_get_accounts_export` (XLSX via `YorksAccountsReportService`) | existing export action |

## Appendix B — Capability per V2 action

| Action | Capability (server) | Default holders |
|---|---|---|
| Open Accounts tab | `view_project_accounts` | Accountant (scoped), PE, SE, Admin |
| See money | `view_project_commercial_values` | Accountant, Admin; PE only if granted |
| Edit Contract | `configure_project_commercials` | Admin (+ PM/SME per D1) |
| Suggest progress | `suggest_billing_progress` | SE |
| Confirm progress | `confirm_billing_progress` | PE |
| Save claim draft / Mark checked | `prepare_client_claim` + values | PE / PM |
| Issue / revise invoice | `manage_client_invoices` | Accountant |
| Certification | `record_client_certification` | Accountant |
| Payments | `record_client_payment` | Accountant |
| Cheques | `manage_pdc` | Accountant |
| Supplier bill draft | `manage_supplier_bills` | Procurement |
| Approve / pay supplier | `approve_supplier_bill_payment` | Accountant, Admin |
| See supplier costs / cash position | `view_supplier_costs` | Accountant, Admin |
| Export | `export_accounts_registers` | Accountant, Admin |

## Appendix C — Hand-off template for each PR

Paste into the implementing agent with the PR number filled in:

> Implement **P{n}** of `docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md`
> on `feature/accounts-workspace-v2`. Read `AGENTS.md`, `docs/yorks-v1/README.md`,
> `SOURCE_OF_TRUTH.md`, `PRODUCT_DECISIONS.md` (§23, §32), `R39_ACCOUNTS_FOUNDATION.md`
> and this plan first. Touch only the files listed for P{n}. Before editing, list
> the exact models, repositories, RPC/RLS, routes, UI and tests affected. Use the
> reference numbers in §12 as fixtures. Run the §13 gate. Report files changed,
> commands, test counts, evidence and limitations. Stop and report instead of
> guessing on any §7 decision that is not yet recorded as approved.

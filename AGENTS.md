# AGENTS.md — Yorks V1 R35

## Mission

Implement the approved Yorks V1 Procurement Control and Inventory system in
this existing Flutter repository, incrementally and without breaking
authentication, sync, Rentals, People/HR, Leave, Inventory history or existing
production hardening.

Yorks V1 is a controlled re-baseline of the overlapping Nexus V7 Materials and
Projects work. Do not continue an older V7 workflow merely because code or
documentation for it already exists.

## Authority order

When sources disagree, use this order:

1. `Yorks_V1_SRS_and_Rapid_Development_Plan_Rev2_0.docx` — behavior, scope,
   roles, invariants and acceptance, except where the later approved Accounts
   R39 package expressly supersedes an Accounts-only deferred statement.
2. The effective final R35 behavior in
   `Yorks_AC_Ref_V1_Procurement_Control_R35_Final.html` — visual and interaction
   target only where it does not conflict with the SRS or security rules.
3. `Yorks_V1_SOL_AI_Execution_Pack.md` — task sequence and completion
   discipline, as corrected by `docs/yorks-v1/IMPLEMENTATION_PLAN.md`.
4. `docs/yorks-v1/PRODUCT_DECISIONS.md` — approved resolutions of ambiguity.
5. The current Flutter application — reuse boundary, not product authority.
6. `docs/nexus-v7/` — historical implementation evidence. Only its explicitly
   preserved security, migration, localization, architecture and unrelated
   module safeguards continue to apply.

The repository-local, self-contained contract is under `docs/yorks-v1/`.
Before every Yorks V1 task, read:

- `docs/yorks-v1/README.md`
- `docs/yorks-v1/SOURCE_OF_TRUTH.md`
- `docs/yorks-v1/PRODUCT_DECISIONS.md`

Then read the task-relevant architecture, UI, migration, test and implementation
documents linked from that README.

For Accounts work, also read
`docs/yorks-v1/R39_ACCOUNTS_FOUNDATION.md`. The approved 25 August 2026 R39
package governs Accounts-only behavior; it does not reopen any unrelated V1
decision.

## Required architecture

- Flutter and Dart
- Riverpod for state and controllers
- GoRouter for navigation and client-side route guards
- Supabase Auth, Postgres, RLS, Storage and Realtime as the production backend
- existing local draft, CollectionStore, outbox and refresh patterns where safe
- trusted Postgres RPCs for critical workflow and stock commands

Widgets never call Supabase directly. The path is:

`Widget -> Riverpod controller -> repository -> Supabase RPC/query or local draft service`

Realtime is a refresh signal, not a transaction authority. Generic JSON
snapshot upserts are not permitted for critical V1 transitions.

## V1 product scope

Implement:

1. Authentication, profiles, ten exact roles and project membership guards
2. Projects, buildings/Common scope and historical team membership
3. Twenty-nine default BOQ groups plus custom groups
4. Dynamic BOQ columns/rows and real Excel import/export
5. Material Request drafts and explicit submission
6. Procurement Full/Partial/Cannot Provide Now arrangement
7. Warehouse reservations and Project Engineer approval
8. Single-warehouse inventory and append-only movements
9. Controlled dispatch and Received/Missing/Damaged receipt review
10. Immutable Delivery Order snapshots
11. Material Returns and Procurement confirmation
12. Documents, links, versions, activity, notifications and audit
13. Retained Configuration, Rentals, User Management, Audit Trail, Duct Sizer
    and ESP Calculator
14. The phased R39 project commercial-control Accounts module: baselines,
    billing progress, claims, certification, receipts/PDCs and matched supplier
    bills, behind `YORKS_V1_ACCOUNTS` until its release gate passes

Explicitly deferred:

- general ledger, journal entry, payroll, tax, bank-reconciliation,
  depreciation, inventory-valuation and company-wide P&L workflows
- full RFQ, quotation comparison and Purchase Order supplier-management suite
- multi-warehouse workflows
- supplier/client portals
- barcode/QR, AI recommendations and complex BI

Preserve deferred or legacy data. Hide unsupported routes behind V1 rollout
boundaries; do not destructively remove historical records.

## Roles and separation of duties

- **Project Engineer** — creates/edits assigned projects and BOQ, manages the
  project team, creates/submits MRs, approves or returns arrangements, confirms
  receipts and creates returns. Cannot arrange or dispatch.
- **Site Engineer** — creates projects, edits assigned BOQ, creates/submits MRs,
  confirms receipts and creates returns. Cannot manage team access or approve
  unless also assigned as Project Engineer.
- **Procurement** — reads running project/BOQ/request/document context, arranges
  MR lines, maintains inventory, dispatches approved quantities and confirms
  returns. Cannot create/edit projects or BOQ, raise Engineering MRs, or approve
  its own arrangement.
- **Admin** — controlled administration and audited overrides. Admin is not a
  substitute for missing workflow history.
- **Accountant** — exact platform role for authorized project Accounts,
  certification, PDC/payment and supplier-bill payment controls. Accountant is
  never a technical project member and inherits no Project, BOQ, MR, Dispatch,
  Receipt, Inventory, Return or team-management mutation authority.
- **PR** — people and HR (owner decision, 12 November 2026,
  `PRODUCT_DECISIONS.md` section 37). Full User Management (as Senior
  Mechanical Engineer), Worker Records, Workforce, People/leave and Rentals;
  read-only Projects and Accounts. PR is never a technical project member and
  holds no project, BOQ, MR, stock, return or Accounts mutation authority.
- **Senior Mechanical Engineer**, **Project Manager**, **Workshop In-Charge**
  and **Document Controller** — organization-wide
  Project Engineer roles. They can access every project and perform Project
  Engineer approvals without a per-project membership row. Senior Mechanical
  Engineer additionally has audited User Management authority, but does not
  gain direct commercial visibility or unrelated Admin modules. Senior
  Mechanical Engineer also has read-only Browse/Inventory access, without any
  stock, category or import mutation authority. Project Manager, Workshop
  In-Charge and Document Controller do not inherit user administration. None
  of these global engineering roles inherits Procurement or stock authority.

Authorization claims come only from exact, server-controlled
`app_metadata.role` values. Never infer privilege from email, editable user
metadata or an unprotected profile. Project access derives from dated
`project_members` records, except that Accountant Accounts scope derives from
protected scoped-capability resolution and never from technical membership.

The exact Accounts capability keys, 90/10 policy defaults, 10/50/30/5/5 stage
defaults and Common-allocation exclusion are frozen in
`docs/yorks-v1/R39_ACCOUNTS_FOUNDATION.md`. T01 is additive/shadow-only;
it protects the default-stage template and its 100% total but does not create
project physical-building allocation relations or constraints. Those ship in
T02 with the commercial baseline. Normalized Accounts routes remain
unreachable and the feature flag remains off until their later phased
acceptance. Legacy `/admin/finance` is not authority.

## Canonical workflow

`Project -> BOQ -> MR Draft -> Submit -> Arrange/Reserve -> Project Engineer Approval -> Dispatch -> Delivery Order -> Receipt Review -> Return`

- Selecting BOQ data creates a draft only. Procurement sees nothing until the
  explicit Submit command succeeds.
- Procurement records every line as Full, Partial or Cannot Provide Now.
- Partial and unavailable lines require reasons and remain visible.
- Saving the current arrangement version replaces reservations atomically and
  transfers ownership to assigned Project Engineers.
- Procurement cannot self-approve.
- Dispatch uses only approved outstanding quantity and commits stock once.
- A Delivery Order may be generated as soon as a dispatch is committed and
  snapshots dispatched quantities; later receipt facts remain separate.
- Receipt review records every line as Received, Missing or Damaged. Only good
  quantity counts as received; missing/damaged quantity remains replacement
  eligible within the approved cap.
- Returns are limited to net eligible good-received quantity. Inventory changes
  only after Procurement confirms physical receipt.

## Transaction and quantity rules

All critical commands re-check actor, role, membership, record version, state
and quantities on the server. Use decimal-safe Postgres numeric arithmetic,
row locks and idempotency keys.

- `arranged_qty <= requested_qty`
- `approved_qty <= arranged_qty`
- `good_received_qty + in_transit_qty <= approved_qty`
- warehouse dispatch cannot exceed available stock at transaction commit
- confirmed return cannot exceed good received minus prior confirmed returns
- missing or damaged quantity never increments good received
- a retry cannot duplicate a document number, reservation, movement, dispatch,
  receipt, return, snapshot or audit event

Do not use ambiguous aggregate workflow statuses named `Arranged`, `Done` or
`Processed`. The verb Arrange and the noun Arrangement are approved.

## UI and responsive rules

- Use existing `AppColors`, `AppSpacing`, `AppTypography` and shared widgets.
- No hard-coded user-facing strings. Preserve English and the configured
  secondary language.
- Important records show state, current owner, next action, actor, role and
  timestamp.
- Desktop uses the persistent office sidebar, full spreadsheet, sticky headers
  and first column, keyboard operation and visible focus/sync state.
- Desktop grids support Tab/Shift+Tab, arrows, Enter/Shift+Enter and insert
  Similar/Blank Row directly below the active row.
- Mobile uses compact/bottom navigation, at least 44x44 tap targets, card lists
  and a focused one-row editor. Do not shrink the desktop spreadsheet into the
  editing experience.
- Project creation follows the effective R35 five-stage flow: Project Details;
  Parties and Access; Buildings; optional Attachments; Review and Create.
- Motion is short, subtle, non-blocking and respects reduced-motion settings.
- Do not add weighted project-completeness behavior to the V1 workflow.

## BOQ and controlled-document columns

BOQ worksheets are dynamic and preserve imported arbitrary columns. They also
store canonical searchable mappings. Arbitrary technical columns are visible
only in that BOQ worksheet; they do not silently become standard MR columns.

Each real Common/building scope owns its own BOQ folder catalogue. New scopes
receive only the active default template, currently Workshop Materials.
Creating, renaming, archiving or restoring a folder affects only the selected
real scope; it never propagates a folder name or shell to another building.
The visible Workshop Materials name may be changed, archived and restored per
scope while its stable `workshop_materials` template identity remains intact.
AC Units is not seeded or protected; any retained scope-local `ac_units` folder
may also be renamed, archived and restored. Archive is recoverable removal and
never deletes rows, documents, Material Request references or audit history.
Preserve all historical same-name sibling shells, group/row/column IDs,
documents and MR references created under the superseded project-wide rule.

The controlled MR Excel/PDF/print table is:

1. R No
2. Item Description
3. Brand/Origin
4. Qty
5. Unit
6. Unit Cost
7. Total Cost

Commercial columns are capability-controlled. Unauthorized queries, state,
caches, exports and documents must contain no commercial field or value.

Keep planning model/equipment-tag data separate from a manufacturer serial
number captured during receipt or asset registration, even if a legacy visible
label combines those concepts.

## Security rules

- UI hiding is not security. Enforce every boundary in RLS and trusted RPCs.
- Site Engineers receive no restricted commercial values by default. Project
  Engineers see Accounts commercial values by default (owner decision, 7 November
  2026, `PRODUCT_DECISIONS.md` section 29). Supplier costs and Material Request
  commercial columns keep their own controls.
- Commercial values live in protected relations/views and role-safe response
  shapes.
- Every RLS change requires positive and negative tests for Project Engineer,
  Site Engineer, Procurement and Admin.
- Procurement project and BOQ writes must fail through the UI, direct routes,
  ordinary table APIs and RPCs.
- Critical audit events are append-only and server-generated.
- Stock, reservation, dispatch, receipt and return commands are transactional
  and idempotent.
- Supabase Auth/Postgres are authoritative. Firebase is FCM transport only.
- Release builds fail closed when Supabase configuration is incomplete.
- Service-role credentials never ship in Flutter or browser assets.
- Storage authorization follows entity access and document classification, not
  knowledge of an object path.

## Offline and sync

- Local storage may hold drafts, permitted caches and queued non-critical work.
- Project activation, MR submission, arrangement save, approval, dispatch,
  receipt confirmation, return confirmation, inventory adjustment and
  administration require connectivity and server confirmation.
- Never show an optimistic success state for a critical transition.
- Realtime notifications trigger authorized re-fetches.
- Stale editable versions return a conflict; do not silently overwrite them.

## Data migration

- Existing JSON must continue to decode.
- Migrations are additive, idempotent and repeatable.
- Never silently discard undecodable rows or unknown fields; quarantine and
  report them.
- Never reinterpret `authorityRef` as an Other Contractor.
- Preserve stable IDs, document references, timestamps, actor attribution and
  historical commercial boundaries.
- Do not auto-promote a legacy `engineer` to Project Engineer. Role and project
  membership backfills require an explicit reconciliation mapping.
- Do not use app hydration or empty-table seed upload as a production migration.
- Do not hard-delete records with downstream activity. Archive, cancel, reject,
  supersede, void or correct them with an auditable reason.

## Code organisation

Follow current repository conventions and prefer small additions over a broad
Flutter rewrite:

- models: `lib/shared/models/`
- providers/controllers: `lib/shared/providers/` and `lib/shared/controllers/`
- repositories/data access: `lib/shared/repositories/` and `lib/shared/sync/`
- feature UI: `lib/features/<feature>/presentation/`
- reusable UI: existing core/shared widget locations
- routes and guards: `lib/app/router.dart`
- Postgres/RLS/RPC: `supabase/migrations/`
- database tests: `supabase/tests/database/`

Normalized V1 repositories may coexist with legacy JSON collections during
rollout. Do not force new transactional state through the generic collection
backend.

## Commands required before completion

Run narrow checks during development, then the complete applicable gate:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze
flutter test
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key \
  ./tool/r35.sh build-web
CI=true YORKS_CI_EPHEMERAL_SIGNING=true \
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key \
  ./tool/r35.sh build-apk
```

For local Chrome testing, create the ignored `.r35.env` from
`tool/r35.env.example` once, then use `./tool/r35.sh run`. The launcher enables
the complete R35 Yorks chain and requires an explicit backend; it never falls
back to a shared remote project. Legacy `NEXUS_V7_*` flags remain absent from
the application provider.

From Batch 1 onward, after the tracked local Supabase project exists:

```bash
supabase db reset
supabase test db
```

Documentation-only tasks have no Dart formatting target, but must still run
`git diff --check`, verify internal links and record the current baseline gate.
UI changes require desktop and 360px/mobile visual evidence. Release validation
requires a properly signed Android lane; a debug-signed APK is not a production
artifact.

## Pull request and batch discipline

- One approved batch/issue and one coherent vertical slice per PR.
- Before editing, identify exact models, repositories, RPC/RLS, routes, UI and
  tests affected.
- New feature flags default off until the batch acceptance gate passes. The
  accepted complete R35 chain is the documented exception and is enabled by
  default; legacy Nexus flags remain disabled.
- Include data-preservation and rollback notes for every migration.
- Include positive and negative permission tests for every access change.
- Include idempotency and competing-writer tests for critical quantity changes.
- Do not change unrelated modules.
- Leave the worktree clean and report files changed, commands, tests, evidence
  and limitations.

## Stop conditions

Stop and report instead of guessing when:

- Rev 2.0 and effective R35 still conflict after applying the authority order;
- a migration could lose, reinterpret or silently omit existing data;
- commercial response shape or RLS behavior is uncertain;
- a quantity, reservation, receipt or return invariant is not defined;
- a task needs destructive production changes, credentials or production
  access not already authorized;
- tests expose an unrelated existing failure;
- Android application identity/signing or a public deployment target requires
  a business decision.

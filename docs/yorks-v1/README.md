# Yorks V1 R35 — Implementation Source of Truth

Status: **approved re-baseline**
Approved: 1 August 2026
Current delivery stage: **Batches 0–9 complete; Batch 10 local release
evidence passed. Staging acceptance, protected Android signing and deployment
remain release-owner activities. R39 Accounts was approved on 25 August 2026;
its T01–T07 protected server/domain/UI slices are complete. The release owner
explicitly authorized production web enablement on 26 August 2026 while the
tracked flag default remains off for unconfigured and CI builds. Workforce T01
through T13 were independently accepted by 31 August 2026. The product owner
initially waived, then reinstated, the dedicated Workforce T14 staging UAT
phase; both decisions remain historical and T14 has never been recorded as a
pass. Dedicated Frankfurt staging project `iqltcyimlqtcwyzlemwx` now carries
the complete tracked migration ledger and the protected document Function,
but named-persona/manual UAT is still not performed. Later on 31 August 2026
the product owner explicitly deferred that UAT until after release and
authorized production immediately as a recorded release exception. The
verified Workforce artifact was later followed by the access recovery,
Administration enablement and matched Daily Crew Timesheet design. The current
artifact from commit `0abe54e93c95d281a80c9a651986ed1e222156e0` is promoted
as deployment `dpl_3qFwJVMAQ11YNGdzdxLvg2o6PYQF` at
`yorks-r35.vercel.app`; this does not convert T14 into a pass.**

> **HISTORICAL BATCH MATERIAL — NOT THE CURRENT BUILD CONFIGURATION.** The
> batch-completion files record the original incremental rollout and therefore
> may say that an individual R35 flag was default-off. The canonical R35 build
> configuration below is current: the accepted, complete R35 chain is on by
> default and legacy Nexus flags are disabled. The later
> `YORKS_V1_ACCOUNTS` flag is an intentional exception and remains separately
> operator-controlled. Production web enablement was explicitly authorized on
> 26 August 2026; the tracked default remains off.

This folder is the repository-local contract for the Yorks V1 Procurement
Control and Inventory turnaround. Rev 2.0 supersedes the overlapping Nexus V7
product workflow. The existing V7 implementation remains valuable evidence and
a reuse source, but it no longer defines V1 behavior.

## Authority order

1. Yorks V1 SRS and Rapid Development Plan, Rev 2.0
2. Effective final R35 HTML behavior for non-conflicting UI and interaction
3. Yorks V1 Sol AI Execution Pack for delivery sequencing
4. [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) for resolved ambiguities
5. Current repository implementation as the reuse and migration boundary
6. `docs/nexus-v7/` as historical evidence and inherited non-conflicting
   security, migration, localization and non-regression safeguards

See [`SOURCE_OF_TRUTH.md`](SOURCE_OF_TRUTH.md) for source fingerprints and the
explicit V7-to-V1 conflict resolution.

## Mandatory documents

| Document | Purpose |
|---|---|
| [`SOURCE_OF_TRUTH.md`](SOURCE_OF_TRUTH.md) | Authority, source fingerprints and superseded rules |
| [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) | Frozen workflow, data and ambiguity resolutions |
| [`CURRENT_TO_TARGET_GAP_ANALYSIS.md`](CURRENT_TO_TARGET_GAP_ANALYSIS.md) | Exact current code reuse, gaps and risks |
| [`ARCHITECTURE_AND_SECURITY_CONTRACT.md`](ARCHITECTURE_AND_SECURITY_CONTRACT.md) | Flutter/Supabase boundary and trusted data flow |
| [`SCOPED_CAPABILITY_MANAGEMENT.md`](SCOPED_CAPABILITY_MANAGEMENT.md) | Hybrid role-template and person-specific scoped permissions, compatibility, delegation, parity and rollout contract |
| [`R39_ACCOUNTS_FOUNDATION.md`](R39_ACCOUNTS_FOUNDATION.md) | Approved Accounts-only authority, ninth exact role, exact capabilities, defaults, phased rollout and T01 security gate |
| [`R39_ACCOUNTS_OFFICE_AUDIT_AND_IMPLEMENTATION.md`](R39_ACCOUNTS_OFFICE_AUDIT_AND_IMPLEMENTATION.md) | Source-grounded Accountant landing/office audit, workbook findings, T08 read-projection design, verification and remaining decisions |
| [`R39_YRA322_MASTER_FILE_RECONCILIATION.md`](R39_YRA322_MASTER_FILE_RECONCILIATION.md) | Audited mapping of the Nexus master workbook into YRA-322 baseline, confirmed progress, exclusions, production evidence and rollback |
| [`WORKFORCE_ATTENDANCE_TIMESHEETS.md`](WORKFORCE_ATTENDANCE_TIMESHEETS.md) | Approved Workforce authority through independently accepted T13 plus the reinstated T14 staging contract, including RLS, rollout and rollback |
| [`WORKFORCE_T13_HARDENING_EVIDENCE.md`](WORKFORCE_T13_HARDENING_EVIDENCE.md) | Accepted T13 security, race, scale, responsive, build and limitation evidence; no release action |
| [`WORKFORCE_T14_STAGING_UAT_EVIDENCE.md`](WORKFORCE_T14_STAGING_UAT_EVIDENCE.md) | Reinstated T14 contract, initialized staging identity, 35-scenario witness matrix and current post-release deferral status |
| [`WORKFORCE_PRODUCTION_RELEASE_EVIDENCE.md`](WORKFORCE_PRODUCTION_RELEASE_EVIDENCE.md) | Owner-exception production release: source, migration ledger, artifact/deployment hashes, live routes, rollback and explicit T14 boundary |
| [`STATE_RPC_RLS_MATRIX.md`](STATE_RPC_RLS_MATRIX.md) | States, server commands, locks, idempotency and access |
| [`R35_UI_CONTRACT.md`](R35_UI_CONTRACT.md) | Role navigation, screens, components and responsive behavior |
| [`OPERATIONAL_ANALYTICS_AND_FOUNDER_OVERVIEW.md`](OPERATIONAL_ANALYTICS_AND_FOUNDER_OVERVIEW.md) | Approved Overview and separately authorized read-only Analytics data, UX, responsive and rollout contract |
| [`USER_PROFILE_UX_AUDIT_AND_REDESIGN.md`](USER_PROFILE_UX_AUDIT_AND_REDESIGN.md) | Unified My Yorks audit and roadmap; P01–P05 are locally accepted, including protected role-aware summaries, access scope, quick links and separate Workforce identity; the P06 dedicated staging candidate is deployed and named-persona UAT remains pending |
| [`CURRENT_MATERIAL_REQUEST_USER_GUIDE.md`](CURRENT_MATERIAL_REQUEST_USER_GUIDE.md) | Current approval-first MR operating guide, roles, screen cues and legacy-record boundary |
| [`COMPANY_MATERIAL_REQUEST_T01_IMPLEMENTATION.md`](COMPANY_MATERIAL_REQUEST_T01_IMPLEMENTATION.md) | Release-gated, project-independent company-use create and submit slice, authorization boundary and rollout requirements |
| [`COMPANY_MATERIAL_REQUEST_T02_APPROVAL.md`](COMPANY_MATERIAL_REQUEST_T02_APPROVAL.md) | Feature-gated independent company approval candidate, immutable decision evidence and explicit pre-fulfilment boundary |
| [`COMPANY_MATERIAL_REQUEST_T03_T05_FULFILMENT.md`](COMPANY_MATERIAL_REQUEST_T03_T05_FULFILMENT.md) | Feature-gated supply planning, shared reservations, dispatch, receipt, beneficiary custody, returns and closure |
| [`COMPANY_MATERIAL_REQUEST_T06_END_TO_END_HARDENING.md`](COMPANY_MATERIAL_REQUEST_T06_END_TO_END_HARDENING.md) | Feature-gated signed-in lifecycle hardening, remaining-demand withdrawal, immutable issue notes, registers and explicit release boundary |
| [`COMPANY_MATERIAL_REQUEST_UNIFIED_EXPERIENCE.md`](COMPANY_MATERIAL_REQUEST_UNIFIED_EXPERIENCE.md) | Shared Project/Company navigation, concise Company records, reviewable operations and protected paged search |
| [`MATERIAL_REQUEST_ACTION_INTELLIGENCE.md`](MATERIAL_REQUEST_ACTION_INTELLIGENCE.md) | My Work, Exceptions, required-date/age indicators, trusted line ledger, operational metrics and the explicit SLA boundary |
| [`MATERIAL_REQUEST_DISCUSSION_SPEC.md`](MATERIAL_REQUEST_DISCUSSION_SPEC.md) | Proposed full-width contextual Material Request discussion, replies, direct attachments, exact-comment notifications, responsive UX and staged release contract |
| [`MATERIAL_REQUEST_FILE_AND_ACTION_UI.md`](MATERIAL_REQUEST_FILE_AND_ACTION_UI.md) | Shared file markers, grouped Material Request actions and consistent Request Information panel behavior |
| [`MR_SAVE_EDIT_RELEASE_2026-09-25.md`](MR_SAVE_EDIT_RELEASE_2026-09-25.md) | Authorized Project MR Save flow, preserved approval and edit evidence, staging and rollback gates |
| [`MATERIAL_REQUEST_WORKSPACE_REDESIGN_PLAN.md`](MATERIAL_REQUEST_WORKSPACE_REDESIGN_PLAN.md) | Approved cleaner MR workspace reference, optional information/audit panel, functionality-preservation map, measured visual handoff and staged acceptance plan |
| [`MATERIAL_REQUEST_PROCUREMENT_ITEM_CLARIFICATION.md`](MATERIAL_REQUEST_PROCUREMENT_ITEM_CLARIFICATION.md) | Procurement item-name/model clarification, shared smart search, immutable requested evidence, save lock and audit contract |
| [`ARRANGEMENT_WORKBENCH_SRS.md`](ARRANGEMENT_WORKBENCH_SRS.md) | Proposed non-regressing arrangement workbench: private progress, safe Back/resume, stock/clarification/uncertain-save handling and responsive UI |
| [`ARRANGEMENT_WORKBENCH_IMPLEMENTATION_PLAN.md`](ARRANGEMENT_WORKBENCH_IMPLEMENTATION_PLAN.md) | Implementation slices, source/test map, edge-case acceptance matrix, staging and rollback gates; not a release approval |
| [`MATERIAL_REQUEST_ACTION_INTELLIGENCE_EVIDENCE.md`](MATERIAL_REQUEST_ACTION_INTELLIGENCE_EVIDENCE.md) | Local database, Flutter, visual and production-shaped build evidence for the action-intelligence release |
| [`R38_UI_CONTRACT.md`](R38_UI_CONTRACT.md) | Rendered R38 visual contract and approved production exceptions |
| [`R38_4_RENTAL_PROPERTIES.md`](R38_4_RENTAL_PROPERTIES.md) | Admin-only rental property, lease, rent, cheque, import/export and controlled-document implementation |
| [`R38_5_TEAM_CHAT_IMPLEMENTATION.md`](R38_5_TEAM_CHAT_IMPLEMENTATION.md) | R38.5 contextual Team Chat architecture, permissions, Storage, notification, responsive UI and rollback contract |
| [`R38_9_INVENTORY_SUPPLIER_FOLDERS.md`](R38_9_INVENTORY_SUPPLIER_FOLDERS.md) | R38.9 supplier folders, Unknown Supplier, five-stage import, receipt provenance and migration safety contract |
| [`MATERIAL_RETURN_CONTROLLED_WORKFLOW.md`](MATERIAL_RETURN_CONTROLLED_WORKFLOW.md) | Project-wide Material Return lifecycle, provenance, approval, warehouse receipt, document and rollback contract |
| [`V01_VISUAL_EVIDENCE.md`](V01_VISUAL_EVIDENCE.md) | Workspace shell, empty Overview and Project Creation convergence evidence |
| [`MOBILE_UI_IMPLEMENTATION_GUIDE.md`](MOBILE_UI_IMPLEMENTATION_GUIDE.md) | Mobile-only authority split, guard, state/permission checklist and evidence workflow |
| [`MOBILE_UI_SCREEN_LEDGER.md`](MOBILE_UI_SCREEN_LEDGER.md) | Delivery state for all 52 mobile design references |
| [`FIREBASE_MESSAGING_SETUP.md`](FIREBASE_MESSAGING_SETUP.md) | Firebase Cloud Messaging client, web worker and operator credential setup |
| [`evidence/mobile-batch-02/README.md`](evidence/mobile-batch-02/README.md) | Verified local evidence index for mobile references 12–21 |
| [`evidence/r38-configuration-20260814/README.md`](evidence/r38-configuration-20260814/README.md) | R38 Configuration Centre security, behavior and responsive visual evidence |
| [`evidence/r38-5-team-chat-20260814/README.md`](evidence/r38-5-team-chat-20260814/README.md) | R38.5 Team Chat desktop, tablet and mobile visual/security evidence |
| [`MIGRATION_AND_ROLLBACK_PLAN.md`](MIGRATION_AND_ROLLBACK_PLAN.md) | Additive migration, reconciliation, quarantine and rollback |
| [`MATERIAL_REQUEST_DRAFT_LIFECYCLE.md`](MATERIAL_REQUEST_DRAFT_LIFECYCLE.md) | Private recovery deletion, retirement, concurrency and telemetry contract |
| [`TEST_AND_ACCEPTANCE_PLAN.md`](TEST_AND_ACCEPTANCE_PLAN.md) | Canonical scenarios, R39 phase gates and platform/security evidence |
| [`YORKS_PERFORMANCE_REVIEW.md`](YORKS_PERFORMANCE_REVIEW.md) | Measured production performance findings, incremental fixes, release evidence and remaining attribution |
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | Dependency-ordered Batches 0–10 |
| [`BATCH_00_COMPLETION.md`](BATCH_00_COMPLETION.md) | Re-baseline changes, verification and known blockers |
| [`BATCH_02_COMPLETION.md`](BATCH_02_COMPLETION.md) | Identity, projects, audit/RLS hardening and verification |
| [`BATCH_03_COMPLETION.md`](BATCH_03_COMPLETION.md) | Editable BOQ groups, responsive spreadsheet and verification |
| [`BATCH_04_COMPLETION.md`](BATCH_04_COMPLETION.md) | Excel BOQ round-trip, protected import command and verification |
| [`BATCH_08_COMPLETION.md`](BATCH_08_COMPLETION.md) | Delivery Orders, returns and verification |
| [`BATCH_09_COMPLETION.md`](BATCH_09_COMPLETION.md) | Controlled documents, audit and retained-module coverage |
| [`BATCH_10_RELEASE_READINESS.md`](BATCH_10_RELEASE_READINESS.md) | Local release evidence, staging matrix and controlled-cutover runbook |
| [`R35_STAGING_DEPLOYMENT.md`](R35_STAGING_DEPLOYMENT.md) | Dedicated staging deployment and controlled-document witness |
| [`RELEASE_NOTES_DRAFT.md`](RELEASE_NOTES_DRAFT.md) | Release content and conditions for the staging sign-off |

## Product north star

- Calm before clever.
- Information before decoration.
- Speed through familiarity.
- Confidence through transparency.
- Precision over personality.
- One source of truth.
- Familiar spreadsheet behavior for engineers without weakening server rules.

## Canonical R35 build configuration

Yorks V1 is the production experience by default. Supabase targets are
explicit: an unconfigured build stops rather than falling back to a shared
remote project. Configure the intended local, staging or production backend
once in an ignored file, then use the launcher without manual dart-defines:

```bash
cp tool/r35.env.example .r35.env
# Edit .r35.env with the chosen target's HTTPS URL and publishable key.
./tool/r35.sh run
./tool/r35.sh build-web
./tool/r35.sh build-apk
```

Use a separately named ignored configuration file for staging/production via
`R35_CONFIG_FILE=.r35.staging.env` or `.r35.production.env`. The tracked
`../../tool/r35.sh` launcher always supplies the complete R35 flags; do not add
legacy `NEXUS_V7_*` flags to an R35 command.

## Canonical operational chain

`Project -> BOQ -> MR Draft -> Submit -> Engineering Approval -> Arrange/Reserve -> Dispatch -> Delivery Order -> Receipt Review -> Return`

The Delivery Order snapshots a committed dispatch and is available immediately
after that dispatch. Receipt review records later good, missing and damaged
facts without rewriting the Delivery Order. Only historical requests that
already entered the former post-arrangement approval path retain that recorded
lane; new requests always use approval before Procurement arrangement.

R39 adds normalized project commercial-control Accounts through phases T01–T07
without changing this operational chain. T01 is additive/shadow-only; later
phases cut over tested Accounts surfaces behind `YORKS_V1_ACCOUNTS`. The
legacy `/admin/finance` route is not Accounts authority. The full
RFQ/quotation/PO and general-accounting suites are not part of V1.
Configuration, Rentals, User Management, Audit Trail, Duct Sizer and ESP
Calculator remain in place and receive regression coverage rather than
Accounts-driven redesign.

Workforce adds a separate phased chain behind `YORKS_V1_WORKFORCE`. T01 through
T04 are additive and route-less; T05 adds the guarded Supervisor Daily Roster.
T03 promotes `workforce.view` and
`workforce.attendance.maintain`; T04 promotes only
`workforce.timesheets.maintain` for protected allocation and later monthly-
validation RPCs. The remaining nine capability rows stay planned/shadow/
nonassignable. The tracked flag defaults off. Existing People/HR, Leave and
legacy attendance collections remain preserved and are not dual-written.

## How to execute a batch

1. Name the exact batch and acceptance slice.
2. Read `AGENTS.md` plus this README, source-of-truth and product decisions.
3. Read the task-relevant architecture/UI/migration/test sections.
4. Audit exact current files and symbols before editing.
5. Implement only the approved slice. Keep new work guarded until its
   acceptance gate passes; once accepted into the complete R35 chain, the
   canonical build configuration controls its default state.
6. Add migration/rollback notes, negative RLS tests and idempotency proof where
   applicable.
7. Run narrow checks and the complete applicable gate.
8. Report files, migrations, commands, evidence and limitations.

The rapid three-day grouping is a client-testable demo target. It is not a
waiver for RLS, transaction, migration, Android or production hardening.

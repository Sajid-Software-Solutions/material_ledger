# Material Request Flow Revision — 13 August 2026

Status: product-owner approved implementation contract.

This revision changes the order of Engineering approval and Procurement
arrangement for newly submitted Material Requests. It also adds an authorized
discussion thread with mentions, non-commercial inventory-assisted item entry,
clear lifecycle presentation, and operational receipt photographs.

## Evidence-backed impact and defect table

| Area | Current behavior | Approved behavior | Root cause / implementation impact |
|---|---|---|---|
| Request approval order | Submit hands the request to Procurement; Engineering approves the completed arrangement | Submit hands the request to Engineering; Procurement may begin only after request approval | The current state/RPC contract encodes `submitted -> arranging -> awaiting_approval`. New states and a new request-decision command are required; this cannot be solved by relabeling UI actions. |
| Stage-one editing | Only creator-owned `draft` rows are editable | Until request approval, the creator and an authorized Project Engineer may edit the Engineering request through a version-checked command | The existing draft RPC rejects every submitted record and has creator-only ownership. A separate trusted edit command must preserve the submitted number, attribution and audit history. |
| Arrangement completion | A saved arrangement waits for Engineering approval | A saved arrangement for a pre-approved request becomes dispatch-approved immediately; legacy arrangements retain their recorded post-arrangement decision path | The existing save command always creates `awaiting_approval`. It must branch on a real immutable request-approval record, never infer approval from state or role. |
| Discussion | Normalized V1 Material Requests have no trusted discussion relation | Authorized participants can comment from the first server-backed request stage, mention authorized users and generate notifications | Legacy JSON comments are not a transaction or RLS authority. New append-only comment and mention relations/RPCs are required. |
| Mention privacy | No scoped mention directory | Mention suggestions contain only authorized display name, exact role and opaque user ID for participants allowed to read that request | The broad profile directory is unsuitable: it excludes global Engineer roles and is not scoped to an MR/project. |
| Material-assisted request entry | Engineers enter custom description fields manually or search inventory only | One non-commercial project-authorized search ranks selected-scope BOQ, wider-project BOQ and then inventory; it copies descriptive data while preserving free text | BOQ scope identity must remain exact, cross-scope suggestions cannot masquerade as same-scope BOQ sources, protected stock/commercial facts remain absent and quantity remains user-entered. |
| Engineering visibility | Submitted request visibility follows existing project/global-role reads; drafts remain creator/Admin only | Active assigned Project/Site Engineers and organization-wide Senior Mechanical Engineers/Project Managers can read all server-backed workflow stages and discussion; private local recovery input remains creator-only | Read helpers and tests must explicitly cover all four Engineering roles without widening Procurement or commercial access. |
| Status clarity | State appears in parts of the workspace but the next owner/action is not consistently prominent | Detail and controlled form show a stable human status plus current owner and next action | Presentation currently maps the old state order and cannot distinguish pre-approval from arrangement review. |
| Close authority | Only Project Engineer/global Project Engineer roles and Admin can close a fully received request | An actively assigned Site Engineer may also close after all server quantity and receipt checks pass | Both the private authorization helper and presentation preflight must widen; the trusted close command, membership check, version, idempotency and audit boundary remain unchanged. |
| Tablet/mobile refresh | A healthy Realtime channel can appear subscribed after browser/app suspension while no longer delivering workflow signals | Re-fetch authorized projections on foreground resume and a low-frequency safety interval, retain the visible projection during refresh, and offer pull-to-refresh on the mobile register | Realtime remains metadata-only; every refresh reuses normal protected RPC reads and no local state transition is synthesized. |
| Receipt evidence | Receipt review records quantities/notes only | After server confirmation, an authorized receiving Engineer may attach JPEG, PNG or WebP site photographs linked to that immutable receipt review | The generic document pipeline does not currently accept `receipt_review` as a link/upload target. The existing prepare/upload/finalize boundary will be extended rather than bypassed. |
| Draft privacy | Assigned/global Engineering could discover another user's server-backed draft through shared project reads | Draft detail, list presence, discussion and mentions remain creator/Admin only until explicit Submit | A draft is unfinished personal work. The shared workflow begins at submission, not the first autosave. |
| Mixed receipt exception | One line can be only Received, Missing or Damaged | One line may record exact Good, Missing and Damaged quantities together; their sum must equal dispatched quantity | Physical deliveries commonly include both missing and damaged pieces on the same dispatch line. Splitting the requested item is needless work and weakens traceability. |
| All unavailable | A legacy all-unavailable approval could close the MR | Keep the arrangement editable by Procurement; only a deliberate Engineering/Admin cancellation with reason is terminal | Zero available supply is operational work, not evidence that the request is completed. |

## New-request state machine

```text
draft
  -> awaiting_request_approval
  -> approved_for_arrangement
  -> arranging
  -> approved
  -> partially_dispatched / dispatched
  -> partially_received / received
  -> closed
```

- Returning a request before approval moves it back to `draft` only through a
  trusted decision with a required reason. Its number, original submission
  attribution, decision history and audit events are retained.
- An edit in `awaiting_request_approval` replaces only the current Engineering
  line snapshot. It is version-checked and audited. The later approved
  post-approval editing decision below governs the limited exception before
  any arrangement exists.
- The request approval freezes the exact approved Engineering version. It does
  not create inventory reservations or commercial facts.
- **24 September 2026 amendment:** an eligible approver may enable an audited,
  default-off post-approval edit window for an approved request before
  Procurement begins arrangement. The approver may designate one active
  Procurement editor and revoke the grant. The existing **Edit request** action
  appears beside Approve for Procurement or Arrange. A saved edit becomes a
  new request version awaiting Engineering approval; old decisions and revision
  snapshots remain intact, and retained lines keep their IDs. Procurement
  cannot approve its own edit or begin arrangement until reapproval. Any
  arrangement, reservation or dispatch permanently closes this editing window
  for that request.
- Saving a complete arrangement for a request with a current approval creates
  approved line quantities from arranged quantities and makes positive lines
  dispatchable. Partial and unavailable decisions remain truthful exceptions.
- A complete arrangement with no positive line stays in Procurement work with
  the all-unavailable reason visible and editable. It closes only through an
  explicit, authorized cancellation, after which Procurement editing fails.
- Receipt review supports `mixed` with separately stored Good, Missing and
  Damaged quantities that reconcile exactly to the dispatched snapshot.

## Existing-data preservation

- Existing `arranging` and `awaiting_approval` requests continue through the
  former post-arrangement approval path. No synthetic pre-approval row is
  created and no reservation is released or replaced by this migration.
- The former post-arrangement approval controls are disabled in production.
  They remain behind the off-by-default
  `YORKS_V1_LEGACY_ARRANGEMENT_REVIEW` compatibility flag only while historical
  beta records are reconciled.
- Existing `approved`, dispatch, receipt, Delivery Order, return, document and
  audit records are unchanged.
- Existing `submitted` records without an arrangement are reclassified as
  `awaiting_request_approval`, because no Procurement fact exists to preserve.
  The migration records the system transition through the row version and
  timestamp without fabricating a human actor event.
- Rollback is forward-only: disable new client actions, retain additive tables
  and functions, and deploy a corrective migration. Do not drop comment,
  decision, mention, document-link or audit history.

## Authorization summary

- Creator: privately edit/comment on their own draft; after Submit, edit own
  request before approval and comment while request-readable.
- Assigned Project Engineer: read, edit, approve/return and comment.
- Assigned Site Engineer: read and comment; can edit only when they are the
  creator; may close a fully resolved received request; cannot approve unless
  separately holding valid Project Engineer authority.
- Senior Mechanical Engineer / Project Manager: organization-wide read,
  edit, approve/return and comment with exact role preserved.
- Procurement: reads/comments after request approval, arranges and dispatches;
  a single explicitly designated active Procurement user may propose an edit
  inside the pre-arrangement window, but cannot approve it.
- Admin: audited override within the same versioned commands; no fabricated
  actor events.

Temporary adoption policies approved for Phases 1-3:

- a non-Site-Engineer creator may self-approve only when they also hold valid
  Project Engineer/global Engineering/Admin authority; Site Engineer creators
  cannot self-approve;
- external supplier readiness is not yet a blocking completion gate; and
- Phase 3 exposes both policies as protected Admin configuration. Only a
  published version affects trusted commands; draft changes remain inert and
  prior actor, role, decision and supplier evidence is never rewritten.

## Acceptance additions

1. New submit produces `awaiting_request_approval`, not Procurement ownership.
2. Procurement begin-arrangement fails before request approval through RPC and
   ordinary table APIs.
3. Creator and valid Project Engineer edits are atomic, version-checked and
   audited; Site Engineer non-creator and Procurement edits fail.
4. Request approval is idempotent, preserves exact role and is required before
   the new arrangement path.
5. New arrangement save creates approved quantities once; a retry cannot
   duplicate approvals/reservations/audit.
6. Legacy awaiting-arrangement decisions remain resolvable without history
   rewrite.
7. Mentioned authorized users receive one notification; unauthorized or stale
   members cannot be mentioned or read the thread.
8. Ranked material search returns selected-scope BOQ, project BOQ and inventory
   in that order; it returns no costs, balances, reservations, minimum stock or
   other protected fields and fills only descriptive request data. No match
   continues as unrestricted free text.
9. Status/owner/next action are consistent across desktop, mobile and the
   controlled MR model.
10. Receipt photograph upload is available only after confirmed receipt and is
    readable only through the receipt/request project authorization boundary.
11. An actively assigned Site Engineer can close a fully resolved received
    request; Procurement and an unrelated or inactive Site Engineer cannot.
12. Tablet/mobile projections re-fetch after foreground resume and by safety
    interval without blanking the current view; mobile also supports pull to
    refresh.
13. Another Engineering participant cannot list, open, comment on or mention
    from a creator's draft; access begins only after Submit.
14. A mixed receipt stores separate Good/Missing/Damaged facts and rejects any
    under- or over-reconciled quantity set atomically.
15. All-unavailable remains Procurement-editable; explicit cancellation makes
    it terminal and a later Procurement save fails.

## Phase 2 collaboration and performance addendum

Phase 2 improves coordination and loading behavior without changing the
approval-first state machine:

- registers load lightweight authorized summaries in server pages of 15;
  search, filters, ordering and counts are server-authoritative, while full
  lines/comments are fetched only when a request is opened;
- the newest 20 comments load with the record and older comments use cursor
  paging;
- a valid request participant may claim responsibility or reassign it to an
  eligible participant with a reason. This is an audited coordination marker,
  not a state transition and not a substitute for workflow authority;
- an unsubmitted draft may sync privately to its creator's account while the
  existing local draft remains offline recovery. A stale server version is a
  visible conflict and never silently overwrites newer work;
- immutable Engineering revision snapshots derive the concise change summary
  shown after a request is returned and edited.

The temporary adoption choices above remain unchanged in Phase 2 and are
carried into Phase 3 as explicit policy inputs.

## Phase 3 policy and recovery addendum

Phase 3 completes the approved adoption controls without changing the familiar
approval-first sequence:

- `requests.allow_authorized_creator_self_approval` publishes whether a valid
  non-Site-Engineer creator may approve their own current request version. The
  default is `true`; publishing `false` requires another authorized
  Project Engineer/global Engineering/Admin actor. Site Engineer creators
  remain unable to approve in either mode;
- every positive External Supplier arrangement line can record **Source ready
  / firmly committed**, an optional expected date and an optional reference.
  `procurement.require_external_source_readiness` defaults to `false`; when an
  Admin publishes `true`, the server rejects an unconfirmed external line
  atomically. Supplier name remains optional;
- after Engineering explicitly cancels an all-unavailable request, an
  authorized Engineering creator may use **Create replacement request**. The
  server creates exactly one linked private Draft, clones the immutable request
  facts and line provenance, and leaves the source cancelled. Procurement has
  no replacement-create authority; and
- exact retries return the same result. A different command cannot create a
  second replacement from the same source, and neither path fabricates
  approval, arrangement, stock, dispatch or receipt history.

Phase 3 adds no automatic cancellation. Until Engineering cancels,
all-unavailable remains editable Procurement work exactly as established in
Phase 1.

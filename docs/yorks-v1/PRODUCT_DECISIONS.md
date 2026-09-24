# Yorks V1 R35 — Frozen Product and Transaction Decisions

Status: approved Batch 0 contract from 1 August 2026.

This file resolves material ambiguities in Rev 2.0 and the effective R35
prototype. It applies least privilege, data preservation and the approved source
hierarchy. A later change requires explicit product approval and matching
updates to state, RLS, migration and acceptance documents.

## 1. Platform and authority

- Flutter, Riverpod and GoRouter remain the application foundation.
- Product-authority clarification (1 August 2026): the Rev 2.0 SRS defines
  the production flows and the effective R35 HTML defines the target UI and
  interaction model. Existing V1/V7 behavior is retained only where it does
  not conflict; it is replaced or isolated when the approved product requires
  different behavior.
- Public product identity is **Yorks AC. & Ref.**; the full company label is
  **Yorks Air Conditioning & Refrigeration LLC-SPC**, both taken from the
  approved R35 HTML. Historical Nexus terms may remain only in internal code
  namespaces and historical documentation, never in user-facing product copy.
- Supabase Auth and Postgres are the production identity and data authority.
- Postgres constraints and trusted RPCs own state and quantity invariants.
- Realtime only signals an authorized refresh.
- Local storage supports permitted cache, draft recovery and queued
  non-critical work. It is not authoritative for committed transitions.
- Controlled-document snapshots are immutable historical truth.
- Firebase is allowed only for FCM transport.
- Product-owner clarification (14 August 2026): Team Chat owns message and
  mention attention. A Chat event may use a private `v1_notifications` row as
  the durable FCM/outbox transport source, but it never appears in or increments
  the workflow notification centre/bell. The authoritative Chat badge and
  cross-device read state come from the conversation-member cursor. New
  contextual Material Request discussion uses Team Chat and follows the same
  rule. Ordinary workflow notifications and preserved pre-Team-Chat history
  retain their existing workflow surface.
- Product-owner clarification (28 August 2026): the original sender may edit
  the text or soft-delete their own ordinary Direct, Project, Group and
  Announcement messages while they remain an active conversation member.
  Material Request conversation messages remain append-only under AT-26.
  Every edit/delete is a version-checked trusted command, preserves the prior
  body in a private server-only revision, and leaves an attributed tombstone
  rather than removing history. Sent, delivered and read marks come only from
  server-owned member cursors; the client never infers receipt or presence.

## 2. Roles and identity

Canonical Auth role claims are:

- `project_engineer`
- `site_engineer`
- `senior_mechanical_engineer`
- `project_manager`
- `workshop_in_charge`
- `document_controller`
- `procurement`
- `accountant`
- `admin`

Claims come from server-controlled `app_metadata.role`. A protected profile may
mirror the claim for display and query convenience but cannot grant privilege.
Every server-authorized read or command compares the exact presented claim with
the current protected Auth record. A stale JWT fails closed even when its old
and new exact roles both normalize to the Project Engineer workflow role.

`senior_mechanical_engineer`, `project_manager`, `workshop_in_charge` and
`document_controller` are organization-wide Project Engineer roles. Trusted
commands normalize them to Project Engineer workflow authority and allow
access to every existing project without inserting synthetic membership
history. They can perform Project Engineer workflow actions and generate an
authorized Delivery Order, but they do not receive Procurement or stock
authority. Their exact claim remains available for display and audit. By
product-owner approval on 9 August 2026, Senior
Mechanical Engineer additionally receives audited User Management and user
capability-configuration authority. This does not grant that actor direct
commercial visibility or unrelated Admin modules. Project Manager retains no
user-management or capability-management authority; neither do Workshop
In-Charge or Document Controller. By product-owner approval on 15 August 2026,
Senior Mechanical Engineer also receives the full non-commercial
Browse/Inventory read projection. Item/category edits, stock receipts and
adjustments, imports and all other inventory writes remain Procurement/Admin
commands.

New server audit events retain both the normalized workflow role and the exact
Auth role. Historical events keep their existing canonical role and are not
silently backfilled with an invented exact claim.

A submitted MR also freezes that exact server-controlled role. Controlled
documents and audit presentation use the immutable exact role, so a Senior
Mechanical Engineer, Project Manager, Workshop In-Charge or Document Controller
is never relabeled as a Project Engineer on the form even though authorization
uses the normalized workflow role.

A Project Engineer approves the submitted Material Request only when they also
hold an active Project Engineer membership for that project. Procurement may
arrange only after that immutable approval. Saving the arrangement then makes
its arranged quantities dispatch-ready without a second Engineering review.
The legacy arrangement-decision command remains server-protected only for
historical records already in `awaiting_approval`; its UI is disabled by
default and new records never enter that state. A Site Engineer may create and
submit an MR, but cannot grant the request approval; an old or incorrect
`project_engineer` membership label must not elevate a Site Engineer account
into approval authority. Admin retains its audited override.

Legacy `engineer` identities are not automatically promoted. Migration creates
a reconciliation entry and blocks privileged Project Engineer actions until an
Admin records an explicit mapping. Existing project assignment provides
evidence, not automatic privilege escalation.

Admin creates/disables users through a protected server/Edge Function using a
service-role secret that never ships to Flutter. Referenced users are
deactivated rather than deleted.

By product-owner approval on 25 August 2026, `accountant` is the ninth exact
platform role. It is not a Project Engineer, Site Engineer or other technical
project-membership role and cannot be inserted into `project_members` to gain
technical authority. Accountant project Accounts scope comes from the
protected capability resolver. Accountant can act only through normalized
Accounts projections/commands that return an explicit command flag; it gains
no Project, BOQ, MR, Dispatch, Receipt, Inventory, Return or team-management
mutation authority. Historical actor attribution retains the exact role.

## 3. Default commercial access

Capabilities are `view_commercials` and `manage_commercials`.

These retained generic capabilities continue to protect existing operational
commercial projections. They do not authorize R39 Accounts. Accounts uses the
15 exact capability keys frozen in section 23 and never infers an Accounts
command from either generic capability alone.

- Project Engineer and Site Engineer have no commercial access by default.
- Procurement and Admin have both capabilities by default; Admin can revoke
  either through protected capability administration.
- Project/Site Engineers have neither capability by default. V1 may grant an
  Engineer `view_commercials`, but never `manage_commercials`.
- An unauthorized response does not contain zeroed or masked cost fields. It
  uses a non-commercial database view/response shape with no cost schema.
- Commercial values never enter unauthorized Riverpod state, local caches,
  exports, print jobs, notifications or logs.
- The authorized controlled MR table has the seven approved columns including
  Unit Cost and Total Cost. The non-commercial projection contains only R No,
  Item Description, Brand/Origin, Qty and Unit.
- Cost uses fixed-decimal values and an explicit currency code, default AED.
  Total Cost is derived consistently from quantity and Unit Cost; the client
  cannot submit an authoritative total.
- Capability revocation purges protected local projections before reload.

Widening Engineer cost access is a later explicit business/security decision,
not an inferred consequence of MR approval.

## 4. Projects, scopes and membership

Project lifecycle:

`draft -> active -> on_hold -> completed -> archived`

- Draft and Active project information may be edited by an authorized Project
  or Site Engineer, subject to membership rules.
- The project creator receives an initial active project membership at creation,
  so they may edit their Draft or Active project while that membership remains
  active. Revocation removes that future authority; it does not rewrite history.
- On Hold blocks new MR submission and dispatch but permits authorized review,
  documents and an Admin-controlled resume.
- Completed blocks new BOQ/MR work but permits outstanding receipt, return,
  document and closure activity.
- Archived is read-only except for audited Admin correction metadata.
- “Delete project” is an Admin-only safe archive, never a physical delete. It
  requires an auditable reason and is blocked while any Material Request is
  operationally open; requests, documents, scopes, memberships and audit
  history are retained.
- Procurement may read Active and On Hold projects. It may also read Completed
  projects while an authorized receipt, return or document action remains open.
  Archived access is search/audit-only.

Every project has physical Building scopes plus one explicit immutable Common
scope. Each real scope owns its own BOQ groups, columns, rows, imports,
documents, exports and BOQ-derived Material Request sources. The UI's
**Overview**
option is a read-only project overview, never a persisted scope, editable
worksheet, export target or MR source. It summarizes every scope without
flattening building rows into an ambiguous editable table.

Existing pre-R38 project-level BOQ groups remain scope-less and visible in
Overview
as `legacy/unassigned`. Their folder name may be represented by independent
empty folder shells in Common/buildings, but their rows and columns are not
copied or inferred into any scope.
An authorized engineer must explicitly version-map one such group to one active
real scope; submitted history or draft sources for a different scope block that
mapping and require reconciliation. Every submitted MR selects exactly one
active scope; a BOQ source must belong to that same scope and may never be
silently mixed across Common/buildings.

Membership records have effective-from/effective-to timestamps, actor and
reason. Revocation prevents future actions but never removes historical access
attribution.

A Site Engineer may select an initial Project Engineer during project creation.
That one creation-time assignment is permitted by the transaction; after
creation, team access changes require an active Project Engineer or Admin.
Activation requires at least one active Project Engineer.

## 5. Project creation experience

The effective R35 five stages are approved:

1. Project Details
2. Parties and Access
3. Buildings
4. Attachments — optional
5. Review and Create

Draft input autosaves per user/device. Creation itself requires connectivity and
one server transaction that creates the project, Common scope, physical
buildings, initial membership history and one **Workshop Materials** BOQ group
for **each** real scope.

No weighted project-completeness percentage participates in V1 readiness or
workflow. Existing progress data remains historical and isolated.

## 6. BOQ groups, columns and rows

- Every Common/building scope starts with one independent **Workshop
  Materials** BOQ group. Its stable template identity remains
  `workshop_materials`, but an authorized user may rename its visible folder
  name independently in that scope or archive/restore that folder without
  changing its retained worksheet and downstream history.
- **AC Units** is no longer a default or protected folder. It is not seeded for
  a new scope. Any retained scope-local folder with the stable `ac_units`
  template identity may be renamed, archived and restored like an ordinary
  folder; it is never bulk-deleted by migration.
- Folder structure is scope-local. Creating, renaming, archiving or restoring a
  custom folder affects only the selected Common/building scope. Another
  building may deliberately use a different folder set or different names, and
  future scopes receive only their own active default template folders.
- The folder name and worksheet title are separate. The folder name organizes
  one scope; the optional worksheet title describes that one worksheet. Neither
  change moves or copies rows, columns, quantities, imports, exports, documents
  or MR sources.
- The historical 8 August 2026 project-wide creation rule may have already
  produced same-name empty sibling groups. Those records remain valid,
  independent scope folders and are never merged or physically removed by the
  scope-local correction.
- Folder structure changes require the enforced, project-scoped
  `boq.manage_folders` capability plus existing project access. They are
  online, version-checked, idempotent and audited. Procurement and Accountant
  cannot mutate BOQ folder structure.
- A folder is archived/restored rather than physically deleted. This includes
  custom folders and the approved `workshop_materials` and `ac_units` template
  identities. A whole
  operational BOQ is never hard-deleted: a completed project is archived, or a
  later explicitly approved BOQ supersession retains the former structure and
  downstream history.
- Overview shows per-scope folder, started-folder and material
  counts. It does not merge rows, permit worksheet mutation or serve as an MR
  source.
- Columns and rows are ordered records with optimistic versions.
- Imported arbitrary columns are preserved in raw JSON and remain editable in
  that worksheet.
- Canonical mappings exist separately for description, brand/origin, quantity,
  unit, planning model/tag and other searchable/transfer fields.
- S:No is derived from row order and is not a durable business identifier.
- Blank Row and Similar Row insert immediately below the active row.
- Deleting a populated column requires confirmation and preserves its legacy
  values in revision/audit history; it does not silently discard them.
- Saving or importing a reviewed worksheet is an atomic active-snapshot
  replacement. Archived row/column order values never block a later import,
  revised IDs and reordered coordinates are accepted, malformed duplicate
  IDs/orders/headings/mappings fail before commit, and an idempotent retry does
  not create another revision.
- BOQ import and editing never submit an MR.

Planning model/equipment tag is separate from manufacturer serial number.
Manufacturer serial is captured only at receipt/asset registration when known.
Legacy `modelSerial` values are retained with provenance until reconciled; they
are not guessed into either field.

The approved default group set is frozen to one folder:

1. Workshop Materials

The former 29 templates remain preserved as inactive historical definitions.
Existing folders carrying any row, column, controlled document or Material
Request source remain visible; empty legacy shells are not shown in normal BOQ
navigation and are never physically deleted by this rollout.

## 7. Material Request creation and submission

An MR draft belongs to one project and one Building/Common scope. It may contain
rows from:

- a whole BOQ group;
- selected BOQ rows;
- an MR Excel import;
- custom rows.

BOQ selection copies a snapshot into the draft only when the source group's
scope equals the selected MR scope. Later BOQ edits do not rewrite the request.
Changing an MR scope warns before removing incompatible BOQ-derived rows;
custom and Excel rows remain. The trusted save and submit commands enforce the
same-scope invariant regardless of client state.

Timing values are `urgent`, `normal` and `scheduled`. Scheduled requires a
scheduled date. Destination is derived from the selected project scope and its
delivery information; an optional delivery note may refine floor/area/zone.
Urgent/Normal do not invent a scheduled date.

Drafts are visible only to their creator and authorized Admin support. Explicit
Submit requires connectivity and atomically:

- validates active project membership and scope;
- snapshots requester name and project role;
- assigns a server number;
- freezes submitted line snapshots;
- moves the MR to `awaiting_request_approval`;
- creates current-owner and audit/notification records.

Until approval, the creator and an assigned/global Project Engineer may update
the current Engineering intent through a version-checked audited command.
Procurement cannot read or arrange the new request until Engineering approval.
The 24 September 2026 approved exception allows an eligible approver to turn
on post-approval editing for that request only, before Procurement starts any
arrangement. It is off by default. An approver may name one active Procurement
editor or limit editing to approvers, and may revoke the grant. Saving an edit
creates a new version awaiting Engineering approval; Procurement never approves
its own proposal and cannot arrange while reapproval is pending. The server
enforces the cutoff, actor, capability, named grant and version under lock.
Retained line IDs, protected commercial relations and all prior decision and
revision evidence are preserved. No existing request is automatically enabled.
The server-backed `draft` remains private to its creator and authorized Admin
support, including discussion. Assigned/global Engineering participants become
readers and may participate only after explicit submission; mentions identify
a protected user ID and create a notification only when that user is also
allowed to read the request.

Custom-row item description supports one non-commercial ranked material
search. Results are ordered from the selected Building/Common BOQ scope, then
the remaining real scopes in the same project BOQ, then the inventory
catalogue. A selected same-scope BOQ result retains its exact group/row source;
a result from another project scope or inventory is copied as descriptive
custom input because an MR may never claim a cross-scope BOQ source. Item
description, brand/origin, size, model/tag and unit may be copied while
quantity remains deliberate user input. No match leaves free-text entry fully
available. The response contains no cost, balance, reservation, minimum-stock,
location or other protected inventory facts.

The same ranked, non-commercial discovery is available while editing a BOQ
description cell. Desktop keeps suggestions inside the active spreadsheet
cell; mobile uses the focused row editor. The current row is excluded from its
own results. Selecting a suggestion copies only mapped description,
brand/origin, size, model/tag and unit values in one local worksheet revision;
quantity and commercial fields remain deliberate input. Searches are
debounced and stale responses are discarded, while unmatched free text remains
valid.

Procurement arrangement shows the immutable request-line BOQ correlation and
uses it to rank warehouse candidates, but never auto-selects a stock item.
Availability, reservation and quantity rules remain authoritative only in the
connected arrangement command; they are not prerequisites for Engineering to
raise a request.

## 8. Canonical MR lifecycle

Machine states:

`draft -> awaiting_request_approval -> approved_for_arrangement -> arranging -> approved -> partially_dispatched -> dispatched -> partially_received -> received -> closed`

Alternative transitions:

- `awaiting_request_approval -> draft` with an immutable `returned` request
  decision and required reason; the request number and submission history stay
  intact and a resubmission returns to request approval
- eligible pre-dispatch records -> `cancelled`
- approved but undispatched records -> `cancelled` with reason and reservation
  release

`deleted` is not a workflow state. A draft may be physically removed if it has
never been submitted. Submitted records follow controlled deletion/cancellation
rules and preserve lines/history.

The first transition to `arranging` occurs only after a current immutable
request-approval decision and when Procurement explicitly starts the first
arrangement version. It is server-recorded, not inferred from opening a screen.
Existing requests already in `arranging` or `awaiting_approval` retain their
recorded legacy post-arrangement approval path until resolved; no synthetic
pre-approval is created.

`closed` is explicit and allowed when all approved quantities are resolved, no
dispatch/receipt is open, and any unavailable-at-zero lines remain preserved.
Unavailable original requested quantity does not fabricate an outstanding
approved quantity. An actively assigned Project Engineer or Site Engineer,
either organization-wide Project Engineer role, or Admin may close. Procurement
may not close its own fulfilled workflow.

## 9. Arrangement and reservation

Every request line has exactly one current arrangement decision:

- `full`: arranged quantity equals requested quantity;
- `partial`: arranged quantity is greater than zero and below requested, with a
  required reason;
- `unavailable`: arranged quantity is zero, with a required reason.

Warehouse is the default source. A line may instead use an external supplier
source. The supplier name is optional operational context because V1 has no
full supplier/RFQ/PO lifecycle. Selecting External Supplier is sufficient for
a Full line; Partial and Cannot Provide Now still require their decision reason.

Saving a complete arrangement version atomically:

- validates every line and current request version;
- locks affected inventory rows;
- replaces the prior active version and reservations;
- prevents aggregate warehouse reservations exceeding availability;
- snapshots arranged quantities as approved quantities for the already
  approved Engineering request;
- moves positive supply to dispatch-ready `approved`; or, when every line is
  unavailable, retains the current arrangement as editable Procurement work in
  `arranging` with zero approved quantity.

An all-unavailable arrangement never silently completes or cancels the
request. Procurement may revise and save the current work when supply becomes
possible. A valid Project Engineer/global Engineering approver or Admin may
explicitly cancel it with a reason; cancellation is terminal for Procurement
editing and preserves the unavailable decisions and audit history.

One `inventory_reservations` table owns the commitment. Presentation values
such as “allocated” are derived from approved reservation status; there is no
second unmodeled allocation authority.

Reservation states are `active`, `partially_consumed`, `consumed` and
`released`. Dispatch consumes the corresponding quantity. Replacement of an
arrangement, cancellation, closure or explicit audited override releases the
remainder. Returning an arrangement for changes keeps the current reservation
until Procurement saves its replacement or the MR is cancelled, preventing
another request from taking the stock mid-review.

## 10. Approval

Only an active assigned Project Engineer, organization-wide Senior Mechanical
Engineer/Project Manager, or authorized Admin override can approve/return the
current request version before Procurement arrangement. Procurement
self-approval is rejected even if the user has another editable client-side
label. Approval freezes the exact Engineering version and actor role; it does
not reserve stock or create commercial facts.

Temporary adoption policy: a request creator whose exact role is not Site
Engineer may approve their own submitted request when they independently hold
the required Project Engineer/global Engineering/Admin authority. A Site
Engineer creator cannot self-approve. Admin may publish
`requests.allow_authorized_creator_self_approval = false` to require an
independent authorized approver. The trusted decision command reads only the
published value, so a configuration draft cannot change workflow behavior and
historical decisions are never rewritten.

For a new creation-form Draft only, the UI presents **Submit** to every
authorized creator and additionally presents **Approve** only to an exact
Project Engineer, global Engineering role or Admin when the published policy
and effective `material_requests.approve` capability permit it. **Approve** is
one trusted idempotent transaction that saves the draft, records the canonical
submission, and records the immutable approved decision; it never chains two
client calls. If any state, role, membership, policy, capability, version or
quantity validation fails, the transaction rolls back without exposing a
submitted request. An exact Site Engineer never receives that affordance or
authority, including when a historical `project_engineer` membership row
exists. Returned-request edits remain a separate submit/review path.

External supplier identity remains optional during the adoption period. This
is a deliberate temporary policy, not proof of supplier readiness. Procurement
may record a lightweight confirmation, expected date and commitment reference
on each positive external line. Admin may later publish
`procurement.require_external_source_readiness = true`; the trusted arrangement
save then rejects any positive external line without confirmation. Supplier
name remains optional and the control does not introduce an RFQ, quotation or
Purchase Order workflow.

A cancelled request whose latest saved arrangement records every line as
unavailable may be copied once into a new private Engineering Draft by an
otherwise authorized MR creator. The replacement keeps exact request- and
line-level source links, while the cancelled source remains terminal and
unchanged. Procurement cannot create the replacement. It must be explicitly
reviewed and submitted through the familiar MR flow; it is never an automatic
resubmission.

The pre-revision `awaiting_approval` state remains a compatibility lane only
for arrangements already saved before this change. Those exact legacy records
may still be approved/returned using their historical command and are never
silently relabeled as pre-approved requests.

## 11. Inventory and dispatch

V1 has one logical warehouse. Inventory uses decimal quantities and append-only
movements. On-hand is changed only by trusted stock commands.

The approved R38.3 warehouse refinement keeps a normalized category master and
accepted source-text aliases. Seeded category names, including SED and RED, are
literal business labels and are never expanded by inference. Imports never
overwrite a balance: Opening Balance, Add Stock and Remove Stock append a
server movement, while No Stock Change may update verified item master data
without fabricating a movement. Minimum stock is an operational attention
threshold only; it is not a valuation, reorder or purchase-order workflow.
Close category matches are advisory until an authorized user confirms an
existing category or explicitly creates a new one.

During the current catalogue-reconciliation period, Procurement may also save
an inventory item without a category. The item remains truthfully
uncategorized; the client and server do not invent a fallback category or
alias. Making category selection mandatory later is a separate product and
migration decision. When a category is supplied, the same trusted resolver,
parent-category creation and duplicate protections remain mandatory.

Dispatch is one server transaction that:

- validates Procurement/Admin authority, current state and idempotency key;
- locks request, reservation and inventory rows;
- caps each line by approved minus good-received minus in-transit quantity;
- caps warehouse lines by stock available at commit;
- consumes reservations and decrements on-hand exactly once;
- creates dispatch/line snapshots, movement and audit records;
- sets the appropriate partial/full dispatch state.

An external-source dispatch does not mutate warehouse stock but remains subject
to the approved quantity cap.

## 12. Receipt review and Delivery Order

Each dispatch line is reviewed with one UI outcome:

- Received — good quantity equals dispatched quantity;
- Missing — reviewer enters good quantity, and the remainder is missing;
- Damaged — reviewer enters good quantity, and the remainder is damaged.

This permits partial good receipt without inventing a fourth visible status.
One line cannot be both Missing and Damaged in the same review; Procurement may
split a dispatch line when those outcomes must be recorded separately.

The review must reconcile to the dispatched quantity. Only good quantity
increments `good_received_qty`. Missing/damaged quantity remains replacement
eligible within the approved cap.

After confirmation, an authorized receiving Engineer may attach JPEG or PNG
site photographs to the immutable receipt-review entity. The existing
prepare/upload/finalize document transaction and entity authorization are used;
the receipt command itself never claims upload success.

A Delivery Order snapshot may be created as soon as its dispatch is committed.
An assigned Project/Site Engineer, either organization-wide Project Engineer
role, Procurement or Admin may generate it. This document-only command does not
permit an Engineer to dispatch stock, arrange a request or confirm a material
return. Cardinality is one current DO revision per dispatch; regeneration
creates an immutable new revision and supersedes, never overwrites, the prior
snapshot. A dispatch revision uses immutable dispatched quantities and the
approved four columns: S.No, Description, Qty and Unit.

The Description cell also renders the Size and, when present, Model/Planning
Model Tag captured on the submitted Material Request line. These values are
frozen into each Delivery Report revision; preview, Excel, PDF and print must
not resolve them from a later mutable inventory record. Size remains explicitly
labelled even when a legacy request did not capture a value.

When a receipt review is confirmed, the server appends a distinct immutable
`receipt_review` Delivery Report revision when a Delivery Order already exists.
The current printable report then shows each confirmed good quantity, including
zero for a fully missing or damaged line, while the earlier `dispatch` revision
continues to prove what Procurement committed. If no Delivery Order existed at
receipt time, generating one afterwards creates that receipt-reviewed revision.
Material Returns remain later, separate inventory facts: they do not rewrite
either dispatch or receipt evidence.

Controlled MR and DO documents use `YORKS Airconditioning & Refrigeration
LLC-SPC` and `يوركس للتكييف والتبريد - ذ.م.م - ش.ش.و`, show the approved Abu
Dhabi telephone/fax/P.O. Box and `yorks_sk@yorks.ae`, include the building
number on the DO, and render the project name as `<job/contract ref>-<project
name>` when the project has a job/contract reference.

## 13. Material Returns

Return lifecycle:

`draft -> awaiting_approval -> approved -> dispatched -> confirmed`

`awaiting_approval -> returned_for_changes -> awaiting_approval`

`awaiting_approval -> rejected` and any pre-dispatch active state may become
`cancelled` with a reason.

- A return belongs to one project and one real scope, not to one Material
  Request. It remains available during project close-out and may combine
  traceable delivered lines from multiple requests with explicitly marked
  historical/custom lines.
- Eligible delivered quantity is good received minus prior approved,
  dispatched or confirmed returns. Draft selection never reserves or changes
  stock; the server rechecks eligibility under source-line locks on submit and
  confirmation.
- Submission assigns the controlled return number and freezes project, scope,
  source request/dispatch/receipt links, custom provenance and line snapshots.
- Assigned Project Engineers, organization-wide engineering approvers and
  Admin approve, return for changes or reject. Procurement cannot approve the
  return it will receive.
- Dispatch records the physical handover date, driver, optional vehicle and
  mandatory delivery-note reference before warehouse receipt can be confirmed.
- Only Procurement/Admin can confirm physical warehouse receipt. Good,
  damaged and not-received quantities must reconcile exactly to each returned
  line; only good quantity increments warehouse stock.
- A custom or otherwise unmapped line must be mapped to an existing inventory
  item or a new Procurement/Admin-created item before good stock is posted. No
  stock is posted to an unidentified item.
- Confirmation is atomic and idempotent, appends one movement per good line,
  retains exception quantities and emits audit/notification evidence once.
- Rejection, return for changes and cancellation require reasons and never
  change stock. Confirmed history is immutable.

## 14. Documents and links

Documents are immutable versions with object path, hash, mime type, size,
revision, uploader and timestamps. A current version supersedes but does not
delete its predecessor.

A document may have multiple links. Normal links belong to one project.
Cross-project links require Admin and a reason. A reader must be authorized for
every current link, then pass the document classification:

- `operational` follows linked-entity access;
- `commercial` additionally requires `view_commercials`;
- `admin_restricted` requires Admin.

Knowledge of a Storage path never grants access. Link creation/removal is
audited and cannot broaden a document beyond its classification.

PDF and print use one domain template. Generated MR, DO and Return snapshots are
stored with source record/version references.

## 15. Numbering and idempotency

- UUIDs are internal primary keys.
- Project reference remains an Admin-controlled unique value.
- MR, dispatch and return human numbers are allocated server-side from a
  per-project locked counter on first committed transition.
- A retry with the same actor, command type and idempotency key returns the
  original result.
- A different payload with a reused key is rejected.

Sequences start at `001`, are never reused and use:

- `{PROJECT_REF}-MR{NNN}`
- `{PROJECT_REF}-DSP{NNN}`
- `{PROJECT_REF}-RTN{NNN}`

The Delivery Order reference is entered by an authorized user, normalized and
globally unique. Historical references are never renumbered; collisions are
reported and retained through a migration alias/exception.

## 16. Deletion, correction and audit

- Creator may hard-delete an unsubmitted local/server draft with no links.
- Assigned Project Engineer/Admin may cancel or delete a submitted pre-approval
  MR only when no dispatch exists; server audit/history is retained.
- Approved undispatched MRs soft-cancel with a reason and release reservations.
- Dispatched, received, return-confirmed, generated-document and audit records
  are never application-hard-deleted.
- Corrections create append-only correcting events or new versions.
- Critical actor, role and timestamp are derived on the server.

## 17. Offline behavior

Project/MR/return drafts and BOQ draft edits may recover locally. Committed
project creation, MR submission, arrangement, approval, inventory adjustment,
dispatch, receipt confirmation, DO generation, return submission/confirmation
and user administration require server confirmation.

The UI shows Offline, Saving, Synced, Conflict and Failed states explicitly.
Critical actions never show success before the server commits.

## 18. Deferred and retained behavior

- The legacy Finance navigation/model remains preserved behind a disabled
  non-authoritative boundary. It cannot create or mutate normalized Accounts
  records. R39 Accounts is a separate phased, default-off normalized feature
  governed by section 23.
- Full RFQ, quotation comparison, PO and supplier portal remain deferred.
  R38.9 separately approves controlled supplier receipt provenance inside the
  Warehouse Inventory workspace; it does not authorize purchasing workflow,
  multi-warehouse behavior or accounting valuation.
- Rentals, User Management, Audit Trail, Duct Sizer and ESP Calculator remain
  and receive smoke/regression fixes only. Configuration follows the explicit
  server-authoritative control-plane contract in section 21.
- Multi-warehouse, portals, barcode/QR, AI and complex BI are deferred.

## 19. R38.9 supplier identity and receipt import

- Supplier folders are Procurement/Admin-only and remain nested under
  Warehouse Inventory. Engineering inventory-read capability does not expose
  suppliers, documents, receipt/commercial fields or supplier exports.
- A blank, whitespace-only, `Unknown` or `N/A` supplier maps to one immutable
  system `Unknown Supplier` identity. The original raw value and
  `unknown_missing` resolution are retained.
- Missing supplier is a visible warning, not a blocker. External Supplier rows
  still require a Delivery Note/reference and Received Date. Opening Balance
  rows may omit those fields and retain Opening Balance provenance.
- Manufacturer Serial No is optional evidence and is never generated by Yorks.
  Blank values and conventional absence markers (`N/A`, `NA`, `Unknown`,
  `None`, `Nil` or a dash) normalize to no serial/bulk tracking while the raw
  workbook cell remains in import evidence. Each genuine manufacturer serial
  requires its own quantity-one row; duplicate genuine serials remain blocking.
- Supplier aliases only auto-resolve on an exact approved normalized alias.
  Similar names require an explicit Procurement/Admin decision.
- Import stages before final confirmation are quantity-neutral. The trusted
  commit is strict, idempotent, append-only and authoritative for supplier,
  receipt, movement, balance and audit effects.
- Delivered quantity equals Accepted + Damaged + Rejected. Only Accepted enters
  usable On Hand; Damaged is quarantined and Rejected does not enter stock.
- The two supplied master workbooks are reconciliation alternatives, not two
  stock sources. Neither may be committed to production before signed cutoff,
  staging rehearsal and source/commit/quarantine reconciliation.

## 20. Material Request Phase 2 collaboration and scale

- Material Request registers use an authorized server summary projection with
  server-side search, filter, sort and paging. The initial request page contains
  15 rows. A summary never embeds request lines, comments, commercial values or
  another user's private draft; full detail is fetched only after the user opens
  one request.
- The discussion projection returns the newest 20 comments. Older comments use
  a stable server cursor and are loaded explicitly without reloading or
  duplicating the newest page.
- **Claim** and **Reassign** are version-checked responsibility markers for
  coordination. They never approve, arrange, dispatch, cancel, change state or
  replace the canonical workflow owner/next-action calculation. Reassignment
  requires a reason and notifies the new assignee.
- Private draft sync is owner-only recovery across the same user's devices. It
  coexists with the local draft for offline recovery, shows **Saved to your
  account** only after server confirmation, and never makes an unsubmitted
  request visible to another participant or Procurement.
- Returned requests expose a concise server-derived change summary from the
  immutable Engineering revision snapshots. It highlights item additions,
  removals, quantity changes, detail changes and delivery-note changes without
  rewriting the decision or audit history.
- Phase 2 preserves the temporary adoption policies: an independently
  authorized non-Site-Engineer creator may self-approve; supplier readiness is
  non-blocking; and an all-unavailable request stays Procurement-editable until
  explicit authorized cancellation makes it terminal.

## 21. Configuration control-plane truth

Configuration is an exact-Admin, server-authoritative control plane. A value is
shown in one of three explicit modes so the screen never promises behavior that
the application does not enforce:

- **Operational** values have a named runtime consumer, may be staged by an
  exact Admin, remain inert as a draft, and affect only future commands after a
  validated publication succeeds.
- **Protected** values describe a Yorks V1 security, legal, document, audit or
  numbering invariant. They are visible with their enforcement target but are
  not editable through Configuration.
- **Planned** values are retained for future modules or integrations. They are
  visible for roadmap clarity but cannot be staged or published until an
  authoritative runtime consumer and permission tests exist.

The operational policy set is intentionally narrow and real:

- `requests.default_timing` supplies the initial timing for a new pristine MR
  draft; it never rewrites a recovered or server-backed draft.
- `requests.urgent_enabled` controls whether future MRs may select or commit
  Urgent timing. Existing urgent records remain readable and unchanged.
- `requests.allow_authorized_creator_self_approval` controls the temporary
  adoption policy defined in section 20 and is rechecked by the trusted
  approval command.
- `procurement.require_external_source_readiness` controls whether future
  external-source arrangements require supplier readiness before save.
- `notifications.push_enabled` controls future push-outbox enqueue only.
  Durable in-app notifications and existing outbox evidence are retained.

Categories and units remain audited master-data actions. Their changes stage in
the same shared draft and become active only through publication. Publication
uses an optimistic draft revision, a device-persistent idempotency key, a
mandatory reason, server-side validation, immutable before/after history and
exact actor/role attribution. Protected/planned legacy draft values must be
explicitly cleared or discarded; they are never silently published.

Non-Admin roles may read only the narrow published runtime projection required
by their workflow. They cannot read the Admin draft, publication detail,
protected settings or operational delivery-health diagnostics.

## 22. Scoped capability management

Yorks uses a hybrid authorization model: the exact server-controlled role is
the user's job identity and default permission template, while protected
person-specific `allow` and `deny` assignments may refine named capabilities at
organization or project scope. This provides flexible access without replacing
roles or turning the Flutter UI into an authority.

The initial deployment is compatibility-only. Seeded role defaults must
reproduce the access in force immediately before migration, including existing
commercial overrides. Existing workflow RPC/RLS checks remain authoritative
while the new resolver runs in shadow mode. No protected consumer may cut over
until the active-user parity report has zero unexplained differences and that
consumer has positive, negative, direct-table, stale-claim, project-scope and
separation-of-duties tests.

Effective access is resolved server-side from active identity, non-delegable
invariants, the most specific explicit deny/grant, role baseline, project
membership/global Engineering authority, then record state and command
preconditions. A grant never bypasses quantity caps, workflow state,
separation of duties, commercial response shaping, document classification or
immutable audit.

Only capabilities with a real protected consumer and completed permission
tests are assignable. Planned modules are visible, if needed, only as disabled
roadmap facts. Audit mutation, secret access, RLS bypass, direct counter edits,
fabricated workflow history and delegation-ceiling changes are never grantable.

Permission administration preserves the current exact Admin and Senior
Mechanical Engineer baseline. An administrator cannot change their own
effective permissions, grant beyond their own delegation ceiling, or remove /
expire the last active permission administrator. Each change is versioned,
idempotent, reasoned and append-only audited. The complete data, UI, Realtime,
rollout and rollback contract is
[`SCOPED_CAPABILITY_MANAGEMENT.md`](SCOPED_CAPABILITY_MANAGEMENT.md).

Exact Auth role is singular. Flexible access is represented only by protected
person capability assignments, never by caller-supplied secondary roles or
legacy JWT capability arrays. The four capabilities required to retain a
permission administrator (`users.view`, `permissions.view`,
`permissions.manage`, `permissions.delegate`) are immediate and open-ended;
ordinary capabilities may still use reviewed validity windows.

## 23. R39 Accounts project commercial control

Product-owner approval on 25 August 2026 supersedes only the earlier decision
to keep Accounts unavailable. Accounts is project commercial control, not a
general accounting ERP. It may read trusted operational facts through narrow
authorized projections but cannot rewrite Projects, BOQ, Material Requests,
Procurement, Inventory, Dispatch, Receipt, Delivery Orders, Returns or
technical membership (FR-002 and FR-003).

The feature flag is exactly `YORKS_V1_ACCOUNTS`, defaults off and fails closed.
T01 adds only the exact Accountant role, protected capability/default rows,
additive/shadow schema/RLS and negative tests. T02–T07 cut over baseline,
progress, receivables, supplier bills, routes/UI and shared evidence surfaces
one tested consumer at a time. No normalized Accounts deep link or action is
reachable during T01. Legacy `/admin/finance` is not an authority or fallback
(FR-014).

The exact Accounts capability keys are:

- `view_project_accounts`
- `view_project_commercial_values`
- `suggest_billing_progress`
- `confirm_billing_progress`
- `prepare_client_claim`
- `manage_client_invoices`
- `record_client_certification`
- `record_client_payment`
- `manage_pdc`
- `manage_supplier_bills`
- `approve_supplier_bill_payment`
- `configure_project_commercials`
- `view_supplier_costs`
- `export_accounts_registers`
- `review_commercial_progress`

The server returns these capabilities and record-specific command flags.
Flutter, profile titles and visible routes are never authorization. Project
Engineer may confirm defensible progress and prepare a claim only when
explicitly authorized; Site Engineer may suggest progress without protected
commercial values; Procurement may manage supplier-bill evidence without
client receivables; Accountant manages authorized receivable/payment controls
without technical mutation; Admin exceptions require a reason and audit; and
Senior Mechanical Engineer/Project Manager review requires
`review_commercial_progress` rather than a title match (FR-018–FR-025).

New project commercial baselines default to 90 payment-term days and a 10-day
reminder lead. Both remain configurable and are snapshotted when an invoice is
submitted. Default stages are Design 10%, Material Supply 50%, Installation
30%, Commissioning & Handover 5% and Energizing 5%. Physical building
allocations total exactly 100% within explicit numeric tolerance;
`Common / All Buildings` is excluded from physical commercial allocation
(FR-029–FR-031). T01 protects the default-stage rows and their 100% total and
freezes the physical-allocation/Common policy. T02 creates the project
physical-building allocation relations and enforces that policy at row and
command boundaries. The complete phased and security contract is
[`R39_ACCOUNTS_FOUNDATION.md`](R39_ACCOUNTS_FOUNDATION.md).

### R39 T03 receivables policy defaults

The following fail-closed rules bind the T03 claim and receivables slice. They
remove policy ambiguity before any normalized Accounts consumer is enabled:

- a client claim is a protected root separate from the invoice it may create;
  its exact lifecycle is `draft -> ready_for_accounts -> invoiced`, with
  `cancelled` as the only releasing terminal state;
- every non-cancelled claim reserves its snapshotted eligible value exactly
  once. A returned claim retains that reservation for correction and
  resubmission. Only pre-submission draft deletion or explicit cancellation
  releases it, without rewriting history;
- preparing a monetary claim requires both `prepare_client_claim` and
  `view_project_commercial_values`. Every claimed line must carry at least one
  nonblank evidence reference before Accounts submission;
- certification is append-only and cumulative. The latest accepted cumulative
  certification snapshot is authoritative, cannot exceed the invoice claim,
  and cannot decrease in T03. A later correction workflow must be separately
  approved rather than silently rewriting a certification fact;
- a submitted invoice cannot be cancelled after certification, payment or PDC
  evidence exists. Returned invoices may be corrected and resubmitted without
  acquiring claim capacity a second time;
- payment references are case-insensitively unique within a project. A payment
  correction is an exact linked reversal of one original fact, never an edit;
- PDC exposure includes only `expected`, `received` and `deposited` instruments.
  `cleared`, `replaced`, `returned`, `bounced` and `cancelled` instruments do
  not contribute. Clearing a PDC requires an explicit bank/payment reference
  and clearance date and atomically records exactly one linked client-payment
  fact; merely receiving or depositing a PDC never records payment.

These rules remain additive and inactive while `YORKS_V1_ACCOUNTS` is off.
Changing them later requires an explicit versioned configuration decision and
a forward migration that preserves all earlier snapshots and audit facts.

### R39 T04 supplier-bill policy defaults

The following fail-closed rules bind the T04 supplier-bill slice:

- the bill lifecycle is `draft -> approved`, with `cancelled` as a terminal
  state; Procurement maintains draft evidence while Accountant/Admin controls
  approval and payment;
- a PO/LPO evidence group requires both its external reference and a current,
  commercial, project-linked controlled document. A reference alone does not
  make the group present;
- accepted delivery is derived only from a confirmed Receipt Review with
  positive good quantity. Client-supplied delivery quantities or references
  are never authoritative;
- a current commercial supplier-invoice document is required before approval
  and has no exception path;
- server match state is `matched` for three evidence groups, `review` for two,
  and `blocked` for fewer than two or any explicit mismatch;
- only exact Admin may approve or pay an unmatched bill, and each exceptional
  command requires its own nonblank audited reason;
- supplier invoice identity is case-insensitively unique by project, supplier
  name and invoice reference. Payment references are independently
  case-insensitively unique by project;
- supplier payments are append-only, may be partial, cannot exceed total
  including VAT and are corrected only through one exact linked reversal;
- cancellation is forbidden while net payment is nonzero. Cancelling an
  approved bill requires payment-approval authority and a reason; and
- supplier projections never expose client claims, certifications, receipts
  or other receivable-side protected values to Procurement.
- operational Accounts defaults do not alter the established action-only User
  Management password-reset/activation hierarchy. Exact-role creation and
  change remain Accounts-aware and fail closed at the Auth trigger boundary.

These rules do not create an RFQ, quotation comparison or full Purchase Order
workflow. T04 is route-less and inactive while `YORKS_V1_ACCOUNTS` is off.

## 24. Workforce Attendance and Timesheets foundation

The approved 30 August 2026 Workforce contract is a Workforce-only extension.
It does not add or rename a platform role, turn a worker into a technical
project member, or replace People/HR and Leave behavior.

The following decisions are frozen for T01:

- a worker is an operational person record and is distinct from a Supabase
  Auth user. `linked_auth_user_id` is optional and unique when present;
- worker numbers are case-insensitively unique. Workers, trades, teams,
  assignments and responsibility scopes are preserved through status and
  effective dates, never hard-deleted;
- one effective primary assignment may exist for a date. A bounded temporary
  assignment may override it for that date without rewriting either history;
- project-scope assignments prove that the selected Building/Common scope
  belongs to the selected project. Project and internal-location assignment
  targets are mutually exclusive;
- responsibility is an explicit, dated organization, worker, team, project,
  project-scope or internal-location relation. It never grants a platform role
  or technical project membership;
- the exact flag is `YORKS_V1_WORKFORCE`. It defaults off and fails closed on
  the protected document dependency;
- the twelve `workforce.*` capability keys are planned, shadow,
  nonassignable metadata in T01. Exact Admin remains the temporary legacy
  authority for protected T01 worker-master RPCs;
- T01 exposes no Workforce route, sidebar entry, attendance action, timesheet
  action or operational capability consumer; and
- legacy employee/attendance JSON remains untouched. T01 performs no copy,
  hydration migration, dual write or inferred identity mapping.

The following decisions are frozen for T02:

- calendar and shift configurations are effective versions with stable codes;
  versions of the same code cannot overlap;
- every calendar has an IANA timezone, integer scheduled/break minutes and
  exactly seven ISO weekdays with at least one regular working day;
- day type remains separate from attendance status. Dated public holidays,
  site closures, Ramadan schedules and other overrides cannot synthesize an
  attendance result;
- shift start/end values are optional supporting data. Cross-midnight work is
  attributed to the shift start date in the linked calendar timezone;
- effective team schedule defaults reference exact retained calendar and
  optional shift versions and cannot overlap; parent date edits cannot strand
  retained links or overrides;
- after any team schedule or dated override references a calendar or shift
  version, its code, timezone, minutes, weekday meanings, shift kind/times and
  effective window are immutable. A display-name correction may not alter
  those resolution facts; semantic change requires a new non-overlapping
  version;
- an already-effective team schedule and a past/current dated override are
  immutable historical facts, including the dated override active state. A
  future unused link or override remains optimistic-version correctable only
  while both its old and proposed start remain in the future;
- every past/current/future boundary is derived from `clock_timestamp()` in
  the exact linked calendar IANA timezone. Database-session timezone and
  session `current_date` never authorize a historical edit or retirement;
- inactive retirement never deletes history. A calendar or shift with only
  expired references may be retired and remains readable, while current or
  future links/active overrides block retirement;
- exact Admin remains temporary audited configuration authority. Capabilities
  stay planned/shadow/nonassignable, the flag stays default-off and no route or
  UI is exposed; and
- T02 creates no daily attendance, time allocation, overtime or timesheet row.

The following decisions are frozen for T03 daily attendance:

- one protected daily attendance fact exists per worker and `work_date`.
  Attendance status is exactly `present`, `absent`, `annual_leave`,
  `sick_leave`, `official_leave`, `unpaid_leave` or `not_entered`; calendar day
  type remains a separate retained fact;
- `regular_minutes` and `overtime_minutes` are non-negative integers. Each is
  bounded by 1,440 and their sum cannot exceed 1,440. `present` requires a
  positive total; every absent, leave and not-entered state requires zero;
- present work may be recorded on a weekly off, public holiday, site closure or
  not-scheduled day only as an explicit attendance fact. T03 does not calculate
  overtime pay, create partial-day absence allocation or infer attendance from
  a schedule;
- the server resolves the worker's temporary-over-primary assignment and the
  exact team calendar, shift and dated/weekday day type for the work date. The
  first saved row retains those semantic values, names, IDs and versions.
  A correction may change only status, minutes and reason; it never rebases the
  retained assignment, responsibility or schedule context;
- creating a day requires an active worker inside employment and assignment
  dates. A versioned correction of an existing row remains possible after the
  worker later becomes inactive, suspended or leaves, but only for an active
  authorized actor and without changing retained context;
- `workforce.view` and `workforce.attendance.maintain` are the only Workforce
  capabilities promoted to operational, enforced and assignable in T03.
  A non-Admin caller requires both effective capability resolution and an
  effective responsibility matching the worker's retained team/project/scope/
  internal-location context. Exact active Admin has audited organization
  authority. Role, email, editable metadata, technical project membership or a
  guessed UUID never grants Workforce attendance access;
- the save payload accepts only worker, date, status, integer minutes and a
  reason. The command is online/server-confirmed, optimistic-versioned,
  idempotent and audited once. Direct authenticated table access and hard
  deletion remain unavailable; and
- T03 adds no route, sidebar, screen, bulk/copy action, allocation, monthly
  period, timesheet lifecycle, notification, report/export, legacy migration,
  feature enablement or deployment. The other ten Workforce capabilities
  remain planned, shadow and nonassignable.

Product-owner resolution on 30 August 2026 denies all future attendance. A new
day and a versioned correction both fail when `work_date` is later than the
calendar-local date derived from `clock_timestamp()` in the exact retained
calendar IANA timezone. A new row uses the server-resolved schedule timezone;
an existing row uses its retained `calendar_timezone_snapshot`. Database
session timezone and client device time never decide this boundary. Any
pre-existing future row is preserved and readable as historical evidence but
is read-only until its work date is no longer future; it is never deleted,
rebased or silently corrected by this rule.

The following decisions are frozen for T04 daily timesheet allocations:

- one attendance day may own one versioned allocation set with multiple
  immutable allocation revisions. An active revision contains at least one
  allocation, and its separate regular-minute and overtime-minute sums must
  equal the parent attendance day exactly;
- allocation targets are explicit and mutually exclusive. Project work names
  one active project and one active Building/Common scope belonging to that
  project. Internal Yorks work names one active internal location and retains
  that location's Department/Cost Centre meaning. The server never infers a
  target from the worker's team or assignment;
- allocation rows retain target identity/display snapshots, optional activity
  and notes, integer regular/overtime minutes, actor/time and revision
  evidence. They contain no pay, salary, cost or commercial value;
- an optional supporting time range must be supplied as a complete pair.
  Start and end form a half-open interval in the retained calendar timezone,
  anchored to the attendance `work_date` as the retained shift-start date. On
  a cross-midnight shift a start earlier than the retained shift start belongs
  to the following local date; an end earlier than that resolved start time
  advances once more. Equal start/end is invalid, adjacent intervals are
  permitted and overlapping intervals are rejected. The interval supports the
  allocation but does not synthesize or replace authoritative integer minutes;
- only a `present` attendance day may carry an active allocation revision.
  Absent, leave and not-entered days carry none. An active allocation set
  blocks every T03 attendance correction so a parent cannot silently make its
  child totals or meaning inconsistent;
- only `workforce.timesheets.maintain` may save or withdraw an allocation set.
  Withdrawal appends a zero-line immutable revision and changes no attendance
  fact. After withdrawal, an attendance maintainer may correct the parent; a
  timesheet maintainer must then save a new active revision against that exact
  attendance version. Timesheet authority never grants attendance authority;
- every save is atomic, worker/date locked, optimistic-versioned, UUID-
  idempotent and audited once. Existing revisions/rows cannot be updated or
  deleted, and every accepted response is the strict authoritative schema-v1
  projection;
- T04 promotes only `workforce.timesheets.maintain` in addition to the two T03
  consumers. Non-Admin access requires an effective capability and dated
  responsibility for the retained worker context plus effective capability
  and explicit dated responsibility over every target. Worker/team
  responsibility alone does not authorize an unrelated target. Exact active
  Admin retains audited organization authority; and
- T04 adds no route, sidebar, screen, roster/bulk action, monthly-period
  lifecycle, review/verification/approval/reopen workflow, notification,
  document, report/export, legacy migration, feature enablement or deployment.

The following decisions are frozen for the T05 Supervisor Daily Roster:

- opening or filtering a roster is read-only. The server projects only workers
  effectively assigned for the selected work date plus authorized retained
  attendance evidence; schedule/day-type values for missing rows are
  suggestions and never create attendance;
- the existing `workforce.view`, `workforce.attendance.maintain` and
  `workforce.timesheets.maintain` capabilities remain the complete T05
  authority vocabulary. T05 promotes no additional key and never derives
  authority from a route, role label, technical project membership or a
  client-supplied selector;
- Review Day is a local validation transition. Save Day is the only server
  mutation and sends one allowlisted, atomic, optimistic-versioned,
  UUID-idempotent roster command. Worker/date locks are deterministic and a
  mixed row set fails without a partial attendance, allocation or audit effect;
- attendance-only authority may preserve a live allocation revision while
  correcting optional overtime evidence, but it cannot see hidden allocation
  identifiers or change locked totals. Replacement or withdrawal always needs
  timesheet authority and the exact visible allocation version;
- bulk actions and Copy Previous Day transform only the local draft. Copy
  recomputes the selected date's assignment/schedule/day type, excludes workers
  no longer assigned, adds newly assigned workers, clears absence/leave,
  overtime, notes and later-phase evidence, retains only a currently authorized
  target, and marks copied rows as needing review before explicit Save;
- the normalized Workforce route, sidebar and search entry exist only while
  `YORKS_V1_WORKFORCE` is enabled and the server permission snapshot confirms
  `workforce.view`. Flag-off, denied, inactive or revoked state fails closed and
  purges protected roster/draft state; and
- T05 is a desktop roster: 1440x900, 1366x768 and 1024x768 use a sticky Worker
  column/header with deliberate local grid scrolling, keyboard traversal and
  visible draft/save states. The 360x800 boundary is deliberately read-only and
  overflow-free; T11/T12 own tablet/mobile editing. T05 adds no monthly period,
  submit/review/approve/lock lifecycle, document, notification, report/export,
  legacy migration, feature enablement or deployment.

The following decisions are frozen for T06 Monthly Period and Validation:

- a monthly period identity is exactly one Workforce `team_id` plus the first
  Gregorian date of one calendar month. Supervisor, project, Building/Common
  scope and internal location are retained worker/date evidence and summary
  dimensions, not alternate period identities. This preserves one controlled
  team month when workers change supervisor or work target mid-month;
- opening a Monthly view never creates a period. Initialization and
  revalidation are explicit online commands. They lock the team/month path,
  use an optimistic period version plus UUID idempotency key, append one
  immutable validation run with retained worker/date summaries and issues,
  advance only the period's current-run pointer/version and emit one audit
  effect. No prior run, summary, date or issue is updated or deleted;
- monthly membership is one canonical retained/prospective union. A worker/date
  with a T03 attendance fact belongs to the exact team and assignment retained
  by that attendance row and uses its retained calendar/day-type context; a
  later mutable T01 assignment edit cannot remove it from the original team or
  make a replacement team absorb it. Only a worker/date with no attendance may
  derive prospective/missing membership from the accepted T01 effective-
  assignment resolver. The two branches are mutually exclusive per worker/date,
  and the current T04 allocation remains attached to its attendance day. Source
  fingerprinting, authority checks, summaries and drill-down all consume this
  same canonical source. Each run retains the exact facts it used, and the
  client cannot add workers, dates or totals;
- one canonical team-month applicability predicate governs the authorized team
  selector, absent-period read and initialization/revalidation. A team/month is
  applicable when its current validity window overlaps the month, retained T03
  attendance names that team for a date in the month, or a monthly period
  already exists. Therefore later mutable team dates cannot hide or reject
  retained history. A non-effective team with no retained attendance and no
  period remains hidden/rejected, and applicability never bypasses the existing
  complete worker/date capability, responsibility or allocation-target checks;
- every date is interpreted in its exact effective calendar IANA timezone.
  Future calendar-local dates may remain visible as future membership but are
  excluded from scheduled/missing totals and never create a missing-entry
  issue. A retained legacy future attendance/allocation fact remains visible
  in its immutable day evidence, but its regular, overtime and allocation
  minutes are excluded from authoritative worker/period totals until that
  calendar-local date arrives; the changed future fingerprint then requires
  explicit revalidation. A missing calendar is a blocking configuration issue and is never
  resolved from the database-session or client timezone;
- the only T06 period states are `draft` and server-derived
  `ready_for_review`. Any blocking issue or a source fingerprint that changed
  after the current run makes the effective projection `draft`. Warnings stay
  explicit but T06 has no acknowledgement or submission transition; T07 owns
  both acknowledgement and lifecycle commands;
- later mutable parent state never rewrites a retained T03/T04 fact. A retained
  attendance row uses its active-at-creation worker/employment/assignment/
  supervisor identity and a retained allocation uses its commit-time project,
  Building/Common or internal-location snapshots. A later `left_company`,
  inactive/suspended worker status or project/scope/location closure does not
  create a retroactive blocker for that accepted row. Prospective dates with no
  retained attendance still use current worker state; because inactive and
  suspended statuses have no dated history in T01, they remain fail-closed as
  current-unresolved validation evidence rather than being asserted as a past
  fact. A `left_company` worker remains applicable through the exact leaving
  date when the assignment window also covers that date;
- a missing supervisor ID is structurally invalid for both retained and
  prospective applicable dates. For prospective dates, a non-null supervisor
  must also be currently active. T03 did not retain dated supervisor-active
  state, so later supervisor deactivation is not backdated into a different
  historical identity; the retained ID/name remain the evidence and the
  absence of a retained supervisor is the only historical status fact T06 can
  prove without invention;
- blocking issue codes cover applicable missing/not-entered required dates,
  invalid attendance/minutes, absent/leave work contradictions, allocation
  reconciliation/overlap, over-1,440-minute days, invalid employment/worker/
  assignment/supervisor/target context. A caller's own authority loss denies
  the RPC before any partial projection or validation run; it is not persisted
  as an issue. `validation_stale` is projected deterministically when the
  immutable run fingerprint differs from current source, rather than inserted
  into retained history. Warnings cover weekly-off/holiday/site-closure work, below-
  standard minutes, assignment/supervisor changes, missing activity,
  off-assignment allocation and backdated evidence;
- accepted T03/T04 constraints remain authoritative. T06 rechecks and reports
  their applicable facts but never repairs, rebases or duplicates them.
  Overtime minutes and the optional T05 reason are retained and summarized;
  because no overtime ceiling or mandatory-reason policy is configured, T06
  creates no fabricated threshold or missing-reason issue. Optional documents
  likewise create no validation requirement;
- `workforce.view` authorizes a complete period read only when exact active
  Admin authority or dated responsibility covers every retained worker/date in
  the team month. Initialization/revalidation additionally requires
  `workforce.timesheets.maintain` over every worker/date and every active
  allocation target. Partial or redacted monthly totals are never presented as
  authoritative. No T07 review/verify/approve/reopen key is promoted; and
- T06 adds the guarded desktop Monthly view inside the existing Workforce
  shell. It has no Submit button. Desktop viewports show server-derived period,
  worker/calendar and exception detail; 360x800 remains deliberately read-only
  and overflow-free. The flag remains default-off and T06 adds no legacy
  migration, notification, document, report/export, tablet/mobile editor,
  commit, push, remote migration or deployment.

Later phases must introduce the remaining attendance/timesheet lifecycle, review,
verification, final approval, reopening, reports and tablet/mobile editing as
separate tested slices. No later slice may infer attendance or approved time
from an assignment, calendar, shift, project membership, Auth session or
legacy record.

The following decisions are frozen for T07 Review and Approval Lifecycle:

- the configurable approval chain is the existing exact capability assignment
  plus dated Workforce responsibility model. A maintainer needs
  `workforce.timesheets.maintain`; a reviewer needs
  `workforce.timesheets.review`; reviewer correction additionally needs
  `workforce.timesheets.correct_during_review`; Verify & Forward additionally
  needs `workforce.timesheets.verify`; final approval needs
  `workforce.timesheets.final_approve`; and reopen authorization needs
  `workforce.periods.reopen`. Every command rechecks complete retained worker,
  date and allocation-target scope. Exact role, email and technical project
  membership are never approval authority;
- submission accepts only the current non-stale `ready_for_review` T06 run with
  zero blocking issues. The submitter must acknowledge the exact complete set
  of retained warning issue IDs when warnings exist. Submit records the
  authoritative validation run, source fingerprint, totals, actor, exact role,
  capability, acknowledgement and one approval revision. Opening a review
  projection creates no state;
- the default separation is mandatory: the submitter cannot review, correct,
  verify or finally approve that revision; any actor who returns the revision,
  applies a reviewer correction or performs Verify & Forward cannot finally
  approve that same revision. No Admin or role-label exception exists in T07.
  Return and Verify & Forward are reviewer actions; Approve & Lock is one
  atomic final-authority command that emits
  distinct approved and locked audit evidence and leaves the period `locked`;
- current lifecycle states are `draft`, `ready_for_review`, `submitted`,
  `under_review`, `returned_for_correction`, `awaiting_final_approval`,
  `locked` and `reopened`. `under_review` begins only through an explicit
  reviewer correction; read never changes state. `verified` and `approved` are
  immutable transition/snapshot facts inside Verify & Forward and Approve &
  Lock rather than transient client-writable states. `cancelled` has no T07
  command and remains reserved for a later explicit decision;
- Return requires a non-empty reason and exact worker/date pairs. Only those
  pairs are editable after return; unaffected period evidence remains
  protected. Resubmission reuses the same approval revision after explicit T06
  revalidation and warning acknowledgement. The optional T08 attachment seam
  is a nullable external reference only and creates no document in T07;
- controlled reviewer correction accepts only the existing T03 attendance
  fields and/or one complete T04 allocation replacement for one affected
  worker/date. It requires the correction capability, mandatory reason,
  expected T03/T04 versions and independent UUID command keys. The trusted T03
  and T04 commands remain the only writers and recheck their minute, status,
  target, interval, future-date and scope invariants. An immutable correction
  record retains before/after values and the row is visibly marked; there is
  no silent rewrite or inheritance of ordinary maintainer capability;
- ordinary T03/T04 writes are lifecycle-guarded. Submitted/under-review,
  awaiting-final-approval and locked facts cannot be changed through ordinary
  save RPCs. Returned/reopened periods expose only their exact affected
  worker/date pairs. A reviewer-only command can open a transaction-scoped,
  server-created correction context; a client-created session variable is not
  trusted;
- an approved snapshot is immutable and server-derived from the accepted T06
  run plus current authoritative T03/T04 facts. It retains worker/team/
  supervisor/project/scope/location identities, daily attendance, regular and
  overtime minutes, activities, calendar/shift versions, reviewer corrections,
  submitter/reviewer/approver identities and timestamps, source fingerprint and
  report revision. Later master-data edits cannot rewrite its JSON bytes or
  hash;
- Request Reopen is available to a fully scoped maintainer and records reason
  plus exact affected worker/date pairs while leaving the approved period
  locked. A different fully scoped actor with `workforce.periods.reopen`
  authorizes the request, preserves the prior snapshot, advances to a new
  approval revision and exposes only those pairs for correction. The new
  revision must be validated, submitted, reviewed and approved again; a second
  immutable snapshot is appended and the older snapshot remains readable; and
- every mutation locks the period and relevant worker/date roots, validates an
  expected record version, uses request-hash UUID idempotency, writes one
  append-only transition/correction/reopen/snapshot effect and audit evidence,
  and returns a schema-v1 authoritative projection. T07 adds no T08 comment,
  document or notification delivery, T09 report/export, T10 dashboard,
  T11/T12 editor, legacy migration, feature enablement or release activity.

The following decisions are frozen for T08 Discussion, Evidence and
Notifications:

- one Workforce monthly period maps to one retained canonical Team Chat group
  conversation. Its effective participants are recalculated from exact active
  identity, `workforce.view`, the accepted T07 capability and dated
  responsibility rules. A stale static conversation-member row is never read
  or command authority;
- user comments, replies, mentions, attachments, edit/delete and delivery/read
  receipts use the accepted Team Chat lifecycle. Comment text such as
  "Approved" or "Verified" has no workflow meaning. T07 server commands remain
  the only lifecycle writers;
- T07 audit events append one non-editable canonical Chat system event per
  source audit ID. Collaboration delivery failure cannot roll back the
  originating T07 transition, and retry/deduplication must never create a
  second system event;
- Workforce evidence reuses the existing immutable controlled Documents
  prepare/upload/finalize/version pipeline with `operational` classification.
  The exact evidence types are medical certificate, leave document, overtime
  authorization, worker transfer note, site attendance sheet, daily supporting
  photo, monthly timesheet attachment and other Workforce document. Evidence
  is linked only to an authorized Worker, retained Attendance Day or Monthly
  Period; project identity is retained only when the authoritative target has
  exactly one project and is never inferred from a technical membership;
- the canonical evidence target is the sole authorization target. Optional
  Worker/Attendance Day/Monthly Period links must agree with that target and,
  for a period, with its exact current retained validation-run source. A day
  link must resolve the same retained worker/date attendance fact. Mismatches
  fail before idempotency, intent, metadata or Storage authority is created.
  Secondary links improve discovery but cannot grant read/download authority
  without authority for the canonical target;
- evidence authorization reuses the accepted `workforce.view`,
  `workforce.attendance.maintain` and `workforce.timesheets.maintain`
  capability-plus-responsibility rules. T08 promotes no capability and ships
  no browser service credential;
- lifecycle notifications reuse durable `v1_notifications`, the existing push
  outbox and recipient preferences. Recipients are derived from the capability
  required for the next action and complete dated responsibility, never a role
  label, email, guessed UUID or technical project membership;
- daily missing-attendance and monthly-incomplete summaries are explicit,
  idempotent Admin-dispatched digest commands. Daily counts cover the complete
  authorized roster through bounded paging and never stop at 500 workers.
  T08 does not invent a scheduler, cron cadence, escalation time or external
  messaging channel; and
- the existing Monthly/Review desktop view exposes discussion, evidence and
  scoped notifications. The 360x800 boundary is deliberately read-only. The
  feature flag remains default-off and T08 adds no T09 reports/exports, T10
  dashboard, tablet/mobile editor, legacy migration, commit, remote migration
  or deployment.

The following decisions are frozen for T09 Excel and PDF Reports:

- final monthly reports are generated only from an exact immutable T07
  approved snapshot ID, approval revision and snapshot hash. Reopen/new
  approval revisions append new report sources and never replace old ones;
- `workforce.reports.export` is the only capability promoted in T09. Every
  caller, including Admin, must also hold `workforce.view`, both effective at
  the relevant project/organization scope, and complete dated responsibility
  for every worker and retained allocation target returned;
- the server owns report kind, source selection, scope filtering, totals,
  approval identity, timestamps, sanitized row values, idempotency and audit.
  Flutter owns only deterministic XLSX/PDF rendering and file/print actions;
- one immutable artifact payload is the source for both formats. PDF Preview,
  Download and Print share one generated byte buffer. XLSX cells beginning
  with `=`, `+`, `-` or `@` are escaped as text unless the cell is a typed
  server numeric/date value; worker numbers always remain text;
- artifact generation and export issuance are separate audited commands.
  First artifact generation appends exactly one `report_generated` event.
  Preview, download, share or print must first confirm the exact cached
  artifact/format/action through the online idempotent issuance RPC, which
  appends exactly one `workforce_export_generated` event and returns the
  source/payload hashes, actor role, capability, scope and server time. A
  same-key retry returns the same receipt; a changed payload is rejected;
- immutable private artifact authority evidence is retained separately from
  the sanitized export payload so every history read can re-check current
  capabilities and complete dated responsibility. Authority loss hides prior
  artifacts without deleting or rewriting them;
- no report includes wages, salary, payroll, overtime pay, bank fields,
  commercial fields, service credentials or unrelated-module data. Internal
  identifiers may exist as protected server references but are never exported
  as user-visible columns;
- man-days are the server sum of each approved date's total approved work
  minutes divided by that date's retained positive standard scheduled minutes.
  Overtime remains a separate value and no pay meaning is inferred. High
  Overtime has no invented numeric threshold and is populated only from a
  retained configured typed validation exception. When no threshold is
  configured, the High Overtime report contains an explicit typed
  `not_configured` row instead of an empty or misleading result;
- the controlled server column sets are report-specific. Daily separates
  Worker/Number/Trade/Status/Regular/OT/Project/Building/Internal Location/
  Supervisor/Notes; Worker Monthly includes daily work context plus reviewer,
  approver and approval dates; Team, Project and Company summaries expose the
  exact operational counts, hours, allocations, exceptions and lifecycle
  status frozen in the T09 contract. PDF approved-month headers show both
  legal names, `MONTHLY TIMESHEET`, and Month/Year; footers show Prepared By,
  Reviewed By, Approved By, server approval dates, revision and page. Worker
  and Team use landscape; Project and Company orientation is content-based;
  and
- daily/exception reports that are not approved snapshots state their current
  source status/version/generated-at and must never present themselves as an
  approved monthly record. Daily reports reject future calendar-local work
  dates. T09 exception registers are organization-scoped; project/team/worker
  keys are rejected rather than ignored. Worker, Team and Project report scope
  must occur in the immutable approved payload and any requested month must
  equal that payload month; and
- T09 adds no T10 dashboard, T11/T12 editor, legacy migration, feature
  enablement or release.

The following decisions are frozen for T10 Admin and management dashboards:

- T10 is read-only. One protected schema-v1 projection returns an explicit
  Supervisor, Management or Admin shape and performs no audit, notification,
  report/export or lifecycle mutation;
- the authoritative date is derived separately for each exact retained or
  effective calendar IANA timezone from the server clock. Mixed-timezone
  results return explicit as-of groups and never collapse them into a client or
  session date;
- Today Completion counts entered attendance other than `not_entered` over the
  effective roster. Current Month Completion counts entered required
  worker-days through each calendar-local today over required worker-days
  through that date. Future local dates never count as missing;
- daily status counts use the seven accepted T03 statuses. Leave is annual,
  sick, official or unpaid leave. Later current worker/project/scope/location
  state does not reinterpret retained T03/T04 facts;
- management review rows expose exact retained submitter/team/month/workers/
  regular minutes/overtime minutes/warnings/reviewer-corrections evidence.
  Review and approval counts are calculated across the complete authorized
  candidate set before the compact queue is limited. Exception priority is
  applied before recency, so an older higher-priority retained exception is
  not hidden by newer normal rows. A closed team/project/scope/location or a
  later worker departure does not remove its retained queue/history row;
  High Overtime and Missing Supporting Evidence are `not_configured` with zero
  count unless an accepted typed validation issue exists. T10 invents neither
  an overtime threshold nor a mandatory document rule;
- Management current-project rows derive from actual effective assignment and
  active allocation targets, never a team's editable default project. Only
  the Current Active Projects list applies current project state; retained
  review/history remains readable after closure;
- Admin receives aggregate operational counts, not every daily row. Active
  supervisors are distinct active profiles referenced by effective current
  assignments. Configuration issues are current typed assignment, schedule,
  supervisor or allocation-target validation issues, deduplicated by stable
  issue-code plus team identity across current and retained sources;
- every shape requires active identity, `workforce.view` and complete dated
  responsibility. Admin organization scope still requires both the capability
  and organization responsibility. Management-role labels select presentation
  only and grant no data. Action booleans require their exact accepted command
  capability plus full responsibility for every retained assignment and active
  allocation target in the candidate period; and
  and
- cached projections are last-confirmed evidence with visible stale/generated
  timestamps. Flag-off, revoked/inactive identity, denied deep links and
  malformed responses purge protected state. T10 adds no T11, migration of
  legacy data, release, flag enablement, commit, push or deployment.

The following decisions are frozen for T11 tablet attendance and review:

- T11 is presentation-only. It reuses the accepted T05 daily-roster and T07
  review controllers, repositories, RPCs and server-returned action flags. It
  adds no relation, migration, capability, route, lifecycle state or client
  authorization rule;
- the existing compact boundary below 720 logical pixels remains a deliberate
  read-only phone experience. Tablet editing applies from 720 through 1199
  logical pixels; widths of 1200 and above keep the accepted desktop
  spreadsheet/review layout;
- landscape tablets use a bounded master roster plus one selected worker/day
  editor. Portrait tablets use a focused single-column roster and open exactly
  one selected worker/day editor in a modal sheet. Neither orientation renders
  the desktop spreadsheet or instantiates editors for every worker;
- the tablet completion footer is sticky and delegates only to the accepted
  Review Day, Back to Edit and Save Day controller operations. Draft changes
  remain local until explicit online review/save, and offline, stale, conflict,
  uncertain and denied states remain visible and non-optimistic;
- tablet review is exception-first and uses only the T07 server action flags
  for Return, Correct, Verify, Approve and Reopen. A visible button never
  creates authority; and
- English, Arabic, Urdu and Hindi strings remain localized, Arabic/Urdu are
  direction-aware, actionable tablet targets are at least 44 by 44 logical
  pixels, focus order/semantics are explicit and reduced-motion preferences
  suppress nonessential sheet transition motion. T11 adds no T12 phone editor,
  legacy migration, feature enablement, commit, push, remote migration or
  deployment.

The following decisions are frozen for T12 mobile attendance:

- T12 is presentation-only and reuses the accepted T05 projection, controller,
  local-draft transformations and atomic Save Day command. It adds no schema,
  migration, RPC, capability, route, lifecycle state or client authority rule;
- below 720 logical pixels the read-only placeholder is replaced by a native
  Today’s Team workflow. It renders worker cards and exactly one focused editor
  at a time; it never shrinks the desktop grid or constructs an editor for each
  worker;
- row editability, allocation-detail redaction, target options and command
  availability come only from the server projection and accepted controller.
  A readable restricted row remains non-maintainable for that restricted
  allocation and no role name, email or guessed identifier grants access;
- mobile bulk operations are explicit local draft transformations with an
  affected count. The sticky footer delegates only to Review Day, Back to Edit
  and Save Day. No local edit, review or offline draft claims server success;
- native date selection does not offer a future local date as a convenience,
  while the accepted calendar-timezone server rule remains authoritative and
  rejects all future creation/correction/save attempts; and
- T12 proves 360x800 and 390x844, English plus Arabic/Urdu RTL, safe keyboard
  and system insets, text scaling, 44x44 targets, semantics, focus, reduced
  motion, non-color state cues, large-roster bounded editor creation and the
  full loading/empty/denied/stale/conflict/uncertain/invalid/saved state set.
  It preserves tablet/desktop behavior and adds no T13/T14 work, import,
  legacy migration, feature enablement, commit, push, remote migration or
  deployment.

The following decisions are frozen for T13 hardening:

- T13 is an evidence-led audit and correction slice over the independently
  accepted T01–T12 authority. It introduces no new Workforce role,
  capability, workflow, route, data meaning or release state. A schema or
  application correction is permitted only for a reproduced security,
  concurrency, accessibility or performance defect and must preserve retained
  history through a forward-safe change;
- every Workforce relation in an exposed schema keeps RLS enabled, no direct
  `anon` or `authenticated` CRUD, service-role-only direct administration and
  its accepted hard-delete/immutability guards. Every privileged internal
  helper remains unavailable to `public`, `anon` and `authenticated`; each
  public RPC keeps only its intended execute grant, fixed trusted search path,
  live active-identity check, exact capability and dated responsibility/target
  checks;
- T07 lifecycle and T10 dashboard period authorization are role-neutral.
  Admin has no capability-only shortcut. Organization responsibility must
  cover the complete calendar month; a future, expired or partial-month
  organization window cannot fall through as work-date authority. Without
  complete organization authority, every retained assignment and every active
  project-scope/internal-location allocation target requires its own effective
  responsibility. An empty period retains only complete organization or exact
  team-month responsibility semantics;
- all critical mutations retain deterministic root/worker-date lock order,
  expected versions, UUID request-hash idempotency, atomic audit/effect writes
  and stable conflicts. T13 runs the repository's real independent-session
  races and may not relabel a sequential retry as concurrency evidence;
- performance proof uses the approved realistic envelopes: 500 active
  workers, 50 teams, 30 active projects, 31 dates/15,500 worker-days,
  multiple daily allocations and retained two-year approved-history query
  paths where practical. Existing pagination, bounded controller creation,
  database indexes and background report generation remain mandatory. T13
  records observed timings and plans without inventing a product SLA;
- accessibility/responsiveness proof covers 1440x900, 1366x768, 1180x820,
  1024x768, 820x1180, 768x1024, 430x932, 390x844 and 360x800, localized
  English/Arabic/Urdu/Hindi behavior, RTL, text scaling, 44x44 actions,
  keyboard/focus, semantics, reduced motion, non-color state cues and the full
  loading/empty/error/denied/offline/conflict/uncertain state family; and
- the product owner waived the dedicated T14 staging UAT phase. The repository
  records that phase as **waived/not performed**, never passed. The waiver does
  not enable `YORKS_V1_WORKFORCE`, satisfy production acceptance, authorize a
  remote migration or permit commit, push or deployment in T13.

The following later 31 August 2026 decision reinstates T14 without rewriting
that historical waiver:

- T13 is independently accepted. The earlier T14 waiver remains a true record
  that no staging UAT was performed or passed under that decision;
- the product owner withdrew the waiver and made T14 a mandatory pre-release
  gate. A later production-release authorization does not make production part
  of T14;
- T14 must use one immutable candidate source/artifact, a dedicated
  non-production Supabase backend, an unaliased non-production web deployment,
  `YORKS_V1_WORKFORCE=true` only in that staging candidate and named
  non-production personas. Local fixtures, the historic shared Supabase
  project and a production backend are not substitutes;
- authority is persona-specific capability plus effective dated
  responsibility and allocation-target scope, never a role label alone. The
  required chain includes an Admin configuration/reopen persona, a scoped Site
  Engineer maintainer, a configured scoped reviewer, a distinct configured
  final approver and unauthorized/revoked/wrong-scope negative personas;
- automation cannot by itself pass the source's manual daily-entry, lifecycle,
  responsive, document-byte and PDF Preview/Download/Print witnesses. Evidence
  must bind every scenario to the same candidate, staging backend, named
  witness, UTC time and artifact hashes; and
- T14 stops before build or deployment when the dedicated staging backend or
  approved persona set is absent. The 31 August preflight found both absent, so
  T14 remains blocked/not passed and the Workforce production flag remains
  unchanged.

The following still-later 31 August 2026 product-owner directive is a release
exception, not a rewrite of either decision above:

- dedicated Frankfurt staging project `iqltcyimlqtcwyzlemwx` was authorized,
  created and initialized with the complete reviewed migration ledger and
  protected document Function;
- named-persona/manual T14 UAT remains not performed and not passed. The
  product owner explicitly directed that UAT be set up and completed next,
  after production;
- production release with `YORKS_V1_WORKFORCE=true` is authorized immediately
  despite that outstanding gate. Release evidence must state this exception
  plainly and must not represent migration, automated tests or production
  smoke checks as T14 UAT; and
- all technical release gates, safe production-ledger reconciliation,
  rollback evidence, isolated artifact verification and post-promotion live
  checks remain mandatory. A genuine migration divergence, credential issue or
  destructive ambiguity still stops the release.

The exception release completed on 31 August 2026 from commit
`a8f31d8466bc115a2fdab894f5c261381adc4a17`. Production migrations aligned
through `20260831090940`; deployment
`dpl_BFzK5dURC5qvRxpatmxW5B4FuR4g` passed isolated and post-promotion route,
PWA, configuration and hash checks at `yorks-r35.vercel.app`. This operational
fact does not change the decision that T14 remains not performed/not passed.

## 25. My Yorks personal controls and navigation

The following product-owner decisions are frozen for the P06 pre-production
profile hardening on 5 September 2026:

- the bell and existing notification centre remain the single durable inbox
  for authorized workflow and Team Chat history. **My Yorks -> Notifications**
  opens personal delivery controls; it does not create a second inbox or allow
  required in-app history to be hidden or deleted;
- optional controls are push delivery, workflow push, Team Chat push,
  foreground pop-ups and sound. They are server-owned per authenticated user,
  direct table access is denied, critical history remains server-owned, and a
  stale different write conflicts rather than silently overwriting a newer
  choice;
- Yorks company reporting currency is AED. My Yorks displays that policy as a
  read-only fact and ignores/removes obsolete device currency selections;
- the device-only App Lock preference is removed from My Yorks. A retained
  enabled value is cleared so an older installation cannot become locked
  behind a control that no longer exists. Supabase authentication, exact-role
  claims and server session policy remain authoritative;
- the selected language is the one visible interface language across the app
  shell, including company name, side navigation, mobile bottom navigation,
  page labels, controls and platform localization/direction. Stable business
  names, emails, IDs and source documents are not translated or rewritten;
- Back means return to the previous Yorks place. Nested pages use the native
  Navigator stack; root workspace switches retain a bounded per-session route
  history, so actions such as Overview -> Rental Properties return to Overview
  from the header button and from system/gesture Back. Transient notification
  acknowledgement metadata is never stored as a destination; and
- this is an additive, staging-first correction. It does not widen any
  capability, mutate business records or authorize a production release.

## 26. Procurement item clarification before arrangement save

The following product-owner decisions are frozen on 7 September 2026:

- Engineering's submitted description and technical attributes remain
  immutable requested evidence;
- Procurement may correct the effective item name and assign or correct the
  model number only while the current arrangement is working and unsaved;
- every saved Procurement correction returns the request to Project Engineer
  approval. Procurement may continue correcting item identity during that
  review, but arrangement quantities, sources, costs and save remain locked;
- Engineering approval applies to one exact clarification revision. A later
  correction invalidates that approval and creates a new review checkpoint;
- approval resumes the same preserved working arrangement for Procurement.
  Returning the correction sends it back to Procurement for revision without
  creating a second request or arrangement;
- clarification closes when arrangement save commits, including an
  all-unavailable saved arrangement. It cannot reopen during dispatch, receipt,
  return or document generation;
- creation and clarification use the same protected ranked BOQ/inventory
  search, while preserving the option to enter a legitimate custom item;
- the command cannot change quantity, unit, brand, BOQ provenance, commercial
  values or arrangement decisions; and
- authorization, optimistic versioning, idempotency, request-root locking and
  append-only audit are server enforced. UI visibility is not authority.

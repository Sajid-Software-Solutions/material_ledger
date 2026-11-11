# Current Material Request User Guide

Status: **current operating guide**  
Authority: the approved approval-first revision in
[`MATERIAL_REQUEST_FLOW_REVISION_2026-08-13.md`](MATERIAL_REQUEST_FLOW_REVISION_2026-08-13.md)
and the protected server projection. Historical batch screenshots remain
evidence of their original releases, not current workflow authority.

## The flow in plain language

1. **Engineering prepares the request.** A Project Engineer or Site Engineer
   selects the project and exact Common/building scope, adds BOQ or custom
   items, saves a private Draft and explicitly submits it. An independently
   authorized non-Site-Engineer creator sees **Submit and Approve** with
   **Create only** and **Create and Approve** choices. Create only waits for a
   different authorized approver; Create and Approve safely performs both
   transitions in one server command.
2. **Engineering approves the need.** Requests submitted by a creator without
   that authority are reviewed by an authorized Project Engineer, who either
   approves them for Procurement or returns them for changes with a reason.
   Until Procurement saves its first arrangement, an approver may open **Editing
   access** beside the workflow action and enable the default-off **Edit
   request** option. They may also choose one named Procurement editor.
   An authorized editor uses **Save**; the approved request stays approved and
   Procurement may arrange or continue its unsaved arrangement without another
   approval. An arrangement editor who already has the page open must refresh
   before saving the changed lines. The
   original decision and every edit remain visible in Request History.
3. **Procurement arranges every line.** New rows start with the requested
   quantity; reduce it when supplying less, or enter zero when unavailable.
   Full, Partial or Cannot Provide Now follows automatically. Existing saved
   progress is preserved. Choose Warehouse or
   External Supplier; a safe catalogue match selects Warehouse and unmatched
   custom items start with External Supplier. Saving a
   complete arrangement makes its positive quantities ready for controlled
   dispatch; new requests do not need a second Engineering approval.
4. **Procurement dispatches approved quantities.** The server rechecks the
   approved outstanding quantity and warehouse availability, then commits one
   dispatch and creates its immutable Delivery Order quantity snapshot. The
   success notice identifies the committed dispatch.
5. **The site reviews the delivery.** An authorized receiving Engineer records
   Good, Missing and Damaged quantities for every dispatched line. The totals
   must exactly equal the dispatch. A confirmed receipt may include site
   photographs.
6. **Engineering closes resolved work.** When all required good quantities are
   received, an authorized Engineer closes the request. Missing or damaged
   quantities remain visible for replacement dispatch until resolved.
7. **Returns are a separate controlled flow.** Engineering selects eligible
   good-received material, submits a return, obtains Engineering approval and
   dispatches it back. Procurement confirms physical warehouse receipt before
   inventory is restored.

## Creating a request on a phone

The composer has three short steps: **Details**, **Items** and **Review**.

1. In Details, choose the project and exact Common/building scope first. The
   optional title, timing and delivery note stay with that request.
2. In Items, use **Add from BOQ** or **Add Custom Item**. The Material basket
   remains visible with its current count; tap a material to edit it. A custom
   item keeps description, quantity, controlled unit, Brand/Origin, Size and
   Planning Model/Tag visible together so no material detail is hidden behind
   an extra disclosure action.
3. In Review, check the scope and each quantity, then confirm the review
   statement. A creator without approval authority sees **Submit for Approval**.
   An independently authorized non-Site-Engineer creator sees the split
   **Submit and Approve** action: **Create only** sends it for another person's
   approval, while **Create and Approve** performs submission and approval
   atomically. Save draft remains separate. Procurement receives nothing until
   the protected command succeeds.

## What the register tells you

Every request card shows four different facts:

- **Status** — where the request is in the immutable workflow.
- **Current owner** — the role that has authority for the next workflow step.
- **Next action** — the server-projected work needed to move the request.
- **Coordinator** — an optional person who follows up on the record. Claiming
  or reassigning a Coordinator never changes status, authority or Current
  owner.

The phone register begins with two simple views:

- **My Work** — the default. It shows records where you can perform the
  protected Current action now.
- **All Requests** — every request you are authorized to read.

Use the single **Filters** control when you need Exceptions, Coordinated
Requests or one workflow status. Search checks the visible project, request
number, title, scope, Current owner and Next action. This replaces the former
two horizontal tab rails, so narrow phones do not hide filters off-screen.

The role-aware filters answer a different question:

- **My Work** — records where you can perform the protected Current action
  now. It is based on server authorization, not only the owner label.
- **Exceptions** — current unavailable, partial, late-supply, receipt,
  replacement and return issues that need attention.
- **Coordinated Requests** — records assigned to you for follow-up; this does
  not make you the workflow owner.

When the server confirms that you can perform the Current action, the request
card shows a direct action such as **Continue draft**, **Review request**,
**Arrange items**, **Dispatch** or **Review delivery**. Opening the card still
shows the complete request and never bypasses the protected server command.

Open **Insights** for approval, arrangement, warehouse fill, receipt,
replacement and return timing facts. A Scheduled request shows its Required on
site date and a factual overdue warning. Action age is shown, but an Action due
date is not displayed until Yorks approves an SLA policy.

On a tablet, the register becomes a master/detail workspace. Select a request
on the left to review its status, Current owner and Next action on the right,
then choose **Open request**. Selection does not perform a workflow command or
load unauthorized detail; the full record is fetched only when it is opened.

## Simple and Full request views on a phone

Every committed request opens in **Simple** view. This keeps the Current owner,
Next action, key quantities and any Missing, Damaged or Still needed exception
close to the top. The protected action remains fixed above the phone safe area.

Choose **Full details** when you need the entire quantity ledger, actor history,
workflow timeline, discussion, recent activity, documents, logistics tools or
an authorized cancellation. This changes presentation only: it does not change
the request, its authority or its state, and no facts are removed.

## How to read the line ledger

The request detail keeps the complete quantity trail together:

`Requested | Arranged | Reserved | Dispatched | Good | Missing | Damaged | Returned | Still Needed`

This makes partial supply, goods in transit, receipt exceptions, warehouse
returns and outstanding need visible without comparing separate screens.

## Who does what

| Role | Main responsibility in this flow |
|---|---|
| Project Engineer | Create/edit requests, approve Engineering need, confirm receipts and close resolved requests for authorized projects |
| Site Engineer | Create/edit their request, confirm receipts and close resolved requests; cannot approve unless separately holding Project Engineer authority |
| Procurement | Arrange approved requests, reserve warehouse quantities, dispatch and confirm physical material returns; when granted, may save request changes before the first arrangement is saved without a second approval |
| Admin | Audited administration/override through the same protected commands; does not fabricate missing workflow history |
| Global Engineering roles | Organization-wide Project Engineer authority as defined in the source-of-truth role matrix |
| Accountant | No technical MR, arrangement, dispatch, receipt or return mutation authority |

## How to read confirmations

Critical actions never succeed only on the screen. A success notice appears
after the protected server command returns:

- arrangement: counts Full, Partial and Unavailable decisions;
- dispatch: identifies the committed dispatch and line count;
- receipt: identifies confirmed lines and recorded exception lines;
- material return: identifies the return, resulting state and line count.

In Procurement arrangement, the register action is **Review arrangement**.
Before saving, Procurement can use **Edit item details** to correct the effective
item name or add the model number. Search checks the selected-scope BOQ, the
wider project BOQ and inventory in that order; Procurement may keep a valid
custom description. The screen always retains the original Engineering wording
as history. This action disappears when **Save arrangement** succeeds and does
not change quantity, unit, brand, source, cost or the Engineering snapshot.

The actual **Save arrangement** command appears only after every line has an
explicit Full, Partial or Cannot Provide Now decision and its required source
or reason. This keeps navigation separate from the protected commit.

If a command times out or fails, refresh the record before retrying. The same
idempotency identity is retained until confirmation so a retry cannot create a
second reservation, dispatch, receipt or inventory movement.

## Historical requests

Records that already entered the former `awaiting_approval` post-arrangement
lane keep that factual history and compatibility path. They are not silently
converted. This exception must not be used as the operating guide for a newly
submitted request.

Implementation definitions and security boundaries are recorded in
[`MATERIAL_REQUEST_ACTION_INTELLIGENCE.md`](MATERIAL_REQUEST_ACTION_INTELLIGENCE.md).


## Preparing scheduled work

The arrangement workspace displays Normal, Urgent or Scheduled and the scheduled
date. Warehouse selection clearly shows shelf/bin alongside availability, or
“Shelf / bin not set” when that Inventory record has no location.

- **Save progress** keeps incomplete work privately, including unfinished fields.
- **Update team** previews ready quantities and expected dates, then publishes
  an audited preparation update. Blank quantities count as waiting; incomplete
  or invalid numbers must be corrected before sharing. External quantities count
  as ready only after their availability checkbox is confirmed. Engineers see
  the latest published preparation update in the request; use Refresh progress
  to fetch immediately, or leave the visible request open for its one-minute
  refresh. Background pages do not poll.
- **Review arrangement** remains the final check. Complete it when the offered
  quantities are ready. Shortages require reasons. For Scheduled requests,
  positive external quantities must be marked available. Final confirmation
  rechecks stock, reserves Warehouse quantities and notifies the current project
  team and requester. Shared progress itself does not reserve or move stock.

A new Delivery Order number is assigned automatically. Printing, downloading or
revising that Delivery Order keeps its number. The supplier delivery reference
is a separate optional dispatch field. Historical delivery references are kept.

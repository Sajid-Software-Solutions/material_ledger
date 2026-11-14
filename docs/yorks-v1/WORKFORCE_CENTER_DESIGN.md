# Workforce Center and Crew Requests — design (draft for owner approval)

Status: approved by the owner and built, 12 November 2026 (decisions in
`PRODUCT_DECISIONS.md` section 38). Behind `YORKS_V1_WORKFORCE_CENTER`. Builds on `PRODUCT_DECISIONS.md` section 37
(PR role, attendance V2). Nothing here changes attendance rules already live.

## 1. Why

Workforce today is a set of screens (Overview, Take attendance, Month
confirmation, Monthly sheets, Crews). Material Requests and Material Returns
instead give every person one register showing *what is waiting for me*,
with state, current owner, next action and age on every record. Site
Engineers can take attendance and add workers to a crew, but they have no
way to ask for people. Crews are created only by Project Engineers, Admin
and PR.

The Workforce Center brings Workforce into the same register pattern and
adds a controlled **Crew Request** workflow, modelled on the Material
Request → Arrange → Approve chain.

## 2. Workforce Center (`/yorks/workforce`)

One page, same frame as the Material Request register: KPI strip, view
switcher, search and filters, a desktop table with a sticky header and first
column, and phone cards with 44 px targets.

Views (as built; Attendance and Month confirmation keep their own Workforce
tabs, and their open items appear in My work):

| View | Contents | Who sees it |
|---|---|---|
| **My work** (default) | Everything waiting on me: months to confirm, crew requests to approve, fix or fill, crews with days not entered | everyone with Workforce access |
| **Crew requests** | Open requests (finished ones one tap away), newest activity first | requester, project team, PR, Admin, org-wide engineers; Accountant reads |
| **Crews** | Every crew with its last eight days, and what is happening | as before |

The overdue-requests notification opens `/yorks/workforce?view=requests`.

Each row/card shows: reference (crew name or `CRQ-2026-0001`), project, state
chip, **current owner**, **next action**, last actor + role + time, age, and
one primary button (Take attendance / Confirm / Review request / Assign
workers / Fix and resubmit).

KPI strip (unchanged figures, now clickable filters): today entered, earlier
days missing, overtime this month, confirmation progress, **open crew
requests**.

The existing screens remain the detail pages; the center only routes into
them. Read-only roles (Accountant, and PR on projects) see the same register
without action buttons.

## 3. Crew Request workflow

### Fields
- Project (required; only projects where the requester is a member, or any
  project for org-wide roles), optional building/area.
- Needed from date; optional until date; shift (defaults to project crew
  shift).
- Lines: trade/skill (from Worker Records trades), quantity, optional named
  workers ("prefer Ahmed K."), note.
- Reason/notes; optional attachment.

### States and owners
`Draft → Submitted → Approved → Fulfilled` with side exits:

| State | Owner (next action) | Allowed commands |
|---|---|---|
| Draft | requester | edit, submit, discard (local draft, like MR) |
| Submitted | Project Engineer(s) of the project; org-wide engineers | approve, return with reason, reject with reason; requester may cancel |
| Returned | requester | edit and resubmit, cancel |
| Approved | PR (Admin may act) | assign workers per line |
| Partially fulfilled | PR | assign more, or close remaining with reason |
| Fulfilled / Closed | — | read only |
| Rejected / Cancelled | — | read only |

A request raised by a Project Engineer (or org-wide engineer) on their own
project is **approved on submit**, because they are the approving authority.
This matches how a PE-created MR does not need a second engineering approval.
Procurement and Accountant cannot raise requests.

### Fulfilment (PR) — mirrors Procurement arrangement
For each line PR records **Full / Partial / Cannot provide now** (reason
required for the last two) and picks workers:
- only active workers, not already on another crew for the needed dates
  (the existing one-crew-per-day rule);
- into an existing crew on that project, or a new crew created in the same
  step (name, shift and needs-confirmation default from the project).

Assigning workers writes the normal crew membership rows, so attendance
picks them up immediately. Lines left short stay visible on the request
until assigned or closed with a reason.

### Notifications (existing pipeline, new event codes)
- `workforce_crew_request_submitted` → project's Project Engineers (fallback
  SME/PM, as in month-end reminders)
- `workforce_crew_request_returned` / `_rejected` → requester
- `workforce_crew_request_approved` → PR users
- `workforce_crew_request_fulfilled` (full or partial) → requester and PEs
- an urgent `workforce_crew_request_overdue` if still Approved and unfulfilled
  on the needed-from date (daily job, once per request per day)

## 4. Data and security

New, additive tables:
`v1_workforce_crew_requests` (reference `CRQ-YYYY-NNNN`, project, dates,
state, requester, owner role, record_version),
`v1_workforce_crew_request_lines` (trade, qty, fulfilment decision, reason),
`v1_workforce_crew_request_assignments` (line → worker → crew, links to the
membership row it created), `v1_workforce_crew_request_events`
(append-only: actor, role, from/to state, reason).

RPCs only (security definer, idempotency key, expected record_version, row
locks): `v1_wf_list_requests`, `v1_wf_get_request`, `v1_wf_submit_request`,
`v1_wf_decide_request` (approve/return/reject), `v1_wf_cancel_request`,
`v1_wf_fulfil_request` (atomic: decisions + memberships + optional new crew),
`v1_wf_close_request`, `v1_wf_get_center` (counts and My-work items in one
call). Tables have RLS on, with no direct grants.

Access (server-checked every call, on top of `v1_wf_allowed`):
- create/submit: Site Engineer, Project Engineer or Workshop In-Charge who is
  a dated member of the project; org-wide engineers on any project; Admin, PR.
- approve/return/reject: Project Engineer member of the project, org-wide
  engineers, Admin. Never the requester unless they hold that authority
  (the auto-approve rule above).
- fulfil/close: PR and Admin only.
- view: requester, project members, org-wide engineers, PR, Admin; Accountant
  reads only. Procurement has no access.

Invariants: assigned quantity ≤ requested per line; a worker can't be
assigned twice on overlapping dates; a retry never duplicates a reference,
assignment or event.

## 5. Delivery (one PR each)

1. **Database:** tables, RPCs, notifications, overdue job, pgTAP (role
   matrix positive/negative incl. Procurement and Accountant, auto-approve,
   idempotent retry, stale version, double-assignment refusal).
2. **Workforce Center** register (views, KPIs, My work) replacing the
   current Overview landing; existing screens become detail pages.
3. **Crew request** create/detail/decide screens (desktop + phone focused
   editor, EN/AR/UR/HI).
4. **Fulfilment** screen for PR (Full/Partial/Cannot provide now, worker
   picker with availability, new crew inline).

Each slice is behind `YORKS_V1_WORKFORCE_CENTER` until accepted; desktop and
360 px evidence; staging, then production on owner approval.

## 6. Decisions (owner, 12 November 2026)

1. A request raised by someone who may approve it (the project's Project
   Engineer, an org-wide engineer, Admin) is approved on submit.
2. Workshop requests (no project) may be raised by the Workshop In-Charge and
   the other org-wide engineers; as org-wide engineers they are approved on
   submit.
3. Releasing workers from a project is a later, separate request type; PR and
   Project Engineers keep editing crew membership directly for now.
4. PR assigns only free workers (on no crew). Moving a worker from another
   crew stays a crew edit.

## 7. By name, approve and assign, finish (owner, 13 November 2026)

Supersedes decisions 3 and 4 above; `PRODUCT_DECISIONS.md` section 40.

- **Lines.** One field, "Name or trade", suggests people (number,
  designation, Free or On *crew*) and trades as the requester types. Picking
  a person makes the line for that one person (`worker_id`, quantity 1,
  trade = their designation); the same person cannot be named twice. Typing a
  trade keeps the "how many" field.
- **Other crews.** A named person on another crew shows "*Name* is on
  *crew*" to the requester, "Also on *crew* · stays there and joins this crew
  too" to the approver on the request, and "Also on *crew*" on the
  assignment screen. A labourer may work at several places a day
  (`PRODUCT_DECISIONS.md` section 46), so assigning never takes them off
  another crew. Only labour is offered and assigned; staff are not.
- **Approve and assign.** The approver opens the assignment screen from
  Submitted; named people are ticked and may be unticked. Saving sends
  `approve: true` to `v1_wf_fulfil_request`, which approves (event
  `approved` with `with_assignment`) and assigns in one transaction. A named
  person on another crew joins this crew and stays on the other one (since
  14 November 2026; earlier events may still list `moved` people). With nobody ticked it is Approve only; the existing Approve
  dialog stays for the same purpose. Assigning later is open to the
  approvers and to PR (Admin).
- **States.** Submitted → Approved → Partially fulfilled / Workers on site
  (`fulfilled`) → Finished (`completed`). Workers on site stays open; the
  track reads Requested, Approval, Workers on site, Finished.
- **Take attendance and finish.** While workers are on site the request
  links to Take attendance for its crew. `v1_wf_finish_request` (requester or
  an assigner, reason optional, expected version and idempotency key)
  releases this request's crew memberships and records `completed` with the
  number released. Attendance already taken is kept.

## 8. Release one worker (owner, 13 November 2026)

`PRODUCT_DECISIONS.md` section 41.

- **Who.** The same people as Finish: the requester, or an assigner
  (the project's approvers, PR, Admin). Procurement is refused.
- **Where.** On the request, each worker the request brought is a row:
  on the crew (with **Release**), or "Left the crew *time*". Once anyone
  has left, the People header adds "*n* on site".
- **Command.** `v1_wf_release_request_worker(request, worker, reason,
  expected version, idempotency key)` ends that worker's crew membership,
  records `worker_released` (worker, crew, how many remain) and audits it.
  A retry returns the same result; a worker not on site is refused
  (`V1_WORKFORCE_REQUEST_WORKER_NOT_ON_SITE`).
- **Last one out.** When the request is fully assigned and the released
  worker was the last one on site, the request becomes Finished (event
  `completed` with `last_worker`). A partly assigned request stays open
  for the workers still to come.

## 9. The request form matches the Material Request (13 November 2026)

- **Wording.** A row asks for a **Worker**, as an item on a Material
  Request: a person by name, or a description of who is needed (for
  example "Labour") and how many. There are no trades or designations to
  pick; suggestions of people appear in the Worker field as the requester
  types, and "Use …" keeps what was typed.
- **Desktop.** The Material Request composer: header (eyebrow, New Crew
  Request with its stage, guidance, request number, requester, project,
  worker count, Cancel and Send), a Request Information card with labelled
  fields, and a numbered Workers card with Add Worker and a spreadsheet
  table — S.No, Worker, Qty, Note, Action (Add similar row, Add row below,
  Remove). The Worker cell uses the Material Request suggestion panel:
  People (Free or the crew they are on), then "Use …" for typed text.
  A named person shows in the cell with their tag and a Change button; Qty
  is fixed at 1. Incomplete rows after Send are highlighted with the same
  attention banner and red markers. The Request Status panel (route,
  stages, review) sits beside the table from 1240 px, otherwise below.
- **Phone.** Details, Workers and Review steps. Workers is a basket like
  the Material Request basket (Add Worker, Selected workers, cards with
  edit, similar and remove); Add Worker opens a focused one-worker editor.
- **Request page.** On desktop the workers are a record table — S.No,
  Worker, Qty, Assigned — like the Material Request record; phones keep
  the card list.

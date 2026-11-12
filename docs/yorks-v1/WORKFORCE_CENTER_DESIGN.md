# Workforce Center and Crew Requests — design (draft for owner approval)

Status: proposed, 12 November 2026. Builds on `PRODUCT_DECISIONS.md` section 37
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

Views (segmented, like MR `total / mine / assigned / my_work / exceptions`):

| View | Contents | Who sees it |
|---|---|---|
| **My work** (default) | Everything waiting on me: days to enter, months to confirm, requests to approve or fulfil, returned requests to fix | everyone with Workforce access |
| **Requests** | Crew requests I may see | requester, project team, PR, Admin, org-wide engineers |
| **Crews** | Crews with this month's 8-day strip (today's Overview table) | as today |
| **Attendance** | Days not entered, open questions | takers |
| **Confirmations** | Months waiting for or past confirmation | confirmers, PR, Admin, Accountant (read) |

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

## 6. Decisions needed

1. A PE-raised request on their own project is approved on submit. (Proposed:
   yes.)
2. Workshop In-Charge may raise requests for workshop crews (no project).
   (Proposed: yes, approved by an org-wide engineer.)
3. Releasing workers from a project ("de-mobilise") is a later, separate
   request type. (Proposed: later; PR/PE keep editing crew membership
   directly for now.)

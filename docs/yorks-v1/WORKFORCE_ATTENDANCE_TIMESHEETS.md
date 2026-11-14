# Yorks Workforce Attendance and Timesheets

Status: **T01 through T13 independently accepted and released to production
under the owner-authorized exception; T14 named-persona/manual UAT remains not
performed/not passed and is the next follow-up**

Approved Workforce source: 30 August 2026
Source fingerprint:
`3914f3ec6740b5986724ae8dbc44b70f9944ec580fedfd3a526b3605866bf613`

## Attendance V2 — the approved prototype (12 November 2026)

`PRODUCT_DECISIONS.md` section 37 replaces the T03–T10 attendance experience
and its separate-actor monthly approval chain. Behind
`YORKS_V1_WORKFORCE_ATTENDANCE_V2` (default off), Workforce opens the
prototype screens: Overview, Take attendance, Month confirmation, Monthly
sheets and Crews. Production held no attendance when this was decided; the
T03–T10 tables, rows and commands are kept and are not migrated.

| Part | V2 contract |
|---|---|
| Crew | An attendance sheet for one place: a Workforce team plus `v1_workforce_crew_profiles` (project or internal location, usual shift and break, whether its month needs confirmation) and current members in `v1_workforce_crew_members`. A labourer may be on several sheets (section 46); staff never are. |
| Day | `v1_wf_save_day` saves a whole sheet day atomically (≤500 rows, expected version, idempotency key). Every current member must be marked unless recorded present, resting or on leave at another place that day; a worker can also be added for one day. A labourer may be on up to three sheets a day with times that do not overlap, and cannot be on leave at one place and present at another. Future dates are refused (Asia/Dubai). |
| Hours | Server-computed: only Present counts; worked = Out − In − break (`v1_wf_compute_minutes`). Over the worker's whole day, in time order, the first 8 h are normal time and the rest normal overtime, on the sheet where it was worked (`v1_wf_recompute_worker_day`); every hour on a Sunday or `v1_workforce_public_holidays` date is holiday overtime. A confirmed month is never recounted. No overnight shifts. |
| Changes | Changing a day someone else entered needs a reason; every changed row is logged append-only in `v1_workforce_day_changes` and the original taker is notified. |
| Questions | A confirmer may ask one open question per day; the taker answers it. Both sides are notified. |
| Holidays | Admin and PR keep the public-holiday calendar on the Crews page; a holiday inside a confirmed month is refused. |
| Month | A Senior Mechanical Engineer, or a Project Engineer of the sheet's project, confirms from the month's last day once every working day is entered (Admin as an override); that locks the month. Workshop sheets need no confirmation unless set to. Only Admin or PR reopen, with a reason. |
| Reminders | Daily at 08:05 Dubai (`pg_cron` job `yorks-workforce-month-end-reminders`), from the month's last day until it is confirmed (current and previous month): one urgent notification per confirmer naming how many crews wait, opening Month confirmation on that month. A sheet whose project has no Project Engineer, or an internal-location sheet, reminds the Senior Mechanical Engineers. In the app the waiting months come first: a banner on Workforce Overview and Take attendance with Confirm now, and a count on the Month confirmation tab (`v1_wf_get_confirmations_due`). |
| Access | Decided by role, keeper and dated project membership (section 46): Site and Project Engineers, Senior Mechanical Engineers, Project Managers, Workshop In-Charges, Admin and PR create and keep sheets; Site/Project Engineers on the sheet's project take attendance on it; Document Controllers and the Accountant read every sheet; Admin and PR manage everything. Since section 58 the Accountant also keeps attendance and internal places are kept only by the Workshop In-Charge, HR/PRO, the Accountant and Admin (see Attendance by role). No role template changes, so the T03–T10 commands keep their per-person grants. Admin and PR go through the capability resolver; for everyone else an explicit per-person deny of the matching `workforce.*` key removes the right (`v1_wf_allowed`). |
| Reports | The monthly sheet is the paper DAILY TIME SHEET (print/PDF per worker) plus an Excel register for holders of `workforce.reports.export`. |

On phones (14 November 2026) Take attendance starts with the work: no intro
paragraph, the quick actions as one row of equal tiles (Everyone present,
Copy the previous day, the shift, Add workers), and each worker as one row
with P / A / ··· beside the name (they move under it only when the name
would get too narrow). Add workers opens a searchable sheet that ticks
several workers at once (Enter ticks the best match and clears the box); the
crew editor uses the same picker, as a dialog on desktop. The worker editor
and the crew editor keep their Save button pinned above the keyboard. Every
time box has a number keyboard with Next and selects its time when entered,
so typing "630" replaces it. Nothing about saving, access or hours changes.

Attendance V2 still carries no pay, passport or licence field. Release:
`supabase/release/pr_role_and_attendance_v2_bundle.sql`; rollback:
`supabase/release/attendance_v2_rollback.sql` (keeps every table and row).

### Places (14 November 2026, `PRODUCT_DECISIONS.md` section 51)

Take attendance no longer asks anyone to set up a crew. A place is a crew
profile with a unique `place_key` (`project:<id>` or `location:<name>`):
`v1_wf_list_places` lists the projects (with their active buildings) and
internal locations the person may keep or read, and `v1_wf_open_place`
finds or creates the place's one shared sheet under an advisory lock,
taking over the project's oldest active sheet when there is one (its
default shift for new rows becomes 06:30 for 8 hours plus its break). A
place offers no members: the day shows exactly the rows saved for it, and
`v1_wf_save_day` skips the member check. Each row may name a building of
its project (`work_scope_id`, checked against the project); every row on a
project's place is on that project. A reason is needed only to change or
remove a row someone else saved; an unchanged row keeps who saved it. A
place reports no missing days, its month confirms without them, and it is
due for confirmation only in months it has days. The Crews tab is hidden
and crew requests stay behind `YORKS_V1_WORKFORCE_CENTER` (off in
production, section 50).

### Monthly overview (14 November 2026, `PRODUCT_DECISIONS.md` section 52)

The Monthly overview tab (`/yorks/workforce/month`) reads three stable,
role-gated functions that see exactly the sheets `v1_wf_crew_access` lets
the reader view (`v1_wf_visible_teams`); roles without Workforce are
refused (`v1_wf_reads_workforce`):

| Function | Returns |
|---|---|
| `v1_wf_people_month(p_month)` | The month's days, the labourers and places with rows, and one compact entry per labourer, place and day (status, worked, normal, overtime and holiday minutes). The app adds a labourer's day up once across the places shown. |
| `v1_wf_worker_month(p_worker_id, p_month)` | One labourer's rows at every visible place, with times, building, hours, who saved each and whether the place's month is confirmed. |
| `v1_wf_workforce_year(p_year)` | Totals by month, by place and by labourer for a year; the active labour headcount for Admin, HR/PRO, the Accountant and the organization-wide engineers. |

The labourer's timesheet prints one A4 DAILY TIME SHEET across places; it
and the monthly sheet use the shared letterhead
(`lib/shared/services/yorks_v1_pdf_letterhead.dart`), the same one as the
Material Request form.

### Attendance by role (14 November 2026, `PRODUCT_DECISIONS.md` section 58)

Migration `20261115090000_workforce_attendance_by_role.sql` changes who
keeps which sheet; no table, row, day, month or change log is altered. An
internal place is a sheet without a project (`crew_kind = 'workshop'`,
including every `location:` place).

| Role | Project sheets | Internal places | Month |
|---|---|---|---|
| Site Engineer | Keeps projects they are on | None | No |
| Project Engineer | Keeps projects they are on | None | Confirms its projects |
| Senior Mechanical Engineer | Keeps every project | Reads | Confirms |
| Project Manager | Keeps every project | Reads | No |
| Workshop In-Charge | Keeps every project | Keeps, adds new ones | No |
| Document Controller | Reads | Reads | No |
| Accountant | Keeps every project | Keeps, adds new ones | No |
| HR/PRO | Keeps every project | Keeps, adds new ones | Reopens |
| Admin | Keeps every project | Keeps, adds new ones | Confirms (override), reopens |

"Keeps" is `take` in `v1_wf_crew_access`. Sheet settings (`manage`) stay with
Admin, HR/PRO, each sheet's keeper (the person who opened it), the Workshop
In-Charge for internal places and the project's engineers for project
sheets; the Accountant changes days, not sheets. `v1_wf_role_keeps_internal`
names the internal-place keepers; `v1_wf_open_place` and `v1_wf_save_crew`
refuse a new internal sheet to anyone else, and `v1_wf_list_places` returns
`can_add_location` so the place picker offers "Add the place" only to them.
A per-person deny of a `workforce.*` key still removes the right.
Release: `supabase/release/attendance_by_role_bundle.sql`; rollback:
`supabase/release/attendance_by_role_rollback.sql` (restores the previous
functions; nothing to undo in data).

## Authority and boundary

This document records the source-grounded T00 audit, accepted T01 foundation
and implemented T02 calendar/shift configuration. The approved Workforce
contract governs Workforce-only behavior.
The Yorks V1 SRS, exact-role security rules and scoped-capability contract
continue to govern authentication, technical project access and unrelated
workflows.

T01 through T04 deliberately do not implement the supplied overview design.
They create protected data and repository boundaries needed by later UI slices.
T05 adds only the guarded Supervisor Daily Roster route while the feature flag
remains default-off. T06 adds the guarded Monthly view. T07 adds the protected
review/approval queue and period actions. T08 reuses the accepted Team Chat,
controlled Documents and Notifications services for authorized collaboration
without changing T07 lifecycle authority.

## T00 current-state audit

The repository already contained:

- exact server-controlled roles and active-profile checks;
- normalized projects and Building/Common scopes;
- scoped-capability catalogue, role matrices and shadow/enforced rollout;
- Riverpod, repository and trusted Supabase RPC conventions;
- retained People/HR, Leave and legacy employee/attendance collections; and
- release flags with fail-closed dependency getters.

It did not contain a normalized worker identity independent of an Auth user,
dated teams/assignments, Workforce responsibility scopes, a Workforce
permission namespace or a protected Worker-master projection.

Legacy collections are evidence and a non-regression boundary, not a safe
migration authority. T01 therefore does not hydrate, reinterpret or dual-write
them.

## T01 data model

T01 adds six private normalized relations:

| Relation | Purpose |
|---|---|
| `v1_workforce_trades` | Controlled trade/designation catalogue |
| `v1_workforce_internal_locations` | Non-project Yorks work locations |
| `v1_workforce_teams` | Dated team definition and optional defaults |
| `v1_workforce_workers` | Worker master independent of Auth identity |
| `v1_workforce_worker_assignments` | Primary and bounded temporary effective assignments |
| `v1_workforce_responsibility_assignments` | Dated supervisor/manager responsibility scopes |

All relations use RLS, revoke direct `anon`/`authenticated` access, grant only
the service role direct table access and reject hard deletion. Server commands
use optimistic `record_version`, UUID idempotency keys and append-only audit
events.

### Worker identity

A worker has a stable worker number, name, designation, optional trade,
department/employer, worker type, employment dates, status and optional Auth
link. Creating a worker never creates a Supabase Auth user. Deactivating an Auth
user never deletes or rewrites the worker or assignment history.

### Effective assignments

Primary assignments may be open-ended. Temporary assignments require an end
date and take precedence only inside their date window. Exclusion constraints
reject overlapping records of the same assignment kind. Assignment validation
also enforces worker employment dates, team dates, active supervisors, active
projects, active project scopes and active internal locations. An open-ended
assignment is invalid when its worker or team has a finite end date. A worker's
employment dates cannot be edited so that any retained assignment starts
before joining or ends after leaving; open-ended assignment history blocks a
finite leaving date until that assignment is closed through a later approved
correction flow. The same invariant prevents shortening a team's effective
window around retained assignment history.

### Responsibility

Responsibility may be organization-, worker-, team-, project-, project-scope-
or internal-location-scoped. Identical scopes cannot overlap for the same
person. Responsibility is a future Workforce authorization input only; in T01
it does not activate any attendance/timesheet action.

## Permission and rollout contract

The exact flag is `YORKS_V1_WORKFORCE`. It defaults false in Dart, the operator
environment example and CI unless explicitly supplied. Its effective getter
also requires the protected document chain.

T01 registers twelve `workforce.*` keys as `planned`, `shadow` and
`is_assignable=false`. The complete nine-role matrix is seeded. Admin alone has
a future template ceiling, but these rows are not authorization consumers.
Exact Admin is checked directly by every T01 public RPC as the temporary legacy
authority.

No route, sidebar item, provider/controller or action surface is added in T01.

T02 does not change that rollout boundary. All twelve capability rows remain
planned, shadow and nonassignable. Exact Admin remains the temporary audited
authority for the new protected configuration RPCs.

## Protected RPCs

- `v1_get_workforce_foundation`
- `v1_save_workforce_trade`
- `v1_save_workforce_internal_location`
- `v1_save_workforce_worker`
- `v1_save_workforce_team`
- `v1_save_workforce_worker_assignment`
- `v1_save_workforce_responsibility_assignment`
- `v1_get_workforce_configuration`
- `v1_save_workforce_calendar`
- `v1_save_workforce_calendar_date`
- `v1_save_workforce_shift_template`
- `v1_save_workforce_team_schedule`
- `v1_get_workforce_attendance`
- `v1_save_workforce_attendance_day`
- `v1_get_workforce_timesheet_allocations`
- `v1_save_workforce_timesheet_allocations`
- `v1_withdraw_workforce_timesheet_allocations`
- `v1_get_workforce_daily_roster`
- `v1_save_workforce_daily_roster`

Flutter uses typed schema-v1 projections through
`YorksSupabaseWorkforceRepository`. The repository fails closed when the flag
is off, connectivity is unavailable, the RPC client is absent or the server
shape is malformed.

## T02 calendars and shift configuration

T02 adds five private normalized relations:

| Relation | Purpose |
|---|---|
| `v1_workforce_calendars` | Effective calendar versions with IANA timezone, standard scheduled minutes and break minutes |
| `v1_workforce_calendar_weekdays` | Exactly seven ISO weekday rows per calendar version, each regular or weekly off |
| `v1_workforce_calendar_dates` | One dated holiday, closure, Ramadan or other override per calendar/date |
| `v1_workforce_shift_templates` | Effective reusable normal-site, warehouse, workshop, Ramadan, night or other shift versions |
| `v1_workforce_team_schedule_links` | Non-overlapping dated team defaults linked to exact calendar and optional shift versions |

Calendar day types remain distinct from later attendance statuses. The exact
day types are `regular_working_day`, `weekly_off`, `public_holiday`,
`site_closed` and `not_scheduled`. Recurring weekdays use only regular working
day or weekly off; dated exceptions own holidays, closures, Ramadan changes
and other overrides. Non-working day types carry zero scheduled and break
minutes. Ramadan overrides remain regular working days with explicit reduced
minutes.

Calendar timezone names must resolve through the server timezone catalogue.
Scheduled and break minutes are integers, non-negative where applicable and
cannot sum beyond 1,440 minutes. Effective versions of the same calendar or
shift code cannot overlap. A team has at most one effective schedule default
on a date, and every link must fit inside the retained team, calendar and shift
windows. Parent window edits fail closed rather than stranding existing links
or dated overrides.

The additive correction migration
`20260830042048_yorks_workforce_t02_retained_version_semantics.sql` closes the
retained-ID drift path left by the initial T02 save RPCs. Once referenced, a
calendar's code, timezone, minutes, effective dates and seven weekday meanings,
and a shift's code, kind, times, minutes and effective dates cannot change in
place. Display names remain presentation-only. Semantic changes use a new
non-overlapping version.

An already-effective team default and every field of a past/current dated
override, including `is_active`, cannot be rewritten. Future links and
overrides are editable with optimistic versions only while they remain future
drafts. A calendar or shift parent with only expired references may be marked
inactive without deleting or hiding its retained row; a past/current override
has no in-place retirement path. Current or future use blocks parent
retirement. These guards execute at the table-trigger boundary as well as
through the trusted RPC transaction.

Correction migration
`20260830044311_yorks_workforce_t02_calendar_local_history_guards.sql`
derives every effective, past/current and retirement boundary from one
captured `clock_timestamp()` in the exact referenced calendar's IANA timezone.
The database session timezone and session `current_date` have no authority over
historical configuration.

Shift start/end values are optional supporting data and must be supplied as a
pair when used. An end time earlier than the start time is a cross-midnight
shift. Its later attendance `work_date` is always the shift start date in the
linked calendar timezone. T02 creates no daily attendance or timesheet facts.

All five relations use RLS, revoke authenticated direct CRUD, grant direct
table access only to `service_role`, reject hard deletion and mutate only
through exact-Admin, optimistic-versioned, idempotent and audited RPCs.

## T03 daily attendance authority

T03 adds one private `v1_workforce_attendance_days` relation with a unique
worker/work-date key. Attendance status is distinct from calendar day type and
is limited to `present`, `absent`, `annual_leave`, `sick_leave`,
`official_leave`, `unpaid_leave` and `not_entered`. Regular and overtime values
are integer minutes; both are non-negative, each is at most 1,440 and their sum
is at most 1,440. Present requires a positive total. Every other status carries
zero minutes. T03 contains no pay calculation or partial-day absence split.

On creation the server locks the worker/date path, validates active employment,
resolves the effective temporary-over-primary assignment, resolves the exact
team schedule in the calendar timezone and retains the complete assignment,
responsibility, calendar, optional shift and day-type snapshot. Dated calendar
overrides win over recurring weekdays; an override shift wins over the team
default shift. No effective assignment, team schedule or resolvable day causes
the command to fail closed. Cross-midnight work remains attributed to the shift
start date.

A later optimistic correction may change only attendance status, minutes and
reason. It never refreshes the retained context from mutable parents. A worker
who became inactive, suspended or left after the day was created does not by
itself block that controlled historical correction. The correcting actor must
still be active and authorized, and every correction is append-only audited.

T03 promotes only `workforce.view` and
`workforce.attendance.maintain` to operational, enforced and assignable.
Non-Admin access requires an effective capability grant plus a dated Workforce
responsibility matching the worker and retained scope. Exact active Admin keeps
audited organization authority. The other ten capability rows remain planned,
shadow and nonassignable. No role, technical project membership or client-
supplied context substitutes for that server resolution.

The schema-v1 read projection returns only days within the caller's authorized
scope. The save command accepts only `worker_id`, `work_date`, status, integer
minutes and reason, and uses expected version plus UUID idempotency. The table
uses RLS, revokes authenticated direct CRUD, permits direct administration only
to `service_role` and rejects hard deletion.

The product owner resolved the source's future-date silence on 30 August 2026:
all future attendance is denied. Creation and versioned correction compare the
work date with `clock_timestamp()` in the exact retained calendar IANA
timezone, never the database session timezone or client clock. New rows use the
server-resolved schedule timezone; existing rows use their retained timezone
snapshot. Any pre-existing future row remains readable and preserved but is
read-only until its calendar-local work date arrives; the correction does not
delete, rewrite or rebase it.

## T04 daily allocation authority

T04 adds a one-per-attendance allocation-set root, immutable revision headers
and immutable allocation rows. One present attendance day may have multiple
allocations in its current active revision. The separate regular and overtime
minute sums must equal the parent day exactly, and each integer total remains
inside the accepted 1,440-minute day bound. Absent, leave and not-entered days
cannot own active work allocations.

The two target shapes are mutually exclusive. Project work records an active
selected project and one active Building/Common scope belonging to it.
Internal Yorks work records one active internal location and snapshots that
location's Department/Cost Centre meaning. A worker assignment supplies
retained authorization context only; it never silently selects the work
target. Rows retain target IDs, names/codes/versions, optional activity and
notes, integer minutes and actor/revision evidence, with no pay/cost fields.

Optional start/end values are supporting time evidence. They must be paired
and form a half-open interval in the parent's retained IANA calendar timezone.
The parent `work_date` is the retained shift-start date: on a cross-midnight
shift, a supplied start earlier than the retained shift start belongs to the
following local date. An end earlier than that resolved start time advances
once more to the following local date, an equal start/end is invalid, adjacent
intervals are valid and overlaps are rejected. Interval duration does not
synthesize authoritative minutes.

Every save locks the T03 worker/date path, validates the exact attendance
version, appends one immutable active revision plus immutable rows, advances
only the root pointer/version, stores UUID idempotency and emits one audit
effect. An active set blocks any T03 attendance correction. The separate
timesheet-authorized withdrawal command appends a zero-line immutable revision
without altering attendance; only then may an attendance maintainer correct the
parent before a new active allocation revision is saved.

T04 promotes only `workforce.timesheets.maintain`. Non-Admin calls require an
effective capability and dated responsibility over the retained worker context
and effective capability plus explicit dated responsibility over every target.
Worker/team responsibility alone cannot authorize an unrelated target. Exact
active Admin keeps audited organization authority. The remaining nine
Workforce keys stay planned, shadow and nonassignable.

## T05 Supervisor Daily Roster authority

Migration `20260830101500_yorks_workforce_t05_supervisor_daily_roster.sql`
composes the accepted T03 attendance and T04 allocation commands; it does not
create a fourth capability. `v1_get_workforce_daily_roster` projects assigned
workers for one date, including missing attendance rows and schedule-only
suggestions, without creating a fact. Rows, selectors and command flags are
derived only from the caller's effective `workforce.view`, dated Workforce
responsibility and target authorization. Future dates remain readable but
non-actionable, and an empty authorized result is conservatively non-actionable
without consulting the database session `current_date`.

`v1_save_workforce_daily_roster` accepts one explicit, allowlisted row per
worker and atomically composes attendance plus `preserve`, `replace` or
`withdraw` allocation intent. It sorts and locks the canonical worker/date
advisory keys, checks every row before committing, requires per-row expected
versions, uses one root UUID idempotency key plus deterministic child keys, and
emits a root audit. `replace` and `withdraw` require the exact allocation-set
version. `preserve` may omit that version only for attendance-only evidence
when allocation details are authority-restricted; supplied versions are still
validated, attendance totals cannot change under a live allocation lock, and
no allocation revision is removed or inferred. Restricted save responses emit
no allocation set, identifier, version or state.

Corrective migration
`20260830111341_fix_workforce_t05_roster_authority_aggregation_bounds.sql`
keeps schema version 1 but makes `allocation_targets` mandatory and distinct
from read-only `selectors`. Filter selectors come only from view-authorized
worker assignments; project-scope and internal-location allocation targets
come only from active target shapes with exact dated
`workforce.timesheets.maintain` target authority. A worker/team responsibility
alone therefore exposes no command target. An active set with any unauthorized
current target removes that row's timesheet-maintain flag, and the aggregate
flag is derived from those corrected returned rows. `is_future` is true only
when every row in the returned page is future in its own retained calendar
timezone; an empty result stays conservatively true and non-actionable. Read `limit` and
`offset` are echoed in `filters`; read pages and atomic saves are both bounded
to 500 explicit rows.

T05 adds nullable `overtime_reason` as optional attendance evidence. Blank text
normalizes to null and supplied text is limited to 2,000 characters. Positive
overtime does not require the field, and it carries no threshold, payroll,
payment, approval or attachment semantics. The accepted T03 six-key public
payload remains unchanged; only the T05 roster composition round-trips this
evidence. T05 also guards the common T04 revision-insert boundary, so both save
and withdraw reject retained future attendance rows in the exact retained
calendar timezone.

The Flutter boundary exposes this authority only behind the default-off
`YORKS_V1_WORKFORCE` flag and a server-confirmed `workforce.view` permission
snapshot. Widget calls flow through the Riverpod controller and strict
repository; no widget calls Supabase. Review, bulk actions and Copy Previous
Day remain local draft transformations until explicit Save Day. Capability or
identity loss purges the protected projection and draft. Desktop uses the
sticky Worker/header roster with local grid scrolling and full keyboard
operation. A 360-pixel viewport is deliberately read-only; tablet/mobile
editing remains later-phase work.

## T06 Monthly Period and Validation authority

T06 identifies one controlled period by an exact Workforce team and the first
date of one Gregorian month. It does not use supervisor, project, scope or
location as alternate period identities because the approved source requires
one period to retain mid-month assignment and supervisor changes. Opening the
Monthly view returns either an authorized absent-period state or the current
projection and never creates a period.

`v1_validate_workforce_monthly_period` is the single explicit initialization/
revalidation boundary. It locks the team/month path, accepts no worker/date or
total input, uses expected period version plus UUID idempotency and appends an
immutable validation run. Each run owns immutable period-worker summaries,
worker/date evidence and stable typed issues. Only the period's current-run
pointer, derived status, version and update attribution advance. Earlier runs
are neither updated nor deleted.

Membership is one canonical retained/prospective union. A worker/date with a
T03 attendance fact is attributed from that row's retained worker, assignment,
team, supervisor, calendar and day-type snapshots. A later T01 assignment edit
cannot remove the date from its original team or move it into a replacement
team. Only dates without attendance use the accepted temporary-over-primary
effective-assignment resolver, and the branches are mutually exclusive per
worker/date. The current T04 allocation remains attached to its exact
attendance day. Source fingerprinting, authorization, summaries and drill-down
all consume this same source. Period and worker totals are calculated only from
those facts. A date is future only according to `clock_timestamp()` in that
exact effective or retained calendar IANA timezone; future membership is
visible but excluded
from scheduled/missing totals and issues. Preserved legacy future attendance
or allocation evidence remains visible on its retained day, while its regular,
overtime and allocation minutes are excluded from authoritative worker/period
totals until that calendar-local date arrives and explicit revalidation
captures the changed future fingerprint. A missing schedule/calendar is a
blocking configuration issue and never falls back to session or client time.

The team selector, absent-period read and validation command share one private
team-month applicability predicate. Current team validity overlap, retained T03
attendance assigned to that team/month, or an already-retained monthly period
is sufficient to keep the team-month reachable. This only preserves evidence;
it grants no authority. Existing exact capability, dated responsibility and
allocation-target coverage must still authorize the complete canonical source.
A non-effective team with no retained attendance and no period stays hidden and
cannot be initialized.

The persisted run status and effective projection are limited to `draft` and
`ready_for_review`. Any blocking issue yields `draft`. The server stores a
source fingerprint over the exact worker/date facts; a changed fingerprint
after validation makes the projection stale/effectively `draft` until another
explicit run succeeds. Warnings remain visible but T06 has no acknowledgement
or submission action.

Blocking codes cover applicable required-date gaps, not-entered required days,
attendance/minute contradictions, allocation mismatch/overlap, over-1,440
minutes and employment/worker/assignment/supervisor/target invalidity. A
caller's own authority loss is a fail-closed RPC denial and is
never persisted as a partial validation issue. `validation_stale` is a
deterministic read projection over the immutable current run, not retained
history. Warning codes cover non-working-day work, below-standard minutes,
mid-month assignment/supervisor change, missing
activity, off-assignment allocation and backdated evidence. Accepted T03/T04
constraints remain the write authority; T06 reports but never repairs them.
There is no configured overtime ceiling or mandatory overtime-reason/document
policy, so T06 does not invent one.

Later mutable parent state is not historical evidence. A retained T03 worker
status and supervisor identity, plus retained T04 project/scope/internal-
location identity, remain valid after a later worker status change, supervisor
deactivation or target closure. Prospective dates still fail closed on a
current inactive/suspended worker or inactive supervisor. A legitimate
`left_company` worker remains applicable through the retained leaving date and
assignment window. A missing supervisor ID is structurally invalid for both
branches. Because T03 did not retain dated supervisor-active history, T06 does
not invent a retroactive inactive fact for a non-null retained supervisor.
Structurally invalid assignment windows and attendance outside retained
joining/leaving dates remain blocking.

Read authority is exact active Admin or `workforce.view` plus dated
responsibility covering the complete team-month worker/date set. Validation
also requires `workforce.timesheets.maintain` over every worker/date and every
active allocation target. A partial/redacted monthly total is never labelled
authoritative. T06 promotes no review, correction, verify, final-approve or
reopen capability.

The strict schema-v1 Flutter boundary is Widget to Riverpod controller to
repository to the protected projection/command. The guarded desktop Monthly
view shows the period summary, paged worker summaries, compact calendar, daily
drill-down and exception-first filters. It contains no Submit button. The
360x800 boundary is deliberately read-only and overflow-free, and the tracked
flag remains default-off.

## T07 review and approval lifecycle

T07 adds a non-mutating monthly approval queue and lifecycle projection plus
trusted commands for Submit, Return for Correction, controlled reviewer
correction, Verify & Forward, atomic Approve & Lock, Request Reopen and
Authorize Reopen. The server response alone determines which action is shown;
role labels and client-side hiding are not authority.

Submission binds one current T06 validation run and source fingerprint to an
approval revision. It rejects blockers, staleness and anything other than the
exact complete warning-ID acknowledgement set. Return and reopen retain exact
worker/date edit scopes. Reviewer correction calls the accepted T03/T04 writer
inside a server-only transaction context and appends before/after evidence;
ordinary attendance/allocation writers cannot bypass the period guard.

Verify & Forward and final approval require separate actors from the submitter,
and the final approver must also differ from every actor who returned, corrected
or verified that approval revision. Approve & Lock atomically creates an
immutable, hashed server snapshot. Reopening keeps
that snapshot readable, requires a separate requester and authorizer, advances
the approval revision and requires validation/submission/review/approval again.
No read creates or advances lifecycle state.

Flutter keeps T07 behind `YORKS_V1_WORKFORCE` and the server-returned action
flags. Desktop has queue, status, timeline and explicit actions; 360x800 is
read-only. The isolated T07 repository/controller boundary fails closed for
flag-off, offline, missing backend, denied, stale, malformed and uncertain
responses and purges protected lifecycle state when authority is lost.

## T08 Discussion, Evidence and Notifications

T08 maps each retained monthly period to at most one canonical Team Chat group
conversation. Opening it is explicit and UUID-idempotent; reads do not create
it. Effective participants are synchronized from exact active identity,
`workforce.view`, the applicable accepted T07 action capability and complete
dated responsibility. Canonical reply, mention, attachment, edit/delete and
delivery/read behavior is retained. A stale member row is never authority and
comment text never advances a period.

Each accepted T07 audit transition adds one immutable system message linked to
the source audit ID. Lifecycle recipients are derived from the next required
capability and dated responsibility, then delivered through the existing
durable Notifications and push-outbox path. Explicit Admin-only daily missing
attendance and monthly incomplete digest commands are idempotent and audited;
the daily command consumes the complete paged roster, including teams above
500 workers. Push-disabled policy suppresses only transport jobs while the
durable in-app notification remains. No scheduler or cadence is invented.

Workforce evidence uses the existing immutable Documents prepare/upload/
finalize/version pipeline and `operational` classification. The exact supported
types are medical certificate, leave document, overtime authorization, worker
transfer note, site attendance sheet, daily supporting photo, monthly
timesheet attachment and other Workforce document. Server authorization binds
each version to an authorized Worker, retained Attendance Day or Monthly
Period. Historical versions remain readable under current entity authority;
object-path knowledge never grants download. Canonical target identity drives
all optional links: day/worker links must agree and period links must exist in
the exact current retained validation source before any upload side effect.
Secondary-link authority alone cannot read or download the document.

Flutter keeps a separate schema-v1 repository/controller boundary behind
`YORKS_V1_WORKFORCE`, purges protected collaboration state on identity or
capability loss and never calls Supabase from a widget. The Monthly desktop
view supports opening/replying and controlled evidence upload; 360x800 shows a
read-only, overflow-free count summary. T08 adds no T09 report/export, T10
dashboard, tablet/mobile editor, legacy migration, flag enablement or release.

## Data preservation and rollback

The T01 through T08 migrations and corrective migrations are additive.
Rollback is
non-destructive:

1. keep `YORKS_V1_WORKFORCE=false`;
2. revoke authenticated execution on the Workforce public RPCs if a
   server rollback is required;
3. return the two T03 consumers and T04 timesheet consumer to
   planned/shadow/nonassignable;
4. retain every normalized row, audit event and idempotency record; and
5. ship a forward corrective migration rather than dropping relations or
   reinterpreting legacy data.

No production migration, flag enablement or legacy-data backfill is part of
this T08 slice.

## Acceptance evidence required

T01 is acceptable only when:

- the full migration chain resets successfully;
- focused and complete pgTAP suites pass;
- all six relations prove RLS and no authenticated SELECT, INSERT, UPDATE or
  DELETE privileges;
- Site Engineer, Project Engineer and Procurement public RPC calls fail even
  when a future responsibility scope exists;
- independent worker identity, retry safety, stale-version rejection,
  assignment precedence, overlap rejection, finite parent-window enforcement,
  worker-date history preservation, active-project enforcement, responsibility
  resolution, hard-delete rejection and single audit emission are tested;
- focused Flutter model/repository and feature-flag tests pass;
- analyzer and applicable release builds pass; and
- any unrelated global-suite or platform limitation is reported separately.

## T03 acceptance evidence required

T03 is acceptable only when clean focused and complete database gates prove
the private-table ACL/RLS boundary, exact worker/date uniqueness, employment
and status/minute rules, exact retained context, scoped Admin/maintainer access,
unscoped and inactive/revoked/expired denial, optimistic conflict, retry and
competing-writer behavior, one audit effect and no hard delete. Focused Flutter
tests must prove strict schema-v1 decoding, exact RPC parameters and flag-off,
offline, missing-backend, denied, stale and malformed failures.

Run the real two-session local concurrency proof with:

```bash
./tool/test_workforce_t03_concurrency.sh
```

The harness refuses a non-loopback Supabase database, resets only the
repository-local stack, installs committed disposable fixtures, holds the
worker/date advisory key as a barrier, and proves that two independent `psql`
sessions are simultaneously waiting inside the save RPC. It runs both a create
race and a same-version correction race. The expected final line is
`Workforce T03 local concurrency harness: PASS`; each race must produce one
commit, one stable `40001` conflict, one authoritative row/version and one audit
effect. Re-running the command begins with a deterministic local reset.

## T04 acceptance evidence required

T04 is acceptable only when the private root/revision/row ACL and RLS boundary,
explicit target shapes, exact split minute reconciliation, calendar-local
paired/non-overlapping intervals, retained target snapshots, active-child
attendance guard, withdrawal release, scoped worker-plus-target authority,
optimistic conflict, retry, no-hard-delete and strict schema-v1 decoding all
pass focused and complete gates.

Run the real two-session allocation-set race with:

```bash
./tool/test_workforce_t04_concurrency.sh
```

The harness must refuse non-loopback databases and prove one writer advances a
shared set while the same-version loser receives the stable conflict, with one
authoritative revision and no duplicate audit/idempotency effect.

The harness intentionally leaves its valid local `593*` rows in place. The
focused T01-T04 pgTAP files and then the complete database suite must be run
again without a reset, following the exact order in
`TEST_AND_ACCEPTANCE_PLAN.md` section 9K. T04 pgTAP data assertions are
fixture-scoped to the `592*` allocation set and must never depend on otherwise
empty Workforce relations.

## T05 acceptance evidence required

T05 remains local and unaccepted until clean migration-chain parsing plus the
focused T03-T05 pgTAP regression and the remaining application gates complete.
The T05 suite must prove no new capability, internal
helper ACLs, read-without-create, missing-row schedule suggestions, strict row
allowlists, atomic multi-row failure, future-date denial, T04 save/withdraw
future guards, idempotency, stale versions, no silent allocation loss, and
role-safe target redaction. Unscoped Project Engineer, Site Engineer and
Procurement calls must return no rows, selectors or action flags;
capability-without-responsibility, revoked/expired authority, banned identity
and uncovered allocation targets must fail closed. A restricted attendance
maintainer must be able to update optional overtime evidence with `preserve`
and a null hidden allocation version while the immutable allocation history is
unchanged and the response contains no partial allocation identifiers.

The real two-session proof is:

```bash
./tool/test_workforce_t05_roster_concurrency.sh
```

It refuses non-loopback databases, resets the repository-local stack, retains
only `595*` fixtures, holds the canonical worker/date advisory lock and proves
two independent roster RPC sessions wait together. Both the create and
same-version correction races must produce one commit, one stable `40001`
loser, one authoritative version and one root audit/idempotency effect. Run the
fixture-scoped T05 pgTAP again without a reset; its `594*` assertions must pass
with the retained `595*` roster row present.

Focused Flutter acceptance covers strict flag/offline/backend/permission/
conflict/malformed mapping, protected-state purge, bulk/copy/review/save draft
transitions, mixed attendance/timesheet authority, hidden allocation
preservation, keyboard/focus/semantics and English/RTL layouts at 1440x900,
1366x768, 1024x768 and the read-only 360x800 boundary.

## T08 acceptance evidence required

T08 remains local and awaits independent acceptance until clean focused and
complete database gates prove private relation ACL/RLS, dynamic participant and
entity scope, Chat lifecycle reuse, source-audit system-event deduplication,
notification recipient/outbox preference behavior, immutable document versions,
object-path denial, digest idempotency and no workflow mutation from comment
text. Strict Flutter tests must prove schema/context mapping, flag/offline/
backend/denied/malformed/uncertain failures, capability-loss purge, desktop
interaction and the read-only compact/RTL boundary. Analyzer, format, diff,
advisors and production-shaped flag-off builds remain required.

## T09 protected Excel and PDF reports

T09 is an online-only report consumer beneath the accepted T01-T08 authority.
It promotes only `workforce.reports.export` and requires it together with
`workforce.view`, an exact active identity and complete dated Workforce
responsibility for every retained worker and allocation target in the result.
Role labels, technical project membership, email, guessed IDs and Admin status
are not substitutes for either capability or responsibility.

The protected report families are Daily Attendance Register; Worker Monthly
Timesheet; Supervisor Team Monthly; Project Workforce; Company Workforce
Summary; and the Missing Attendance, High Overtime, Returned Timesheets,
Unsubmitted Periods, Workers Without Assignment, Overlapping Allocations and
Reopened Periods exception registers. Monthly final reports select one exact
immutable T07 approved snapshot ID/revision/hash. Reopening or editing the
current period never rewrites an older report source. Daily and exception
registers explicitly carry current/source status, source version and the
server generation timestamp; they are not labelled approved. Daily Attendance
Register rejects a future calendar-local work date. Exception registers are
organization-scope outputs in T09; a client-supplied project/team/worker scope
is rejected instead of being ignored or broadening the result.

Worker, Team and Project final-report scope is verified against the retained
approved payload before generation: the worker must occur in its retained
dates, the Team must equal the exact snapshot period team, and the Project
must occur as a retained allocation target. A requested month, when supplied,
must equal the immutable snapshot month. Forged or irrelevant scope IDs fail
closed and cannot create an empty but misleading issued artifact.

The server creates one immutable schema-v1 report artifact descriptor and
sanitized report payload per actor/idempotency key. The payload omits internal
UUID columns and all wage, salary, pay, bank, commercial and unrelated-module
data. Same-key/same-payload returns the same artifact; a different payload
fails. Pay and passport data exist only in the separate
[Worker Records](WORKER_RECORDS.md) relations, which no Workforce projection
or report reads. Every successful first generation appends exactly one
`report_generated` audit event. Preview, Download, Share and Print are explicit
online issuance actions: before the cached bytes are used, the client submits
the artifact ID, format and action to the idempotent issuance RPC. The server
reauthorizes the exact artifact and appends exactly one
`workforce_export_generated` event containing source/payload hashes, actor
role, capability, scope and server time. Same-key/same-payload returns the same
receipt; a different payload fails. The private artifact ledger retains the exact daily
authority projection, or the approved-snapshot links/exception month needed
to re-check current access. Report history is hidden immediately when the
actor loses any required capability or dated responsibility; this protected
authority evidence never appears in the user-visible payload or export.

XLSX and PDF bytes are deterministic clients of that immutable payload. XLSX
uses the existing pure-Dart OOXML engine with text worker numbers, true date
and numeric minute/hour cells, frozen header/identity panes, filters and
formula-prefix neutralization. PDF Preview, Download and Print reuse the same
cached bytes; printing never rebuilds from mutable rows. PDF pages repeat
headers and include the legal English/configured secondary company name,
report identity, exact approval revision where applicable, prepared/reviewed/
approved actors and server dates, and page numbering. Approved monthly headers
show both legal company names, `MONTHLY TIMESHEET`, and Month/Year. The footer
shows Prepared By, Reviewed By, Approved By, server approval dates, revision
and page number. Worker/team monthly reports use A4 landscape;
project/company layouts select portrait or landscape from their controlled
column set. Preview/Download/Share/Print reuse the same cached PDF bytes after
their respective server-confirmed issuance receipt.

Controlled output fields are not generic placeholders. Daily exports separate
Worker, Worker Number, Trade, Status, Regular Hours, OT, Project, Building,
Internal Location, Supervisor and Notes. Worker Monthly retains each daily
status, hours, projects/buildings/locations, activities, supervisor, reviewer,
approver and approval dates. Team reports expose workers managed, attendance,
regular/OT, absences, projects, exceptions and review/approval status. Project
reports expose project/building, worker/trade distribution, man-hours,
man-days, regular/OT, absences, supervisors and outstanding periods. Company
reports expose active workforce, attendance completion, approved regular/OT,
absence position, project allocation, pending submission/approval and reopened
period counts.

Derived man-days are calculated server-side as the sum, for each approved
date, of total approved work minutes divided by that date's retained positive
standard scheduled minutes. Dates without a positive retained denominator do
not invent a man-day and remain explicit in detail/exception output. Overtime
is reported separately and is not a payroll calculation. Because no overtime
ceiling is approved, High Overtime is derived only from retained typed
`overtime_limit_exceeded` evidence when such configured evidence exists; T09
does not invent a threshold. In the current unconfigured state, the report
returns an explicit typed `not_configured` row rather than an empty result.

The existing Monthly Reports surface exposes format/report/snapshot/scope
selection, generation history and explicit Preview/Download/Print states.
Desktop is optimized at 1440x900, 1366x768 and 1024x768. The 360x800 boundary
is a deliberate read-only history/availability summary with no compressed
desktop report editor. English, Arabic, Urdu and Hindi copy remain localized;
Arabic/Urdu output is RTL-safe. T09 creates no dashboard, approval transition,
worker self-service route, tablet/mobile editor, legacy migration, flag
enablement or deployment.

## Later phases

## T10 Admin and management dashboards

T10 is a read-only schema-v1 projection over accepted T01-T09 facts. It has
three explicit shapes: Supervisor, Project/Management and Admin. Every response
includes a server timestamp, source version, authorization mode and explicit
calendar-local as-of groups. A mixed-timezone response never advertises one
invented organization date.

Supervisor counts cover only workers effectively assigned to an authorized
team on that team's calendar-local date. Today Completion is entered
attendance other than `not_entered` divided by applicable roster workers.
Current Month Completion is entered required worker-days through each retained
calendar-local today divided by required worker-days through that date. Leave
is the exact union of annual, sick, official and unpaid leave. Warnings and
returned corrections are current retained month evidence. The action to finish
today's attendance is exposed only with exact attendance-maintain authority for
the complete team/date scope.

Management counts cover only completely authorized project/team periods and
their retained worker and allocation targets. Review queue rows are exception
first and expose submitter, team, month, worker count, regular/overtime minutes,
warnings and reviewer corrections. Full review/approval counts are calculated
before the compact visible limit, and an older higher-priority exception sorts
ahead of newer normal rows. Retained queue/history remains visible when its
team, project, scope or internal location later closes or its worker leaves.
The Current Active Projects list alone applies current project state and is
derived from actual current assignment/allocation targets, never editable team
defaults. Missing Supporting Evidence and High
Overtime are populated only from retained typed validation evidence. With no
approved evidence requirement or overtime ceiling they return zero together
with `not_configured`; no threshold or mandatory document rule is invented.

Admin counts are organization summaries: active workers/supervisors, missing
today across every team's exact local date, monthly pending, returned, awaiting
final approval, locked, open reopen requests and configuration issues. Admin
does not receive every daily row. Later worker status or project/scope/location
closure never retroactively invalidates an accepted retained attendance or
allocation snapshot. Prospective missing counts continue to use dated current
assignment/calendar authority.

All three shapes require an active exact identity, `workforce.view` and dated
responsibility/capability coverage. Admin organization access still requires
the effective capability plus organization responsibility. Management roles
select a presentation shape only; role labels, technical membership, email and
guessed IDs grant nothing. Configuration issues use stable issue-code/team
identities across current and retained evidence. Action booleans are separately
derived from the exact T03-T07 command capability and complete retained target
responsibility. Reads append no audit, notification, export, report or workflow
effect. Flutter uses Widget -> Riverpod controller -> repository ->
trusted RPC, fails closed on authority/backend/malformed responses and marks a
last-confirmed projection stale instead of presenting it as live.

The desktop Overview is responsive at 1440x900, 1366x768 and 1024x768. At
360x800 it is a deliberate read-only, overflow-free summary. English, Arabic,
Urdu and Hindi copy remains localized and RTL-safe. T10 adds no T11 editor,
report generation/issuance call, lifecycle mutation, feature enablement,
remote migration or deployment.

## T11 Tablet attendance and review

T11 is a presentation-only adaptation of the accepted T05 daily-roster and
T07 monthly-review surfaces. It does not add a database relation, migration,
RPC, capability, route or lifecycle transition. Every read and mutation still
passes through the existing Widget -> Riverpod controller -> repository ->
trusted RPC boundary, and every action remains constrained by the exact
server-returned capability/responsibility/target flags.

The existing compact boundary below 720 logical pixels remains deliberately
read-only for T12. From 720 through 1199 logical pixels, landscape attendance
uses a bounded master roster and one selected worker/day detail editor;
portrait attendance uses a focused single-column roster and one selected-row
modal editor. A sticky completion footer exposes only the accepted Review Day,
Back to Edit and Save Day operations. Opening, selecting or editing never
creates a server fact; explicit online Save remains the transaction boundary.
The tablet layout creates controllers only for the active row rather than for
the complete roster.

Tablet review is exception-first, keeps period and selected-worker detail in a
master/detail or focused-sheet hierarchy, and renders Return, Correct, Verify,
Approve and Reopen only from the accepted T07 action flags. Offline, loading,
empty, denied, stale, conflict, uncertain and saved states remain explicit.
Action targets are at least 44 by 44 logical pixels, keyboard/focus traversal
and semantic labels are preserved, reduced-motion suppresses nonessential
sheet transition motion, and English, Arabic, Urdu and Hindi remain localized
with direction-aware Arabic/Urdu layouts.

T11 preserves the accepted desktop layouts at 1200 logical pixels and above
and establishes the 720–1199 tablet boundary. It adds no phone editor,
attendance import, exception bulk flow, legacy migration, feature enablement,
commit, push, remote migration or deployment.

## T12 Mobile attendance

T12 is a presentation-only phone adaptation of the accepted T05 daily-roster
authority. Widths below 720 logical pixels show a purpose-built Today’s Team
workflow rather than a squeezed spreadsheet. Worker cards show identity,
explicit attendance text, regular/overtime time and authorized retained target
summary. A tap opens exactly one focused worker editor with status, minute
controls, an authorized target picker, activity/exception evidence and the
accepted standard-minute prefill. Restricted allocation detail remains
redacted and neither role labels nor client inference creates edit authority.

Phone bulk actions are local draft transformations shown in a bottom sheet
with the affected count. Date selection is native and future work dates remain
denied by the accepted calendar-timezone server boundary; the client also
avoids offering a future date as a convenience but never becomes authority.
A sticky completion footer exposes only Review Day, Back to Edit and Save Day.
Opening, selecting, editing, bulk applying or reviewing creates no server fact;
only explicit online Save delegates to the accepted T05 atomic command.
Offline drafts, conflicts, stale/uncertain outcomes and denied authority never
present server success, and protected state is purged by the existing guarded
controller boundary.

The phone layout is accepted at 360x800 and 390x844 with safe-area/keyboard
insets, 44x44 actions, text scaling, visible focus, semantic labels, reduced
motion and English/Arabic/Urdu/Hindi localization. Arabic and Urdu are
direction-aware. T12 preserves accepted tablet and desktop behavior and adds
no migration, RPC, capability, route, lifecycle state, attendance import,
legacy migration, flag enablement, commit, push, remote migration or
deployment.

## T13 Security, concurrency, accessibility and performance hardening

T13 audits the complete accepted T01–T12 module without adding product scope.
The database lane inventories every Workforce table, policy, grant, trusted
function, public command and Storage/document seam; proves direct table/helper
denial and intended RPC execution; reruns the genuine independent-session
mutation races; and verifies that stable idempotency, stale-conflict and audit
effects remain atomic. A reproduced defect is corrected narrowly and
forward-safely; otherwise T13 adds only repeatable evidence.

The performance lane retains the accepted 500-worker/15,500-date validation
fixture and exercises the 50-team/30-project, multiple-allocation and retained
two-year-history paths where practical. It records local wall time/query plans,
pagination and bounded-controller evidence without inventing an unapproved
production SLA. The client lane rechecks every Workforce surface across the
nine approved viewports, four supported languages, RTL, text scaling,
keyboard/focus, semantics, reduced motion, 44x44 actions, non-color cues and
all loading/empty/error/permission/offline/conflict/uncertain states.

The T13 audit reproduced repeated per-team assignment and authorization scans
in T10 overview/queue reads. Additive migration
`20260831090940_yorks_workforce_t13_query_performance.sql` preserves the exact
temporary-before-primary assignment result and scoped authorization fallback,
but resolves prospective monthly membership and current team contexts
set-wise and short-circuits only complete organization capability plus
organization responsibility. It writes no business row and changes no RPC
shape, lifecycle state or capability. The local 500-worker/50-team/30-project,
24-month fixture reduced isolated overview wall time from about 29.06 seconds
to 4.99–5.31 seconds and queue wall time from about 11.91 seconds to
1.73–2.23 seconds; retained-suite runs recorded about 7.16–7.35 seconds and
2.72–2.81 seconds respectively. These are local observations, not a product
SLA.

Independent T13 review also reproduced the retained T07 Admin role shortcut.
The same additive migration now defines T07 and T10 period authority
separately and role-neutrally: Admin, Project Manager, Senior Mechanical
Engineer and every other exact role require effective capability plus dated
responsibility. Organization authority covers a month only when its window
covers that complete month; otherwise retained assignments and every active
allocation target are checked individually. Empty periods remain authorized
only by complete organization or exact team-month responsibility. No retained
period, lifecycle, allocation or audit fact is rewritten.

T13 kept `YORKS_V1_WORKFORCE` default-off and performed no commit, push, remote
migration, flag enablement, deployment or production action. The product owner
initially waived T14 dedicated staging UAT, so T14 remained **not performed and
not passed** at T13 acceptance. Later on 31 August 2026 the product owner
withdrew that waiver. T14 is now mandatory and its pass cannot be inferred from
T13 automation.

## T14 dedicated staging UAT

T14 uses one immutable candidate source and artifact, a dedicated
non-production Supabase project, an unaliased/non-production web deployment,
`YORKS_V1_WORKFORCE=true` and named non-production personas. The complete
35-scenario chain in the approved Workforce source must be exercised against
that same candidate, including exact capability plus dated responsibility and
allocation-target authority, the frozen future-work-date denial, lifecycle
separation, collaboration/evidence/notifications, protected Excel/PDF
issuance, dashboards, responsive/localized states and unrelated-module
regression. Opening a roster or reading a period must not create facts.

Automation is necessary but cannot replace the required human witness for the
daily roster, review/return/correction/verification/approval/reopen chain,
responsive interaction, document bytes and print/preview consistency. A pass
requires named witnesses, timestamps, screenshots/logs, candidate and artifact
hashes, staging backend identity without secrets, migration ledger evidence and
zero open P0/P1 defects.

That initial preflight was later resolved only for infrastructure: dedicated
Frankfurt project `iqltcyimlqtcwyzlemwx` and ignored local staging
configuration were created, all tracked migrations through T13 were applied,
and `finalize-document-upload` was deployed with JWT verification. Named UAT
personas, the unaliased Workforce candidate and the required human witness were
not completed. The product owner subsequently directed that T14 UAT be done
after production and authorized production immediately as an explicit
exception. T14 therefore remains not performed/not passed. Exact evidence and
the required persona/scenario matrix are in
[`WORKFORCE_T14_STAGING_UAT_EVIDENCE.md`](WORKFORCE_T14_STAGING_UAT_EVIDENCE.md).

## Later phases

No production action is evidence of T14 acceptance. The later explicit
production exception authorizes migration, flag enablement and alias promotion
only after the technical release gates pass; attendance import and exception
bulk flows remain outside scope. Those gates passed and the verified release is
recorded in
[`WORKFORCE_PRODUCTION_RELEASE_EVIDENCE.md`](WORKFORCE_PRODUCTION_RELEASE_EVIDENCE.md).
T14 UAT stays the required next follow-up.

## Post-release Workforce Administration follow-up

The production Workforce workflow originally shipped with attendance,
timesheet and review consumers enabled while the three master-data consumers
remained planned and nonassignable. That made an authorized supervisor's
overview truthful but left no supported product path for creating workers,
organizing teams, changing dated work assignments or configuring calendars.

The approved follow-up enables these existing catalogue keys without changing
their original meaning:

- `workforce.workers.manage` creates and updates normalized worker records;
- `workforce.teams.manage` creates/closes teams and maintains dated worker,
  supervisor, project, scope and internal-location assignments;
- `workforce.configuration.manage` maintains trades, internal locations,
  calendars, shifts and dated team schedules.

All three retain the `workforce.view` dependency. A login account is still
created, disabled and permissioned only in User Management; a Workforce worker
record does not create Auth identity. A person marks attendance only when the
server confirms both the operational attendance/timesheet capabilities and an
applicable dated organization/team/project/scope/internal-location/worker
responsibility. Role labels and linked-worker identity do not grant command
authority.

Worker and team removal is intentionally not exposed. Login accounts are
disabled, workers become inactive/suspended/left-company with a leaving date,
teams close through their effective window and project/team changes use an
atomic transfer command that closes the prior assignment the day before the
new one. The old assignment, actor, reason, version and audit evidence remain
available. Ordinary table APIs and internal helpers remain denied.

The responsive Workforce Administration route contains Workers, Teams, Setup
and Access sections. Each section is independently capability-controlled and
loads only protected, non-commercial server projections. This follow-up does
not perform or replace the outstanding T14 named-persona/manual UAT.

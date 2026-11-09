# Workforce attendance: mobile-first product and implementation plan

Prepared: 7 October 2026 (Asia/Karachi).
Status: implementation in progress; two local UI slices implemented. Usability validation and release pending.
Owner direction: mobile-first attendance for site engineers and warehouse recorders; clean Codex/calculator-style presentation within the familiar Yorks Material Request home and workflow language.

## 1. Outcome and evidence

Make recording an ordinary crew day as understandable and efficient as marking the existing printed table. Users should recognize their team, mark attendance, change exceptions and confidently save without needing to understand the administrative system.

The user reports that site engineers and warehouse staff mainly use phones, prefer a printed table, have limited basic English and find the current corporate-style app complicated. This is direct stakeholder evidence. Earlier source and saved-image inspection identified dense desktop controls, separate mobile worker editors, technical labels, inconsistent minutes/hours presentation, hidden bulk efficiencies and an in-memory draft boundary. These observations are not a measured production usability study.

The current architecture already supplies worker cards, four language catalogues, standard-shift filling, bulk edits, explicit online saving, immutable history and protected approval flows. Preserve that foundation.

### Goals

1. Ordinary attendance can be completed without coaching after a brief introduction.
2. Logging takes no longer than the team's measured paper process for an equivalent crew and exceptions.
3. Users reliably distinguish a local draft from a server-saved record.
4. Interruptions and retries preserve work without duplicate submissions.
5. Office staff can use the resulting authorized records without retyping the daily log.

### Scope boundary

This plan covers the attendance home, daily mobile editor, tablet/desktop adaptation, exception entry, draft recovery, save feedback and office handoff. It does not introduce payroll, worker self-service, biometric/GPS tracking, a new platform role, AI/OCR attendance interpretation, automated approval, or changes to People/HR and Leave ownership. Those need separate product decisions. Existing worker records remain distinct from login accounts.

## 2. Authority and implementation baseline

Read [source authority](SOURCE_OF_TRUTH.md), [product decisions](PRODUCT_DECISIONS.md), [Workforce contract](WORKFORCE_ATTENDANCE_TIMESHEETS.md), [architecture/security](ARCHITECTURE_AND_SECURITY_CONTRACT.md) and [UI contract](R35_UI_CONTRACT.md) before each slice.

Use the [Material Request workspace plan](MATERIAL_REQUEST_WORKSPACE_REDESIGN_PLAN.md) and current MR implementation for visual/interaction reuse. Historical plans do not prove the currently deployed appearance. Capture the actual approved MR home and all seven phases at implementation kickoff and pin the source commit and screenshots used as references.

This document specifies proposed presentation and draft enhancements. It does not silently supersede server invariants. Any necessary authority change must be resolved and documented before dependent implementation. In particular, default location is a client suggestion that must become an explicit, authorized allocation; assignment alone is not server permission to infer a work target.

The planning checkout is at `0117273` with pre-existing unrelated changes. No application gate was rerun for this documentation-only task. The prior audit inspected a separate released-source worktree at `3efc069`; reconcile branches before implementation. Historical T13 evidence and the outstanding [T14 manual UAT](WORKFORCE_T14_STAGING_UAT_EVIDENCE.md) remain separate from this plan. No current full-suite pass or live usability pass is claimed.

## 3. People and entry points

| Person/context | Primary task | Initial experience |
|---|---|---|
| Authorized site engineer recording a crew | Record today's workers and exceptions | Today card for assigned team/project; one tap into logging |
| Authorized warehouse recorder | Record warehouse/internal work | Today card for assigned team/internal location |
| Person responsible for multiple teams | Choose the correct crew | Explicit team chooser; remember preference only while still authorized |
| Reviewer/final approver | Resolve issues and perform existing period commands | Review queue and period workspace |
| Administrator | Maintain workers, shifts, assignment and responsibility | Separate administration destination |

Warehouse recorder is a usage persona, not a new or automatically privileged role. Effective capabilities and dated responsibility determine access. A worker need not receive a login for a supervisor to record attendance. No shared credentials are introduced.

## 4. Macro UI and shared design contract

### Familiar Yorks structure

- Retain the universal Yorks shell, top bar, mobile navigation and existing Back behaviour; avoid duplicate navigation bars or back buttons.
- Workforce home follows the MR register hierarchy: compact title, one primary action, familiar filters/search, records with status and next action.
- Put today's team task first for recorders. Provide a direct Today entry from authorized mobile navigation/home; keep previous records reachable through Workforce home.
- Reuse AppColors, AppSpacing, AppTypography, field treatments, sheets, menus, status chips and focus conventions. Codex is the reference for restraint and hierarchy, not a new theme/font framework or chat interface.
- Keep metric dashboards and administration out of the frontline logging path. Reviewer summaries remain available to appropriate users.
- Desktop/tablet use a familiar table where space allows. Phones use direct-action cards and short exception sheets.
- Use a single mounted controller across responsive branches; resize, sheet opening and language changes must preserve edits and focus.

### Seven-phase Material Request familiarity

Reuse MR's current-stage emphasis, completed indicators, owner/next-action summary and expandable history pattern. The inspected `_IndustrialWorkflowStrip` already adapts wide progress to a compact mobile timeline. Reuse/extract presentation safely rather than importing Material Request state into Workforce.

Daily logging has three interaction stages: **Mark attendance → Check → Save**. These are UI steps, not new database states. On mobile show only the current step and next action, with details expandable.

Monthly state remains the existing server model:

| Server state | Proposed understandable presentation |
|---|---|
| draft | In progress |
| ready_for_review | Ready to submit |
| submitted | Submitted |
| under_review | Being reviewed |
| returned_for_correction | Changes needed |
| awaiting_final_approval | Waiting for final approval |
| locked | Approved and locked |
| reopened | Reopened for correction |

Returns and reopening are branches, not fabricated completed stages. Never label an unsaved day Approved, or show seven required daily steps merely to match the MR count. Formal submit, verify, approve and reopen commands retain their meaning and separation of duties.

## 5. Screen specifications

### S1 — Workforce home

Order: title; Today card with team/date and primary **Record attendance** or **Continue attendance**; small status filters; recent authorized day/period records. Each record shows team, date, truthful save/workflow state and next action. Show actor/time when meaningful. Keep device drafts explicitly labelled and separate from confirmed records. Empty state explains whether no team is assigned, no records exist, or the request failed.

For several teams, choose one explicitly. A remembered team is a convenience, never proof of current access. No team/configuration error should masquerade as an empty successful roster.

### S2 — Today's attendance

Order: plain title; easy language access; selected work date; team/location with Change; marked/unmarked count; **Mark remaining present**; name/number search; worker list; sticky save area.

Worker card: name and worker number; **Present**, **Absent**, **More**; readable working hours and work location when present; clear changed/error cue. No automatic attendance fact on opening. Card identity and selected date remain clear while editing. Keep list ordering stable after a mark so the next worker does not jump away.

Footer: marked count, save state and **Check and save**. Validation must distinguish marked, valid and server saved; a green attendance selection is not a saved receipt. When invalid, enable a clear **Fix N items** path instead of an unexplained disabled button. When unchanged, show **Up to date** rather than implying a save is needed.

### S3 — Exception sheets

| Action | Fields and behaviour |
|---|---|
| Change hours | Large hour/minute controls, appropriate numeric keyboard; represent 8 hours consistently, never an unexplained 480 |
| Overtime | Hours/minutes; optional reason according to existing contract, not a new compulsory field |
| Leave/other status | Existing supported status choices, plain wording; no invented leave approval or HR mutation |
| Change work location | Authorized searchable project/building or internal location options; existing target distinctions preserved |
| Split time | Location/time rows and remaining time; sums must match attendance; preserve interval/overlap rules where ranges are supplied |
| Add note/evidence | Optional by existing rules; controlled document service where supported; draft and upload status remain distinct |

Each sheet has a descriptive title, labelled close/cancel and **Done**. Done changes the local draft; it does not imply a server save. Browser/Android Back dismisses the sheet first; route exit then uses a truthful draft guard. No repeated confirmation for each ordinary unsaved field edit.

### S4 — Mark several people

Accessible secondary action, not unexplained Bulk. Show explicit selected count and names, then choose an action. **Mark remaining present** affects only unmarked editable workers in the declared team/date scope. Search must not silently change its meaning: label selection scope explicitly and allow review of affected people. Paginated rosters must not pretend only loaded rows are the full team. Load/resolve the intended authorized set or explicitly operate on selected visible people. Respect the existing 500-row command limit; never silently split an atomic whole-team save and present full success after partial completion.

Existing absence/leave/saved values remain unchanged by “remaining.” Prefill from the retained configured shift; missing shift requires hours entry, not a fabricated default. Show Undo for local operations. Bulk action, deletion/clearing and status change have distinct undo boundaries. Undo never rewrites a committed record; post-save correction uses existing versioned commands.

### S5 — Check and save

Short summary: exact date/team, counts by supported attendance status, overtime count and unresolved items. **Fix** opens the relevant worker without losing the rest. Final **Save attendance** invokes the existing online atomic command and waits for confirmation. Prevent double taps; reuse the same durable command identity for uncertain retries. A timeout is “We could not confirm the save,” not an automatic failure/success claim. Reconcile before issuing a new command.

After success, remain on the useful day record with saved time and next appropriate action. Do not create a dead-end success screen. Offer another team/day through navigation, preserving the saved record and clearing only the confirmed draft version.

### S6 — Previous days and office handoff

Today/Yesterday/date picker; clear historical date banner; prohibit future attendance using retained calendar timezone. Read-only locked days explain the valid correction/reopen route. Historical assignment/identity snapshots remain intact. Monthly submission/approval remains distinct from daily save. Keep reports, exports and authorized period history accessible from the record without filling the daily editor with them.

## 6. Interaction rules and edge cases

- “Present” uses standard hours as an explicit draft suggestion; a worker with existing active allocations must be updated consistently through accepted combined commands.
- Switching to Absent/Leave with hours/allocations explains what will be cleared and offers local Undo. Never leave hidden invalid child allocation data.
- Copy previous day copies suitable authorized work details for review; never silently copy yesterday's absence, leave or evidence into today's facts.
- Missing worker: **Person missing?** explains who can fix assignments. Do not create worker identity or widen access from the recorder flow. Add a routed support request only if an existing approved channel exists; no fake success button.
- Long names, duplicate names and non-Latin text retain a visible worker number and wrapping. Photos are not required for this release.
- Switching team/date, refresh and leaving the app must preserve or explicitly handle dirty work. Never silently replace a draft with another team's data.
- Morning presence and final hours must not be confused with measured completed time. Shift defaults are proposed hours; recorder explicitly checks them before save. A new provisional clock-in system is outside this release.

## 7. Durable drafts and offline behaviour

Implement a protected local draft service below the controller. This is new reliability work, not a claim that current in-memory drafts survive restarts.

### Proposed draft envelope

Schema version; tenant/backend identity; actor ID; team/date context; worker IDs; retained source versions; attendance/allocation edits; saved-local timestamp; reviewed payload fingerprint; pending idempotency identity where applicable. Keep layout preferences separate. Store only permitted necessary data, never unrestricted worker or commercial snapshots. Decode failures retain recoverable evidence and show a recovery error; do not silently discard rows.

### Save states

| State | User wording/action |
|---|---|
| Dirty, local persistence pending/failed | Changes not saved / Could not save on this phone |
| Local persistence confirmed | Saved on this phone — not sent |
| Offline after local save | Saved on this phone — waiting for internet |
| Online pending commit | Saving attendance… |
| Confirmed server response | Saved at [time] |
| Lost/uncertain response | Save not confirmed — check again |
| Version conflict | This record changed — review changes |
| Revoked access | You no longer have access to this team |

Persist after changes, flush at appropriate lifecycle boundaries, and detect storage failures/quota. Do not promise persistence before the local write succeeds. Restoration must distinguish an unsubmitted draft from an uncertain submitted payload. First release offers **Check and send** after reconnection; no automatic critical background commit.

Offline editing is limited to a previously authorized cached roster. A fresh offline start without that roster explains that internet is needed. No new scope discovery offline. Before sending, reauthenticate/recheck authority, fetch current versions and reconcile. Security/authorization errors never permit stale fallback. Known logout/revocation clears protected visible state and invalidates local access; design cache expiry/session binding and storage protection explicitly before this slice ships. Shared phones and browser storage eviction must be tested. No durable-sensitive-cache rollout until these protections pass review.

Authority refresh must not resurrect forbidden drafts. Two tabs must detect competing draft writers, preserve conflict evidence and prevent silent overwrites. Successful save clears only the exact acknowledged draft revision; later edits remain pending.

## 8. Language, accessibility and responsive acceptance

Reuse existing English, Arabic, Urdu and Hindi catalogues with no hard-coded user strings. Language choice is easy to find and remembered per user. Validate common labels with intended speakers; do not assume every worker reads their spoken language fluently. Icons always have text. Preserve RTL, dates and understandable units.

Primary touch targets: 48–56 logical pixels, never below existing 44 minimum. One-handed reachable action area; no horizontal scrolling for ordinary phone logging; sheet content and footer remain reachable with keyboard visible. Support text scaling, screen-reader labels/state announcements, visible keyboard focus, adequate contrast and reduced motion. Do not rely solely on colour, small tooltips or transient snackbars.

Verify 360x800, 390x844, a larger phone, tablet portrait/landscape and desktop 1366/1440 widths. Preserve existing breakpoint conventions unless measured content requires adjustment. Test on representative actual Android/iOS devices and web/PWA sessions, not screenshots alone. Record performance on crews of 1, 25, 100 and 500 people; bounded rendering must preserve selection, search, draft identity and scroll position.

## 9. Engineering map

| Layer | Existing integration points | Planned work |
|---|---|---|
| Home | `lib/features/workforce/presentation/screens/yorks_workforce_overview_screen.dart` | Recorder-first Today card, familiar register and direct entry |
| Daily UI | `lib/features/workforce/presentation/screens/yorks_workforce_daily_attendance_screen.dart` | Direct card actions, exception sheets, summary and responsive composition |
| State | `lib/features/workforce/application/workforce_daily_roster_controller.dart` and `workforce_providers.dart` | Draft adapter, coherent undo, conflict/recovery state; retain authority epoch |
| Domain | `lib/features/workforce/domain/workforce_daily_roster_models.dart` and attendance/allocation models | Versioned draft envelope, no ambiguous server-state additions |
| Repository | `lib/features/workforce/data/workforce_repository.dart` | Reuse authorized projections and atomic save; add only justified narrow queries |
| Monthly/reporting | Existing timesheet/review/report controllers and screens | Preserve commands; plain next-action summaries and output parity |
| Navigation | `lib/app/router.dart`, existing shell/navigation components | Capability-filtered direct Today entry and correct Back behaviour |
| Copy/theme | `lib/shared/models/yorks_v1_workforce_strings.dart`, shared tokens/widgets | Plain localized labels, consistent MR/calculator components |
| Analytics | Existing analytics event/service/route infrastructure | Allowlisted funnel events with no attendance content |
| Backend/tests | `supabase/migrations/`, `supabase/tests/database/`, existing Workforce Flutter tests | Additive migrations only if justified; permission, retry and competing-writer coverage |

Before edits, produce a behaviour-preservation map: old entry, new entry, actor/state, controller/RPC, test. Use Widget → Riverpod controller → repository/local service. Critical writes stay online, server-authoritative, versioned, locked and idempotent. Realtime triggers an authorized refresh. No generic collection snapshot upserts and no direct widget Supabase calls.

## 10. Print/export and adoption bridge

Obtain a blank/redacted current printout; match useful columns, ordering and terms. Existing approved snapshot exports retain their meaning. If daily draft/unapproved printing is needed, specify a separately authorized output clearly labelled with its status; never present it as the approved monthly report or reuse approval-only exports to bypass authority.

Pilot keeps a temporary paper fallback and a defined reconciliation owner/date. Avoid indefinite double entry. No OCR/photo-to-attendance automation is part of this implementation. Training is a short demonstration in the preferred language and an illustrated quick guide, not a prerequisite for deciphering the UI.

## 11. Telemetry and success measures

Proposed allowlisted events: attendance_opened, roster_ready, attendance_marked, bulk_action_applied, check_opened, validation_blocked, local_draft_saved, draft_restored, save_attempted, save_confirmed, save_uncertain, conflict_shown and recovery_completed. Names must follow existing analytics conventions before implementation. Properties limited to coarse action/error type, app version, language, viewport class, connectivity, bucketed crew size and duration. Avoid worker/team/project identifiers, names, hours, attendance status contents, leave reasons, notes and document paths. Audit records remain separate. Mask sensitive replay content and verify actual payloads.

Measure session-level task completion rather than using analytics to rank workers. Confirm PostHog availability/configuration; do not assume the currently recorded route events establish this funnel.

| Measure | Proposed pilot gate | Method |
|---|---|---|
| Unassisted task completion | At least 90% across defined ordinary tasks | Witnessed attempts; report sample size and assistance |
| Time to record equivalent crew | Median no slower than measured paper baseline | Paired tasks with similar exceptions; also report slow cases |
| Save-state understanding | Every participant distinguishes device draft/server save | Ask them to explain the state in interruption scenarios |
| Data reliability | Zero lost drafts/duplicate commits in defined tests | Restart, retry, storage-failure and competing-writer tests |
| Office utility | No retyping for the agreed output workflow | Reviewer completes daily/monthly handoff |
| Continued use | Target at least 80% of eligible pilot crew-days logged by week two | Authorized aggregate completeness, not screen views alone |

These are proposed acceptance thresholds, not measured results or statistical proof of product-market fit. Run one warehouse and one site team over roughly two working weeks, with 5–8 representative recorders across languages/device types where feasible. Observe initial use without coaching, then teach and retest; record both results separately.

## 12. Delivery slices and exit criteria

| Slice | Deliverables | Exit criterion |
|---|---|---|
| WFA-01 Baseline and design | Pin source/production references; MR seven-phase visual inventory; printout mapping; actual-phone task baseline; preservation map | Concrete mobile prototype and agreed ordinary-day task; unresolved assumptions recorded |
| WFA-02 Shared shell/home | Recorder-first home, Today entry, familiar register/status language; guarded routes | Correct authorized landing, empty/error/denied states, mobile and MR shell regressions pass |
| WFA-03 Daily mobile core | Present/Absent, hours, optional details, explicit bulk scope, local Undo, check/save | Standard day and exceptions work at 360px; server facts unchanged before Save |
| WFA-04 Durable recovery | Protected draft store, restart/offline recovery, version conflicts, uncertain command replay | Identity isolation, storage failure, lost-response and two-tab tests pass |
| WFA-05 Office/responsive integration | Historical corrections, split time, period handoff, authorized outputs, tablet/desktop parity | No lost capabilities/history; office accepts sample output |
| WFA-06 Verification and pilot | Full applicable gates, named-persona staging UAT, telemetry payload review, actual-device sessions | Technical and usability acceptance documented separately; remaining defects resolved |
| WFA-07 Controlled release | Release manifest, explicit production authorization, reversible flag/rollout and rollback evidence | Production artifact/routes verified; pilot monitoring and rollback owner assigned |

Begin with WFA-01. Independent foundation work can proceed while the printout/language input is collected, but final usability acceptance depends on intended users. No fixed delivery-date promise without baseline and scope estimates. Each slice is a coherent PR; preserve unrelated dirty work. Production deployment is a later explicit action, not part of writing this plan.

## 13. Required verification matrix

- Normal day; all absent; no assigned team; no shift; multiple teams; large paginated team; duplicate names; long names; all supported languages and RTL.
- Bulk under search/filter/paging affects the declared set only; no saved exception overwritten; Undo restores each discrete action.
- Optional overtime reason remains optional; no invented payroll rules. Split allocation totals, targets, date validity and interval overlap follow existing server constraints.
- Daily review/save and monthly submit/verify/final approval remain distinct; locked/returned/reopened records expose only authorized actions.
- Positive/negative scopes: authorized site/warehouse recorder, wrong team, expired responsibility, role-only user, inactive/revoked user; required existing Project Engineer, Site Engineer, Procurement and Admin security coverage plus relevant reviewer/final-approver separation.
- Refresh, app termination, date/team navigation, keyboard, rotation and text scaling do not silently lose drafts.
- Offline cold start; cached offline start; reconnect; expired authentication; server outage; timeout after commit; retry; competing tab/device; storage quota/corruption; logout/login as another actor.
- Controller/repository tests prove actual confirmed versions and no optimistic critical success. Any backend change gets positive/negative RLS/RPC tests and data-preservation/rollback notes.
- Run the complete applicable AGENTS gates: pub get, changed-Dart format check, analyze, Flutter suite, CI-configured web and APK builds; tracked local Supabase reset/test for backend changes. Proper signed Android lane for a release; ephemeral/debug signing is not distribution proof.
- Capture desktop and 360px/mobile evidence plus representative physical-device results. Execute existing T14 named-persona/manual scenarios; automation and a production smoke test do not convert deferred UAT into a pass.

## 14. Rollout and rollback

Use an isolated implementation branch/worktree and dedicated staging backend. Prefer a presentation rollout switch defaulting off until accepted; preserve the current attendance path during the pilot. If switching off, retain recoverable drafts and provide a compatible recovery path; do not orphan new-schema drafts. Any migration is additive and preserves history. Pin exact source, schema, flags and artifact hashes before release. Define rollback triggers: data loss/duplication, authorization regression, significant save failures or inability to complete the ordinary task. Rollback the UI flag/artifact without deleting committed attendance or downgrading audit history.

## 15. Inputs to resolve during WFA-01

| Input | Owner | Effect/default |
|---|---|---|
| Blank/redacted printed table | Product/site and warehouse leads | Needed before final field/order/output acceptance; prototype can start now |
| Representative devices, crew sizes and connectivity | Pilot leads | Sets performance/device test sample; use stated viewport/crew matrix until verified |
| Preferred spoken/read languages and simple terminology | Actual recorders with product lead | Start with existing four catalogues; validate before copy freeze |
| Named recorder/reviewer/final-approver pilot accounts | Authorized administrator | Required before staging persona UAT; never invent grants |
| Daily output versus approved monthly output expectations | Office reviewer/product lead | Keep existing report authority until explicit daily-output scope is resolved |
| Offline sensitive-cache protection and expiry policy | Engineering/security | Must resolve before WFA-04 rollout; fail closed on known authority loss |

## 16. Definition of done

The redesign is complete when a warehouse recorder and site engineer can independently log the agreed scenarios on their own phones, correctly recognize saved state, recover safely from interruption and supply usable office records; all existing permissions, history and approval controls pass regression checks; the exact staged candidate passes manual persona UAT and measured pilot gates; and any later production release has explicit authorization and verified rollback evidence.

Planning completion does not mark any implementation checkbox or deployment complete.

## 17. Implementation progress — 7 October 2026

First implementation slice on `codex/workforce-mobile-attendance`, based on `3efc069`:

- Mobile overview exposes existing server-authorized workflow navigation instead of hiding all action links. No direct mutation is added to the overview.
- Phone worker cards expose 48px Present/Absent buttons. Present uses retained suggested shift hours and opens the existing editor when no valid hours are suggested.
- Direct marks remain local until the existing review/save command. Local Undo restores the exact previous row only while the captured edit remains current; later edits, refresh, save and authority purge invalidate it.
- Local-change/Undo feedback is translated into the four existing languages; long worker names wrap.
- Regression tests cover direct mark/undo, zero-hour suggestions, stale undo and authority purge. Updated deterministic mobile images cover English, Arabic and Urdu; existing desktop/tablet coverage is retained.

This slice does not complete WFA-01–07: the proposed register/home redesign, plain-copy overhaul, bulk improvements, durable draft storage, telemetry funnel, printout mapping, real-device pilot and named-persona UAT remain pending. Existing in-memory drafts must not be described as restart-safe or persisted offline drafts. No production or backend change is included.

## 18. Actual paper-sheet evidence — 7 October 2026

The user supplied the current Daily Timesheet. This changes the emphasis of the proposed solution: the familiar record is one worker's month, with daily clock times and weekly sign-off spaces. Team attendance shortcuts remain useful but cannot alone replace this record. Do not copy the supplied worker identity or attendance details into fixtures, telemetry, source assets or demonstration data.

### Observed structure and implementation mapping

| Paper element | Product requirement | Existing boundary / required work |
|---|---|---|
| Worker name, employee number, designation, supervisor, month | Worker-month header and stable identity, with historical supervisor context | Reuse authorized worker and retained assignment projections |
| Day number and weekday | Scrollable monthly day list on phone; familiar month table on desktop/print | Preserve selected work date and retained calendar timezone |
| IN / BRK. / IN / BRK. / IN / OUT | Simple daily start, break-out, return and finish entry with optional additional break interval | Actual punch/break events are not represented by the current attendance input; additive normalized evidence design is needed |
| NOR. and HOL. overtime columns | Preserve the distinction if confirmed as required, with clear localized names | Current attendance stores one overtime-minute total; do not invent classification or a payroll rule |
| Project name and occasional written remarks | Explicit authorized work location plus optional note, with split-work support | Existing allocation targets and notes are reusable; assignment alone does not authorize inferred allocation |
| Weekly site-in-charge signature space | Make weekly review needs explicit | Do not fabricate signature images or equate daily save/monthly approval with a weekly witness |
| Approved by, employee signature and engineers approval spaces | Map actual required attestations to authorized digital records or paper handoff | Confirm who signs and whether weekly/employee digital attestation is required before adding a workflow |

### Revised mobile information architecture

Home keeps the MR-style register and Today action. Provide two views of the same authorized facts: **Team today** for fast crew entry and **Worker month** for the familiar individual log. Neither view creates a duplicate attendance source. Selecting a worker opens their month with Today highlighted; selecting a day opens the focused daily editor. Month rows show date/day, entered time summary, work location and status, with exceptions readable without horizontal scrolling. Desktop and print can use the fuller paper-like month grid.

Daily editor proposal: attendance status; start time; break start/end (add another break only when needed); finish time; work location; overtime and note. Common patterns can be filled as suggestions after an explicit action and changed for exceptions. Unknown clock values remain unknown: never reconstruct historical punches from regular/overtime totals or scheduled hours. Store actual intervals separately from planned shift definitions.

### Backend findings and dependency

`workforce_attendance_models.dart` currently accepts attendance status, regular minutes and overtime minutes. Its retained schedule snapshot contains scheduled shift/break information, which is not actual break evidence. `workforce_timesheet_models.dart` supports optional allocation start/end ranges, but those are location-allocation evidence, not a complete daily punch/break ledger. Reusing them as such would change historical meaning.

Before clock-time implementation, specify an additive evidence model and narrow versioned RPC that preserves current totals/records, handles overnight shifts and multiple breaks, and defines how entered/derived totals are reconciled. Any computed duration must state whether breaks are excluded; overtime derivation/classification must wait for the confirmed business rule. Store integer minutes and explicit retained timezone/date context. Do not interpret handwritten combined overtime notation automatically.

Open clarification sent to the user: meaning of combined overtime notation; normal versus holiday overtime rule; whether overtime is entered by a supervisor or calculated from clock times. Also validate the unused IN/BRK columns and actual sign-off practice during WFA-01. Continue independent UI/regression work while these are unresolved; do not ship guessed calculations.

### Acceptance additions

- A worker-month record can reproduce the agreed paper fields without retyping known authorized identity details.
- Recording actual clock times never overwrites planned schedule definitions or silently backfills old dates.
- Normal/holiday overtime follows an approved rule and preserves original evidence.
- Actual breaks, overnight work, missing finish time and split locations are tested independently of approval.
- A reviewer can trace daily evidence to the same monthly record and existing approval history.
- Weekly/employee sign-off is explicitly mapped or visibly left as paper-only; no claim of a digital signature without a real attestation.

### First-slice local validation

7 October 2026: `flutter pub get` passed; changed-Dart formatting and `git diff --check` passed; `flutter analyze` reported no issues; full `flutter test` passed 2,506 tests with 4 skips. The CI-configured `./tool/r35.sh build-web` passed including startup budget. `CI=true YORKS_CI_EPHEMERAL_SIGNING=true` CI-configured APK build passed (verification artifact only, not production signing). Updated 360px/390px mobile goldens were inspected, along with the retained desktop daily-roster reference. No database changes, production mutation, real-device acceptance or named-persona UAT were performed.


## 19. Mobile daily actions and worker-month continuation

8 October 2026: implemented a second local presentation slice:

- Phone attendance uses short localized instructions, an explicit Hours and details action, and Check and save in the fixed footer. Existing review and server save remain authoritative.
- Mobile monthly worker lists expose search and pagination through the existing controller callbacks.
- Opening a worker focuses their record. Phone days use readable vertical cards with status, regular/overtime hours and location; selecting a day shows compact facts inline. Tablet calendar and desktop table remain available.
- No schema, RPC, permission or attendance calculation change. Actual clock intervals and overtime classification remain dependent on the rules recorded in section 18.

Verification: 43 focused daily/monthly tests passed; full regression passed 2,507 tests with four skips. A final compact day-facts presentation adjustment then passed all 10 monthly tests. Analyzer reported no issues. Formatting and diff checks passed. Phone daily and selected-day golden images were inspected; desktop/tablet regression goldens passed unchanged. CI web and ephemeral-signed APK results are recorded after completion below. These are local checks, not named-persona or real-device acceptance.

Remaining implementation includes durable draft recovery, a simpler home/exception flow, agreed actual-time evidence, paper-compatible export/sign-off mapping, telemetry and the site/warehouse usability pilot. The entire redesign is not complete and has not been deployed.

Final build checks: CI-configured web build passed with startup budget; CI ephemeral-signed release APK build passed. The APK is a verification artifact, not a production-signed release.


## 20. Attendance clarity and compact monthly summaries

8 October 2026: further UI refinement keeps the existing controller/repository and server-save contracts:

- Replaced the mobile Bulk label with Edit team and its sheet title with Edit selected workers in all four languages.
- The fixed phone footer describes unsaved changes and explains an unavailable save action: no edits, invalid worker details or internet required. Offline and invalid states still cannot save.
- Monthly totals use two columns on phones with wrapping text. Daily log replaces Compact calendar; displayed durations consistently use hour labels, including planned hours and hours by location.
- Added assertions for idle/invalid/offline save guidance and tested selecting monthly days in all four languages. No mutation, authorization, schema or overtime calculation changes.

This is a clarity improvement, not proof of field adoption. Actual clock-time evidence, recovery and the usability pilot remain tracked in sections 18–19.

Validation for section 20: 46 focused tests and 2,510 full regression tests passed (four skips); analyzer clean; formatting and diff checks passed. CI web startup budget and ephemeral-signed verification APK passed. English desktop and 360px phone screenshots inspected; translated phone day interactions passed in all four languages. No deployment or human field-acceptance claim.


## 21. Workers, Attendance and Reports entry points

8 October 2026: implemented locally following the owner-confirmed assigned-team
scope:

- Home exposes capability-aware Workers, Attendance and Reports shortcuts.
  Reports opens the existing monthly workspace and its report panel.
- Phone reports now expose generation, Excel download, PDF download, preview,
  print and PDF sharing through the existing authorized report controller.
- The administration Add worker form collapses optional details. The new scoped
  Workers form requests core identity and employment facts, permits a generated
  worker number, and lists only authorized teams with paginated worker results.
- Server checks live actor, capabilities and current team responsibility or
  supervision. Worker and assignment creation is atomic, audited and idempotent.
  Failed or uncertain replies do not report success; retries retain the command
  key. Authority changes dispose the scoped controller and late reads are ignored.
- All new labels are provided in English, Arabic, Urdu and Hindi.

### Backend and release contract

Migration: `supabase/migrations/20261007193129_workforce_assigned_team_worker_creation.sql`.
Adds only authenticated `v1_get_workforce_team_workers` and
`v1_create_workforce_team_worker`; the permission helper remains private.
The exact callable inventory test was extended for these two endpoints.
Existing organization management permissions and historical records are retained.

`YORKS_WORKFORCE_TEAM_WORKERS` defaults off. For staging, apply the migration
before building with the flag enabled. Rollback disables the flag and revokes
the two endpoint grants; retain worker, assignment and audit history. No remote
migration or deployment was performed in this slice.

### Local verification

- Analyzer: no issues; full Flutter suite: 2,517 passed, four skipped.
- Local database reset, lint (no errors), and full suite: 125 files, 3,642 tests
  passed. New tests cover Site Engineer, Procurement warehouse supervision,
  Project Engineer and Admin, rejected foreign-team creation, expired scope,
  private helper/table denial, unchanged organization-management denial and retry.
- Desktop 1366px and phone 360px Add worker golden/interaction checks passed.
  Existing report tests verify mobile and desktop action availability.
- CI web build/startup budget and ephemeral-signed APK build passed with the new
  feature flag enabled. The APK is a verification artifact, not production signed.

Real printer/mobile-device acceptance and the site/warehouse pilot remain open.
The actual-punch, overtime classification and recovery work in sections 18–20
is not superseded by this slice. Automated evidence does not replace human UAT.

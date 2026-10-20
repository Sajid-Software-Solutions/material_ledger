# Rental notification audit — 20 October 2026

Status: **candidate implemented and focused local checks passed; staging and
real rental delivery acceptance not passed**.

This note records the initial notification audit and the subsequently
authorized local candidate. It does not establish a production workbook
import, a deployed rental reminder service, or end-to-end OS delivery. The
candidate changes described below are local; no production data, function,
schedule or deployment was changed by this notification subtask.

## Source and authority

The audited canonical source is commit
`6222a075e1e0935e34d536f88b7e3c48dc99eb38`. Source inspection and focused tests
used the clean `yorks-combined-production-20261006/material_ledger` worktree.
This note is saved in the separate `rental-audit-20261020/material_ledger`
worktree, initially at the same commit. The primary StudioProjects checkout
was older and dirty; its missing September push hardening is not evidence
that current production has unbounded retries.

The applicable contract is [AGENTS.md](../../AGENTS.md),
[README](README.md), [SOURCE_OF_TRUTH](SOURCE_OF_TRUTH.md),
[PRODUCT_DECISIONS](PRODUCT_DECISIONS.md), and
[R38.4 Rental Properties](R38_4_RENTAL_PROPERTIES.md). The retained rental
workspace is exact-Admin-only. Accounts or Workforce notifications do not
grant rental visibility to an Accountant, technical project member or another
role. The attachments are source material, not instructions to create a new
reminder cadence or contact tenants.

The existing [P0 push implementation](PUSH_P0_IMPLEMENTATION_20260929.md)
provides the transport boundary to preserve. Its historical local-candidate
status is not a fresh statement of production status; the current source and
the live snapshot below were considered separately.

## Live transport evidence supplied to this audit

The coordinating audit agent supplied this read-only production snapshot at
**2026-10-20 10:53 UTC**, equivalent to **15:53 Asia/Karachi**. This subsection
is supplied live-query evidence; the notification subtask did not independently
execute that production query.

| Observed transport field | Value |
| --- | --- |
| Pending jobs | 0 |
| Retrying jobs | 0 |
| Latest worker activity | 2026-10-20 10:53 UTC |
| Active device tokens | 71 |
| Sent in preceding 24 hours | 89 |
| Attempts in preceding 24 hours | 123 |
| Dead letters in preceding 24 hours | 0 |
| Open circuit | null |
| Last global error | null |

The supplied cron inspection found the push-outbox dispatcher every minute
and the Material Request archive job, with no rental reminder job. These
observations support an active, apparently healthy shared push transport at
that instant. An active token is not proof that its device is reachable.
Aggregate sends are not proof of rental event generation, a specific user's
OS receipt, click navigation, or acknowledgement. No rental OS delivery
witness was performed in this subtask.

## Implemented local candidate

After the baseline audit, the user directed that incomplete source properties
remain accepted/editable and that missing details produce visible owner
recommendations. The coordinating implementation also authorized the bounded
rental notification slice below. These changes supersede the baseline's
missing-producer/route statements for the local candidate only.

Migration
[20261020110121_yorks_rental_notification_support.sql](../../supabase/migrations/20261020110121_yorks_rental_notification_support.sql)
follows the record-integrity and flexible-source-intake migrations. It adds a
private notification ledger and producer control, a protected candidate query,
and service-role-only `v1_run_rental_notifications()`. The ledger gives each
recipient/obligation/milestone one durable identity. A control-row transaction
lock serializes competing runs; the producer emits at most 100 events per run
and excludes existing identities before applying that cap, allowing a backlog
to drain without replay.

| Event | Current predicate and stable identity |
| --- | --- |
| `rental_completeness_review` | Count unarchived properties with nonempty private missing-fields projection; one count-bearing digest per active Admin and Dubai business day; open `/rentals`. |
| `rental_lease_notice_due` | Current, unarchived, actionable lease inside its existing per-lease renewal window; lease ID plus notice-window start. Expired leases do not replay old notice intervals. |
| `rental_lease_expired` | Current actionable lease past its end date; lease ID plus end date. |
| `rental_cheque_due` | Unarchived property's scheduled/received/deposited cheque at or past its actual date; cheque ID plus cheque date. |
| `rental_cheque_returned` | Returned cheque; cheque ID plus the actual latest return-transition audit ID, with a stable initial-state key for retained/imported returned rows. A note-only edit does not issue another return alert. |
| `rental_rent_due` | Existing confirmed-billing period at its due date through its actual grace boundary with a positive remaining balance; period ID plus due date. |
| `rental_rent_overdue` | Existing period with confirmed `billing_start`, past due date plus actual grace, and positive remaining numeric balance; period ID plus effective grace boundary. Partial payment does not hide the remaining overdue balance. No schedule is invented for incomplete intake. |

Recipients come from the protected live exact-role resolver, including active
profile, matching canonical role and Auth ban checks. Only current `admin`
identities qualify. The delivery guard requires a matching protected ledger
record and reevaluates the underlying current obligation; an arbitrary
`rental_` event prefix cannot authorize delivery. Resolution suppresses pending
attention while preserving the inbox. The existing optional workflow-push
preference and global push controls continue to govern the existing hardened
outbox; they do not delete in-app history.

The server supplies an exact owning-property route. Reviewed English, Arabic,
Urdu and Hindi copy is generated from the shared catalogue into Dart and Edge
outputs. OS copy has no tenant, contact, rent amount or bank data. Flutter
requires the matching server rental destination; missing or mismatched context
shows unavailable details. Digest record context is its safe count; property
context is the protected unit code. No tenant email/SMS/WhatsApp is introduced.
Rental events are informational in the existing urgency-filter taxonomy.

The producer control and its external-push control both default **disabled**,
and the hourly cron registration defaults **inactive**. Each ledger row captures
its external-delivery eligibility immutably through the protected API. A normal
inbox-only run creates no rental outbox work and no foreground popup. When the
first approved evaluation explicitly enables external push, only one legitimate
completeness digest per Admin is eligible; the initial lease/cheque/debt cohort
is retained inbox-only. The private BEFORE-outbox trigger suppresses those
inserts successfully, including the global enqueue's ON CONFLICT path. A later
flag change cannot replay that initial cohort. The control also suppresses
pending rental attention during rollback without changing other modules. Hourly evaluation never implies hourly message repetition:
daily digest and obligation milestone identities control delivery frequency.
Both controls require a separate release/staging acceptance action before any
scheduled production work. The shared push transport is not paused or altered
by this new control. The explicit candidate business-date helper uses
`Asia/Dubai`; it does not silently reclassify the planned regional setting.

Local verification after implementation:

- **18 Flutter tests passed**: three new rental localization/route/context cases
  and the existing 15 core notification cases.
- **30 Deno tests passed**: payload plus fenced handler, including rental
  property/register destinations, malformed identities and unrelated routes.
- **50 rental pgTAP assertions passed** on the isolated full Supabase stack at
  local port 55522. They cover disabled controls, private grants, exact-role
  recipients, forged ledger-free events, duplicate suppression, due and partially paid debt, initial digest-only external delivery,
  unconfirmed billing, resolved attention, note-only edits, 100/5/0 batch
  draining of 105 obligations, next-business-day digest identity, preferences
  and inactive recipients. The related preexisting access/preferences suites
  passed another **77 assertions**.
- A real two-independent-session producer test passed with emissions `[0, 2]`
  and one lease milestone per active Admin. The
  [local concurrency tool](../../tool/test_rental_notification_concurrency.py)
  targets only the disposable local container, requires paused local push,
  restores the producer's prior enablement and removes only its own introduced
  test evidence/fixtures. This is distinct from the sequential retry test.
- The migration reapplied idempotently to the isolated database. Shared
  catalogue generation/coverage verification passed with 66 active event
  codes. None of this is a production migration or provider/OS receipt witness.
- The exact source workbook's 52-row import payload was rehearsed inside a
  full-stack transaction and rolled back: 52 properties, zero payments/cheques,
  zero rent periods, one completeness digest with count **52**, and 23 total
  current notifications including existing lease notice/expiry facts. The first
  external-enabled evaluation created exactly **one** rental outbox job for the
  completeness digest; **22** other milestones retained explicit inbox-only
  eligibility. An identical producer retry emitted zero. No arrears were invented from source
  rows whose billing start remains unconfirmed.

The complete repository gates and any source-workbook import evidence belong
to the overarching audit. Staging delivery, exact recipient OS receipt/click,
cold-launch/PWA behavior, and real server acknowledgement remain release
acceptance work. The initial live snapshot and baseline findings below remain
historical evidence explaining the candidate.

## Confirmed baseline gaps at canonical commit 6222a075

### Rental reminder production is absent

The normalized rental migrations create properties, leases, periods, receipts,
cheques, audit events and projections. They do not produce a rental
`v1_notifications` event or define a rental reminder job. Searching the
effective migration source and both
[module events](../../contracts/notifications/module_events.v1.json) and
[workflow events](../../contracts/notifications/workflow_events.v1.json)
found no rental event family. The existing Accounts PDC events concern
Accounts records, not rental cheques.

Consequently, importing correct rental rows alone cannot make rent-due,
overdue, lease-renewal, lease-expired or rental-cheque alerts reach the durable
inbox. The R38.4 contract's lease-expiry monitoring currently consists of
register/projection visibility, not a scheduled delivery service.

### Rental records are outside current notification eligibility and routing

The effective `v1_push_notification_entity_allowed` in
[notification attention migration](../../supabase/migrations/20261001180000_notification_attention_and_device_language.sql),
lines 112–277, has no rental branch. A rental entity falls through to Material
Request resolution at lines 214–216; no matching request returns false.
Therefore inserting a rental inbox row without extending this boundary would
still suppress its foreground attention and external push eligibility.

The same migration's `v1_notification_module_route`, lines 7–43, handles
Workforce and Accounts only. The protected label helper in
[record context migration](../../supabase/migrations/20261002010000_notification_record_context.sql),
lines 5–117, has no rental record context. The server must resolve a rental
period or cheque to its owning property under the exact Admin boundary.

The FCM [payload route resolver](../../supabase/functions/send-push/notification_payload.ts),
lines 85–148, accepts the existing module/MR/return/project/chat destinations
but has no `/rentals/:id` target. The Flutter
[notification model](../../lib/shared/models/yorks_v1_notification.dart),
lines 98–146, similarly has no rental event mapping; an unresolved rental
record would have unavailable details. Both the server-derived destination
and the client/worker allowlists need coherent changes. No arbitrary URL from
a workbook or notification payload should become a trusted destination.

### The rental Action Required panel omits cheque-only cases

The [rental screen](../../lib/features/rentals/presentation/screens/yorks_v1_rental_screens.dart),
lines 566–572, selects properties with outstanding rent, expiry notice or
vacancy. It does not inspect cheque state or cheque date. An occupied,
paid-up property outside its renewal window can have a returned or due cheque
and remain absent from the panel even though its subtitle promises cheque
attention.

The [rental portfolio SQL](../../supabase/migrations/20260811045718_yorks_r38_4_rental_properties.sql),
lines 854–855, separately counts scheduled/received/deposited/returned cheques
dated no later than 30 days ahead. That aggregate is not used to select the
Action Required rows. The next-cheque projection at lines 834–842 excludes
returned cheques, so adding only a next-cheque-date predicate would not cover
returned-cheque attention.

The 30-day aggregate is existing display behavior. It does not establish an
approved external reminder lead time or repeat frequency.

### Rental freshness depends on local commands or manual refresh

The [rental providers](../../lib/shared/providers/yorks_v1_rental_provider.dart),
lines 40–48, are one-shot FutureProviders. Successful commands invalidate the
current client's portfolio/detail at lines 180–182; import invalidates the
portfolio at line 155. There is no normalized-rental realtime subscription or
business-day-boundary refresh in this provider. The compatibility realtime
service does not supply one for these normalized rental tables.

An Admin can leave the page open while another Admin records a receipt or
changes a cheque and continue seeing the older projection. A clock-derived
label can also change without the server's outstanding/current-month summary
being fetched again. Existing employee-document and idle-MR client monitors
are not rental reminder services and do not provide reliable background
operation when the app is closed.

### Partial payment masks an overdue classification

The [period status helper](../../supabase/migrations/20260811045718_yorks_r38_4_rental_properties.sql),
lines 234–239, returns `partially_paid` before checking due date and grace.
Any positive payment below the amount due therefore remains `partially_paid`
even after its grace period has elapsed. The balance remains visible, but a
future reminder that checks only `status = 'overdue'` would miss that debt.

A reminder predicate must evaluate remaining balance and due/grace dates
independently, or an approved projection must expose payment progress and
timeliness as separate facts. Changing retained status semantics needs a
focused compatibility review; this audit does not silently redefine them.

## Business date and timezone findings

Rental lease, period, payment and cheque dates are Postgres `date` values;
creation/audit timestamps are `timestamptz`. This separation is useful and
should remain intact. The due-day generator clamps a configured day 29–31 to
the actual month's final day in the
[schedule helper](../../supabase/migrations/20260811045718_yorks_r38_4_rental_properties.sql),
lines 269–286. No time-of-day conversion is needed for a selected contract date.

However, current rental date decisions have three different origins:

| Surface | Current date source |
| --- | --- |
| Rent due/overdue, outstanding/current month, fixed 90-day expiry KPI and 30-day cheque aggregate | Database-session `current_date`; base rental migration lines 237–238 and 819–855 |
| Lease-expiry export days/status | Database-session `current_date`; import/export migration lines 137–141 |
| Expiry row and per-lease notice filter | Device `DateTime.now()`; rental screen lines 1479 and 4219–4221 |

The portfolio returns `as_of` but no business date or timezone. The
[model parser](../../lib/shared/models/yorks_v1_rental.dart), lines 45–48,
parses date-only values as Dart DateTime values; lines 401–403 even substitute
the device clock if `as_of` is absent. A missing timestamp should not be
presented as proof of a fresh server read.

`leaseEnd.difference(DateTime.now()).inDays` measures complete elapsed
24-hour intervals, not business-calendar days. For example, tomorrow's
midnight can be less than 24 hours away and display as zero days. A different
device timezone, clock skew or a database session with another timezone can
also move a threshold independently. The live database session timezone was
not supplied or independently checked for this subtask, so it is not claimed
to be UTC or Dubai time.

There is a separate definition mismatch: the KPI counts only dates from today
through a fixed 90-day horizon; `expiringSoon` uses each lease's
`renewal_notice_days` and has no lower bound, so expired leases remain in that
filter. These can be legitimate distinct views if named precisely, but they
must not be treated as the same notification threshold.

The [regional configuration seed](../../supabase/migrations/20260814090919_yorks_r38_configuration_centre.sql),
lines 169–175, retains UAE / `Asia/Dubai`. This is evidence for a proposed
rental business timezone, not established operational policy. The later
[configuration control-plane migration](../../supabase/migrations/20260824015124_yorks_v1_configuration_control_plane.sql),
lines 24–55 and 82–92, leaves `regional.timezone` classified as planned;
only selected settings are operational. Reusing that retained setting must
not silently make a planned control operational.

The smallest consistent design, subject to the business-date decision, is:

1. Define one protected rental business-date source using an explicitly
   approved IANA timezone. `Asia/Dubai` is a candidate grounded in the retained
   company configuration; the user's device timezone is not authority.
2. Capture one statement-time instant per command/projection/job, derive its
   business date once, and use it across period status, outstanding/current
   month, expiry and cheque predicates. Preserve date-only source values and
   historical timestamps; do not reinterpret imported dates as UTC instants.
3. Return `business_date`, `business_timezone`, `as_of` and derived
   `days_remaining`/attention flags in the authorized rental projection. The
   client renders those facts instead of recalculating policy using its clock.
4. Refresh the authorized projection on resume, relevant authorized change
   signals and the next server-described business-date boundary. A retained
   projection shows its age; a timer never changes business records or claims
   a command succeeded. Failed refresh must remain visibly stale.
5. Test both sides of the approved midnight, month/year ends, leap February,
   due-day clamping, grace-day equality, expired leases, notice-days other than
   90, device timezone changes and clock skew. If configurable timezones are
   approved, also test daylight-saving transitions and invalid timezone input.

## Acceptance design to prepare after policy decisions

This is a proposed implementation boundary, not an approved new reminder
product policy.

| Area | Required acceptance behavior |
| --- | --- |
| Server evaluation | A protected, bounded job evaluates existing rental obligations. It does not create receipts, clear cheques, renew leases or change financial balances. Public clients cannot choose the run date, recipient, event or message copy. |
| Identity and recipients | Resolve current active identities with the exact server-controlled `admin` role. Recheck current authorization when generating and delivering. Capability overrides, email matching and editable metadata do not grant rental access. |
| Duplicate prevention | Persist a stable notification identity for recipient + actual obligation + approved event/milestone. Atomic unique enforcement and job/root locking prevent duplicate inbox/outbox rows under retries and competing scheduler runs. Define whether repeat milestones exist before choosing the key. |
| Current relevance | Before push/foreground presentation, recheck remaining balance, current lease/archival state and cheque status as applicable. A newly paid or otherwise resolved obligation must suppress pending attention while retaining inbox and delivery history. |
| Durable history | Use the existing recipient-owned `v1_notifications` inbox and hardened outbox. Optional workflow-push preferences affect delivery, not required in-app history. Do not create a second local notification authority. |
| Safe copy | Add reviewed English, Arabic, Urdu and Hindi catalogue copy and generated Dart/TypeScript outputs. OS messages contain no tenant identity, rent amount, bank details or protected document data. Any protected unit/record context is resolved only after an authorized read. |
| Exact destination | Server resolves period/lease/cheque to an existing property and supplies an allowlisted `/rentals/:id` route. Foreground, OS click, cold launch and installed PWA use the same protected destination and acknowledgement path. Unknown/deleted/denied targets fail safely. |
| Freshness | Update Action Required from the same server predicates, including cheque-only cases. Authorized change signals trigger bounded re-fetches; direct normalized-table access is not opened merely to obtain realtime. |
| Operations | Expose last successful rental-job evaluation, bounded failure and per-run candidate/emitted/suppressed counts without tenant/payment payloads. Preserve the existing six-attempt/24-hour transport budget, claim fencing, device ledger, circuit and no-historical-replay behavior. |
| Rollback | Additive schema/migration only. Disable the new producer/job independently; retain business rows, inbox, dedupe and delivery evidence. Do not requeue suppressed historical jobs when resuming. |

Required negative cases include revoked/inactive Admin, every non-Admin role,
malicious destination, forged recipient/date, missing property, archived or
superseded lease, resolved balance, cancelled/cleared cheque, preference change
between enqueue and claim, concurrent runs, job restart, token rotation,
expired push, and late acknowledgement. Positive cases must cover full and
partial balances, approved lease thresholds, cheque lifecycle and every
configured language on desktop and 360px/mobile.

## Current candidate policy and release operations

The implemented candidate follows the coordinating implementation's final
scope: exact active Admin recipients; Dubai business date; daily completeness
review; existing per-lease notice values; once-per-current-milestone due,
overdue, expired and cheque attention; actual confirmed billing only; safe
initial digest-only external delivery; and inactive hourly polling. These are
now concrete candidate behaviors, rather than unresolved implementation
alternatives. No tenant contact channel or broader role access is introduced.

The operator SQL is prepared, **not executed in production**:

1. [Initial source inbox and one completeness digest per Admin](evidence/rental-audit-20261020/rental-initial-inbox-operator.sql)
   verifies disabled controls and shared push health, rejects an initial cohort
   larger than 100 recipient milestones, then evaluates the imported source
   once. Cron remains inactive and the producer returns to disabled while the
   legitimate digest can finish external delivery. Verify actual Admin inbox
   counts, source routes, provider acceptance, OS receipt/click and server
   acknowledgement before continuing. The rehearsed source's 23 obligations
   fit within 100 for the reported three production Admins (69 inbox records,
   at most three fresh digest OS jobs), subject to a fresh recipient/candidate
   count immediately before execution. This arithmetic is not production
   execution evidence.
2. [Enable future rental evaluation](evidence/rental-audit-20261020/rental-enable-future-schedule-operator.sql)
   is a separate release action. It checks current health, inactive cron,
   recorded initial evaluation and a drained current cohort before enabling
   producer/external delivery and hourly cron. New daily/milestone events can
   deliver; initial suppressed rows remain suppressed. If the initial cohort
   exceeds 100 or grows during acceptance, stop for reviewed inbox-only catchup
   rather than enabling a burst from a later batch.
3. [Disable rental evaluation/delivery](evidence/rental-audit-20261020/rental-disable-schedule-operator.sql)
   disables both rental controls and cron without modifying shared transport
   or deleting business/inbox/outbox/ledger rows. A send already accepted by the
   provider cannot be recalled; inspect health after in-flight work drains.

Verify the approved project/host, migration ledger, reviewed candidate artifact
and recipient/policy state before using any operator SQL. Database name alone
is not project identity. No script silently requeues notifications, rewrites
history or changes personal push preferences.

The existing `notification_delivery_check` is localized copy plus a protected
existing-Material-Request target; source inspection found no general self-test
RPC or Settings producer. It is not used as a fabricated rental witness. The
actual first completeness digest provides a legitimate source-backed delivery
check after release approval; until observed, real rental OS delivery remains
unverified.

## Verification performed and remaining gates

On 20 October 2026 the following commands ran against canonical commit
`6222a075e1e0935e34d536f88b7e3c48dc99eb38`:

```bash
flutter test test/yorks_v1_notification_test.dart \
  test/notification_p0_navigation_test.dart test/push_targets_test.dart \
  test/push_installation_lifecycle_test.dart \
  test/notification_delivery_check_test.dart \
  test/yorks_notification_preferences_test.dart \
  test/notification_web_contract_test.dart --reporter compact
node --test supabase/functions/send-push/fcm_failure.test.mjs \
  tool/firebase-messaging-sw.test.mjs
python3 tool/notification_producer_inventory_test.py
```

- **46 Flutter tests passed**, including existing desktop/360px navigation,
  preferences, installation lifecycle and web contract coverage. Flutter
  resolved dependencies using the existing lockfile. The canonical tracked
  worktree remained clean afterward.
- **36 Node tests passed**, covering normalized FCM failures and service-worker
  presentation/click/visibility/expiry behavior.
- **9 Python tests passed**, covering the notification producer-inventory
  tool. This is coverage of that tool, not proof of a missing product producer.

None of these suites contains rental notification acceptance scenarios. The
pass count establishes a useful shared-notification baseline only. No full
Flutter suite, analyzer, release build, database reset/test suite, real FCM
delivery, scheduler concurrency test or named-persona rental UAT was performed
by this notification subtask. Overall audit results may record additional
commands separately; they must not be inferred from this note.

Before deployed rental notification acceptance, complete the full applicable
repository gate and staging validation for this additive candidate. The focused
positive/negative, duplicate, concurrency, Flutter and Edge results above do not
substitute for those release gates. Prove real delivery with one approved fresh rental event: durable inbox
row, bounded outbox claim, provider acceptance, actual OS receipt, click to
the protected property, and server acknowledgement. Repeat the required
browser/device lifecycle and permission/preference cases; a successful FCM
response alone is insufficient. Record candidate commit, migration ledger,
deployment identity, persona, timestamp and artifact/evidence references.

The initial audit was documentation-only; the later authorized local candidate
is described separately above. This note's own document checks are
`git diff --check` plus local-link verification. It does not authorize a
production migration, deployment, scheduler activation or historical replay.

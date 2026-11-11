# Rental notification code review — 20 October 2026

This independent second review covers the rental notification SQL, protected
inbox integration, Edge payload routes and shared event catalogue introduced
between `6222a075` and `5cfdaec`. The original source import is already live;
this review does not repeat it or contact tenants. Production changes belong
to the coordinating release and must be verified separately.

## Corrected findings

1. **P2 — an initial cohort above 100 could alert on later batches.** The
   producer used any successful run as its initialization boundary, including
   a capped run with unprocessed initial obligations. A local two-batch
   reproduction queued seven old obligations externally on the second run.
   The forward migration adds an explicit completion checkpoint and keeps
   every initial batch inbox-only except the approved completion digest.
   Normal external eligibility begins only after the remaining current
   recipient/milestone identities are drained. Existing per-event eligibility
   is preserved and no notification is replayed. The live imported cohort was
   69, so this defect did not compromise that initial production evaluation.
2. **P2 — the Urgent inbox hid overdue rental records.** The catalogue and
   Flutter classify `rental_rent_overdue` as urgent, while the protected SQL
   page filtered only the two Accounts overdue codes. The forward migration
   includes rental overdue in that same recipient-only filter. Ordinary rental
   reminders remain outside Urgent and Accountant receives no Admin feed.

Both fixes are in
[`20261020115421_rental_notification_review_closure.sql`](../../supabase/migrations/20261020115421_rental_notification_review_closure.sql).
The deployed migration files remain unchanged. The new checkpoint backfills
only once: a prior successful batch below the cap is already complete; a
cap-sized last batch is conservatively rechecked under initial suppression.
Reapplying the migration preserves the checkpoint and all business/history
rows. Rollback disables rental generation/delivery/cron and retains evidence;
it must not requeue previously suppressed milestones.

The local two-session test tool also now restores every scheduler control
field after its fixture, preventing the test from leaving initialization
complete in an otherwise empty local database.

## Verification

- New regression suite: **14 pgTAP assertions passed**, including all three
  assertions that failed before the correction.
- New review, existing rental notifications, web inbox history and protected
  record-context suites: **184 assertions in four files passed**.
- Existing fenced Edge handler and payload suites: **30 Deno tests passed**;
  no Edge implementation change was required by this review.
- A real two-independent-session producer race emitted **[0, 2]**, with one
  lease milestone per active Admin and no duplicate. Fixture and scheduler
  checkpoint cleanup were verified afterward.
- The additive migration reapplied successfully; `git diff --check` passed.

Read-only production inspection at **11:52:41 UTC** found all **52 properties**,
**69 rental inbox events**, zero pending rental jobs, enabled rental controls
and an active hourly cron. The first scheduled tick subsequently **succeeded at 12:00:00 UTC** in
approximately 121 ms, emitted zero duplicates, retained all 69 events and left
zero pending rental jobs. The read-only
[first-tick snapshot](evidence/rental-audit-20261020/review-first-scheduler-tick.json)
closes that previously pending scheduler gate. This is transport/server evidence only; physical OS receipt,
notification click and device-specific visual acceptance require their own
witness. The coordinating audit records the final scheduler and release state.


## Additional recovery correction

The coordinating review identified a separate command-recovery gap: a client
restart retains only an uncertain intent's hash/key, so a request that never
committed could leave the user blocked when its exact payload is no longer
available. The additive
[`20261020120051_rental_command_intent_settlement.sql`](../../supabase/migrations/20261020120051_rental_command_intent_settlement.sql)
provides an explicit active-Admin, actor-only resolution command. It shares
the exact ordinary-command advisory lock and returns `confirmed` if the old
command committed. Otherwise it records an `abandoned` fence whose sentinel
cannot equal an ordinary request hash; later delayed old writes fail. The
outcome read distinguishes `abandoned` from `confirmed` and `unconfirmed`.
The client must invoke this only through explicit recovery, never automatically
when payload changes.

An orphan incomplete row's original fingerprint and creation timestamp remain
in protected audit before-data. Deterministic command-scoped child audit keys
avoid collisions when one UUID was independently used for two different
commands. Repeated settlement preserves a single audit event for each command.
The command never returns the original payload and never reads another actor's
outcome or changes that actor's key. There is no shared helper/schema rewrite.

All **37 settlement pgTAP assertions passed**, covering exact-role/active-actor
negatives, invalid inputs, actor isolation, delayed original writes, orphan
fingerprint preservation, repeat settlement, same-key/different-command audit
identity, and real committed-command preservation. Two actual independent
session races then passed both orderings: an old save holding the common lock
committed once and settlement returned `confirmed`; settlement holding the lock
fenced first and the delayed old save failed with no business record. Those
synthetic committed local fixtures were removed by the subsequent disposable
project reset; they were never production data. The coordinating
[release record](RENTAL_CODE_REVIEW_2026-10-20.md) records the full gate and
deployed corrections, including the successful real hourly tick and final
live reconciliation.

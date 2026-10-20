# Rental backend audit — 20 October 2026

This audit covers the normalized rental database, trusted commands, protected
projections, lease schedules, receipts, cheques and source-workbook intake. The
matching workbook and notification investigations are recorded in
[RENTAL_WORKBOOK_AUDIT_2026-10-20.md](RENTAL_WORKBOOK_AUDIT_2026-10-20.md) and
[RENTAL_NOTIFICATION_AUDIT_2026-10-20.md](RENTAL_NOTIFICATION_AUDIT_2026-10-20.md).
The repository's R38.4 architecture and Admin boundary remain authoritative.

## Owner-approved source intake

The owner approved importing the current 52 source rows despite missing
optional facts, with completion warnings and later editing. Annual amounts
remain annual; monthly rent is a separate explicit choice. Blank source status
remains Unknown. Store and Office (Store) retain distinct identities. Missing
location, tenant, contract, contact or date values are not fabricated.

The source workbook has no authoritative receipt history or first tracked bill
date. Every initial source lease therefore has `billing_start = null`, and
imports create **no rent periods, receipts or transactional cheques**. Security
cheque source notes remain protected source evidence. An Admin must explicitly
select the first tracked billing date before charges are generated. Existing
normalized leases retain their pre-existing billing ranges on the first
installation of the additive column; migration replay cannot activate pending
source rows.

## Findings and corrections

| Confirmed defect | Correction |
| --- | --- |
| A stale Admin JWT could still read the portfolio, property detail and export after live role/profile revocation. | The common rental assertion requires the active live Auth/profile boundary as well as exact Admin workflow authority. |
| A property save could reuse another property's lease ID and rewrite that tenant, leaving the edited property with no current lease. | The locked lease must belong to the locked property. Historical leases cannot be silently resurrected. |
| Every occupied-property edit rebuilt the entire schedule; any prior receipt blocked even contact edits, and a linked cheque produced a foreign-key failure. | Metadata edits retain all financial periods and references. Explicit financial revisions preserve retained month IDs and reject paid or cheque-linked schedule rewrites. |
| Null expected versions bypassed cheque-transition and archive conflicts. A missing cheque update could become a create. | Required version checks fail closed; missing update identities are rejected. |
| A deposited, cleared or cancelled cheque could have its banking terms rewritten. | Financial cheque terms are locked in those states; reasoned lifecycle commands remain separate. |
| A new current lease hid previous-lease unpaid rent from the property portfolio. | Outstanding rent includes all preserved leases for the same property. Current-period current-lease KPIs remain separate. |
| A payment allocated to a future period could offset current unpaid rent in the archive guard. | Archive eligibility sums the remaining balance of each due period independently. |
| A partial receipt permanently masked overdue state. | A remaining balance becomes Overdue after the grace period; partial status remains during grace. |
| Annual anniversary iteration could drift after a February 29 start. | Every annual anniversary derives independently from the original billing date. Monthly due-day 31 clamps within each month without drifting the next month. |
| Sparse source updates could clear manually completed optional facts. | Omitted fields merge from the locked current property/lease. Explicit null remains a deliberate clear, protected by financial-history checks. New explicit leases do not inherit an old lease's billing start. |

Original source cells and source identity metadata are immutable once recorded.
Correcting the live property code or type clears its matching recommendation
without rewriting the original workbook evidence. Missing optional fields are
non-blocking warnings; supplied negative amounts, reversed date ranges,
unsupported frequencies and invalid financial transitions remain rejected.

## Contract and preservation

The additive schema permits nullable optional location and lease facts, native
`store` / `office_store` types, Unknown occupancy, `annual_rent`, independent
monthly/annual frequency, explicit `billing_start`, and protected JSON source
metadata. The core unique Unit Code and Property Name remain required.

The Admin projections expose `missing_fields`, `billing_setup_pending`, source
metadata, the Dubai business date, days to lease end and cheque attention.
Annual and monthly rent-roll totals are distinct; neither converts the other.
Exports retain annual frequency, amount, billing and source-evidence fields.

Payment method labels and CDC/PDC choices are normalized to the exact RPC
values before sending or hashing a command. A persisted, actor-scoped command
intent fences each payment period, cheque or archive command. An uncertain
exact retry keeps its original key, including across controller disposal;
changed financial payloads cannot acquire a new key while the earlier outcome
is unknown. A small active-Admin-only outcome read reports only that actor's
`confirmed` / `unconfirmed` state. It never exposes raw request data, and an
unknown/in-flight command is never described as a failed transaction. Auth
session revision changes refresh the local intent namespace. Eight focused
repository/controller reliability tests cover normalized tokens, persistent
retries, changed-payload fences, outcome recovery and actor separation.

The property-detail projection now carries the same server-derived outstanding
and current-period totals as the portfolio, avoiding a misleading zero balance
when only the detail page is opened.

The private `v1_rental_missing_fields_internal(uuid)` helper is callable only
from trusted server code/service role. Its public wrapper rechecks active
Admin authority. The five domain tables retain RLS and no authenticated direct
CRUD grants. New source metadata never goes to a technical-role projection.

The migrations replace existing function signatures and add nullable columns;
they do not backfill source tenants, delete imported records, reinterpret legacy
collections, reallocate receipts, modify cheque amounts, convert rent frequency
or manufacture historic debt. Previous schedules, receipt allocations, cheque
links, document IDs and audit/idempotency evidence remain intact.

Files:

- [Integrity migration](../../supabase/migrations/20261020105617_yorks_rental_record_integrity.sql)
- [Flexible intake migration](../../supabase/migrations/20261020110021_yorks_rental_flexible_source_intake.sql)
- [Integrity regression tests](../../supabase/tests/database/yorks_rental_record_integrity.test.sql)
- [Flexible intake regression tests](../../supabase/tests/database/yorks_rental_flexible_source_intake.test.sql)
- [Existing rental acceptance](../../supabase/tests/database/yorks_r38_4_rental_properties.test.sql)

## Verification

The original three rental migrations in the primary checkout and clean
production-source checkout have identical SHA-256 hashes. A read-only live
query against production `czykuksmlwswjsgotrpo` verified that all 12 checked
rental function bodies match the canonical pre-change repository exactly;
there is no untracked live rental-function drift to overwrite.

The complete tracked migration chain and seed applied successfully to the
separate local Supabase project `yorks_rental_audit_20261020` on database port
55522. Focused tests against that real shared schema passed **136 assertions**:
36 retained rental assertions, 53 integrity assertions and 47 flexible-intake
assertions. The original fixed-date partial-payment expectation now follows
the approved overdue-after-grace rule. All tests roll back their fixtures.
The Supabase CLI security advisor reported no warning/error issues locally.

An earlier isolated PostgreSQL reproduction confirmed each original defect.
Two-session checks then verified that competing payments of 70 against a
balance of 100 commit once and reject the excess writer; simultaneous same-key
payments return the same receipt; and two property edits using version 1
produce one version-2 result and one conflict. Both migrations can be replayed
without activating pending imported billing or removing protected evidence.

The exact Dart-decoded source payload was imported and replayed with the same
command ID against the new trusted import RPC. Reconciliation was:

| Fact | Verified result |
| --- | ---: |
| Source / committed properties | 52 / 52 |
| Preserved leases | 52 |
| Exact source annual rent total | AED 710,238.00 |
| Rows preserving raw source evidence | 52 |
| Rows with completion/billing pending | 52 |
| Generated rent periods | 0 |
| Imported receipts / transactional cheques | 0 / 0 |
| Invented monthly amounts | 0 |
| Duplicate properties after same-key replay | 0 |

Local audit evidence is under
`/tmp/yorks-rental-backend-audit.yRk8H5/`:
`reproduce.sql`, `reproduce.log`, `production-baseline-comparison.json`,
`full-supabase-rental-tests.log`, `full-supabase-security-advisors.log`,
`command-reliability-tests.log`, `command-analyze.log`,
`source52-rehearsal.log`, and `concurrency-results.json`. The original workbook
and generated raw payload remain local evidence and are not committed with
this report. Complete reset/full-suite, Flutter/device/browser, matching
release/deployment and physical-device push evidence are recorded by the
coordinating release task; this backend report does not substitute for them.

## Rollback and operating limits

Before release, take the normal backup and preserve the source workbook hash,
command ID, committed row count and matching build identity. Rollback hides or
stops the new intake/UI and notification producer while preserving all new
columns and business/audit rows. Do not reapply old NOT NULL or enum constraints
to populated incomplete records, remove imported rows, drop schedules, or copy
protected commercial evidence into legacy JSON collections.

Paid or cheque-linked financial terms require an explicit supported business
correction/renewal path rather than editing historical charges. The audit does
not invent proration, automatic annual escalation, receipt reversal/refund, or
missing historical-payment policies. Initial source rows remain safely pending
until their responsible Admin supplies the missing facts and billing start.

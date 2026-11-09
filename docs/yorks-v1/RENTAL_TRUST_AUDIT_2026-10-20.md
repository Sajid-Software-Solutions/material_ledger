# Rental Properties audit and source intake — 20 October 2026

Status: implementation and automated acceptance passed; production schema, push
handler and verified web release deployed. All 52 source properties are imported
and reconciled. Rental reminders are active, with real provider acceptance.
Production browser and physical OS acceptance remain incomplete: the Mac is locked.

The subsequent owner-requested [code review and correction release](RENTAL_CODE_REVIEW_2026-10-20.md)
is now deployed and is the current release record. It closes the first hourly
scheduler witness and records additional financial/import/recovery safeguards;
the original import and snapshots below remain preserved historical evidence.

## Approved outcome

The owner requested the live import of `Yorks Properties.xlsx` and an audit of
the complete rental system, including notifications. During the audit the owner
explicitly approved optional location, contract and other incomplete fields,
later editing, annual and monthly rent options, a template aligned with the
supplied tracker, and recommendations to complete missing details. Type plus
unit identifiers are approved. Missing identifiers/types must remain flagged.
Security-cheque source values must not become cash deposits or paid receipts.

This later rental-only approval supersedes the earlier occupied-lease required
fields in [R38.4](R38_4_RENTAL_PROPERTIES.md). It does not widen rental access:
the exact live active Admin role remains required for every protected surface.

## Evidence and scope

Work is isolated from the dirty primary checkout in the attached
`rental-audit-20261020` worktree, based on the current production source
`6222a075e1e0935e34d536f88b7e3c48dc99eb38`. The twelve production rental
function bodies matched the canonical baseline before any release work.

The source has 52 rows and AED 710,238 of explicitly annual rent. It has no
receipt history or actual cheque register. The original tracker, source values
and both user-supplied workbooks remain preserved. See the detailed
[workbook audit](RENTAL_WORKBOOK_AUDIT_2026-10-20.md) and
[notification audit](RENTAL_NOTIFICATION_AUDIT_2026-10-20.md).
The [backend integrity audit](RENTAL_BACKEND_AUDIT_2026-10-20.md) records the
reproductions, permission/version fixes and real competing-writer checks.

## Resulting behavior

- The original single-sheet tracker and the previous detailed format are
  accepted. Preview is read-only. Missing workbook/header errors are visible
  even when there are no parsed rows.
- Source property type, status, dates, annual amount, contact and security
  notes are preserved. Missing facts remain null/unknown. Source evidence is
  immutable and current property details can be corrected independently.
- Annual and monthly amounts are separate. Switching frequency does not
  convert or relabel the old amount. The template retains the original eleven
  columns and adds optional fields for monthly rent and later completion.
- Missing location, contact, contract, identity, dates, rent or billing setup
  appear in a completion checklist. Correcting current fields clears the
  corresponding recommendation without changing original evidence.
- Imported records have no billing start. They create no inferred historical
  arrears, payment receipts or actual cheques. The owner explicitly selects the
  first rent date to track before unpaid periods are generated. Opening
  balances remain visibly unconfirmed until then.
- Metadata edits retain paid and cheque-linked schedule IDs. Critical writes
  reject stale versions, wrong-property lease IDs and unsafe schedule changes.
  Terminal cheque financial facts remain protected. Historical unpaid debt
  stays visible, and future prepayments cannot mask another period's debt.
- Rental views refresh while open and discard protected cached projections on
  session/permission changes. Dates use the server's explicit Asia/Dubai
  business date. Overdue partial balances remain overdue after grace.
- Failed payment/cheque/archive responses retain command identity for an exact
  retry. Stored intent references contain hashes and UUIDs, not tenant or rent
  payloads. Concurrent UI commands are guarded.
- Rental notifications reuse the existing durable inbox and bounded push
  outbox. Exact active Admin recipients, current-obligation rechecks, stable
  milestone deduplication, preference checks and protected rental destinations
  are enforced on the server. Source-completion reminders are a daily digest.
  First-import notification activation must avoid an OS alert burst.

The first production-shaped build measured 2,903,934 gzip bytes, exceeding the
unchanged 2,900,000-byte startup limit. Rental routes now use the application's
existing deferred-library loading/retry pattern. Role guards, paths and screen
behavior remain the same; the rental editor loads when its guarded route opens.
The transfer ceiling is not raised.

## Verification

Local evidence includes a complete 52-row server rehearsal and same-key replay with zero
periods, receipts or cheques and the original annual total unchanged.

The final pre-release gate passed:

- `flutter pub get`; formatting check on all changed Dart files; clean full
  `flutter analyze`;
- full `flutter test`: 2,862 passed with four retained skips;
- isolated local `supabase db reset` and `supabase test db`: 4,788 assertions
  across 140 files passed, without resetting the pre-existing local project;
- CI web build: 9,899,119 raw / 2,850,861 gzip bytes for the main bundle, below
  the unchanged startup ceiling;
- CI APK build with explicitly permitted ephemeral signing: passed. This is
  build validation, not an Android distribution release;
- 30 Edge transport tests, actual independent-session quantity/property and
  notification races, source preservation, protected destinations and
  payment timeout/offline recovery checks;
- desktop and 360px visual review, all 120 checked internal documentation links
  valid, generated notification catalogue current, and `git diff --check` clean.

The first complete Flutter run exposed a notification-fixture assumption and
a refresh timer surviving a failed load. Both were corrected and the whole
suite rerun successfully. No unrelated failure was suppressed or rebaselined.

Dedicated staging `iqltcyimlqtcwyzlemwx` accepted the exact three migrations as
`20261020112615`, `20261020112622`, `20261020112632`. The send-push Function is
version 6 and retains its existing webhook authentication mode. The actual
source imported successfully inside a rollback-only rehearsal: 52 properties,
52 incomplete records, AED 710,238 annual rent and zero generated rent periods.
Staging returned to zero properties; rental producer/cron remain off. Security
advisors have no ERROR-level findings and retain their existing advisory
categories. This is backend rehearsal evidence, not named-persona browser UAT.

## Preservation and rollback

Migrations add columns and replace bounded RPC bodies without deleting business
records or modifying legacy collections. Existing IDs, receipts, cheques,
documents, schedules, attribution and audit history are retained. Producer
control and its cron job default off until acceptance. To contain a release,
disable the rental producer and cron and promote the retained prior web
deployment. Keep imported records and evidence. Do not restore old NOT NULL or
enum constraints over newly accepted incomplete records, or drop populated
relations. Use a reviewed forward correction for database defects.

## Release evidence

Production migration versions are `20261020114049`, `20261020114054` and
`20261020114058`, respectively. The production `send-push` Function is version
16; all five deployed files equal the reviewed source and retain the existing
webhook authentication. Its bundle SHA-256 is
`c4bd461168e4d0b92f62310f990d89feb384df5d09d604ce6baf4a29c75da826`.

The clean implementation commit is
`2c844c08bb06112c2db288f19da2955b82265b6c`. Production configuration preserves
Accounts, Workforce, Analytics, Company Requests, Project Setup, Calculator
Workspace, FCM and PostHog. The production main bundle is 9,962,172 bytes /
2,871,425 gzip bytes, below the unchanged startup ceiling. Its SHA-256 is
`e0a26e777f1bc727204e235ad3a5f85e9930c4885a9418571861abdf0512dc67`.

Deployment `dpl_AAZBeSPhGcR6Rj8Cjssk3Ckq5F3u` was verified before promotion:
<https://yorks-r35-4aly5ytvn-sajid-alis-projects-0ec775a2.vercel.app>.
All 34 route/asset checks passed for both the immutable deployment and
<https://yorks-r35.vercel.app>. The canonical domain resolves to that deployment.
The prior deployment remains available as
`dpl_6kHrXZ3yHFrJA41vLhcimN9xFWdZ` for web rollback.

Production security advisors retain the four previous advisory categories and
no ERROR-level findings. Added findings are expected: two service-only rental
notification tables with RLS and no client policy, and two authenticated RPCs
with explicit active-Admin/actor checks. Anonymous execution has not expanded.
All seven rental tables have RLS enabled and no anonymous/authenticated direct
table CRUD grants. Shared push health has no pending/retry jobs, pause, circuit
or global error; its worker is current. Historical dead letters remain intact.

The Mac was locked and native browser control could not proceed. The exact
application-codec workbook payload was instead imported through the audited
production `v1_import_rental_workbook` command under the existing Owner Admin
actor, with the owner's explicit live-import authorization. No direct domain
table inserts or generated payment facts were used. The command ID is
`d5ad4340-38a2-4e24-a718-44ca2e1bbde8`; the import audit is retained once.
An exact same-key replay returned the original result with no new rows/audit.

Live reconciliation confirms 52 properties, 52 leases, 39 annual amounts
totalling AED 710,238, zero monthly amounts and all 572 original source cells
matching. Codes, amounts, frequency and immutable source metadata have zero
mismatches. Periods, receipts, actual cheques and cash security deposits remain
zero. The Owner's protected application projection returns all 52 records,
46 occupied, 19 expiring within 90 days, and 52 completion/billing-setup warnings.
Zero recorded charges is not proof of a settled balance: each opening remains
unconfirmed until an Admin explicitly sets billing tracking.

The initial notification evaluation generated 69 inbox entries for the three
active Admins: three count-52 completion digests, nine expired-lease entries
and 57 notice entries. Only the three digests entered the push outbox; all 66
initial lease milestones are permanently inbox-only. Actual first-attempt FCM
acceptance is recorded for the Owner's four devices and one other Admin device.
The third Admin has no registered device; that digest has terminal `no_devices`
delivery and remains in the protected inbox. There are no pending/retry jobs,
new dead letters, circuit/global errors or duplicate milestones. Same-day
evaluation emitted zero new entries and zero external candidates.

After health and drained-cohort checks, the rental producer, external delivery
and hourly cron (`0 * * * *`) were enabled. Existing suppressed milestones were
not replayed. The first scheduled hourly tick had not yet occurred at the
recorded snapshot. The [release evidence](evidence/rental-audit-20261020/production-import-notifications.json)
contains the actual counts, provider outcomes, protected projection and limits;
the candidate/canonical asset manifests and artifact hash are saved alongside it.

The production file-picker interaction, rendered post-import register, actual
OS receipt/click and server `seen_at` acknowledgement were not witnessed because
the Mac remains locked. Desktop/360px UI evidence and full automatic tests
passed; provider acceptance is a separate verified result. Every device/browser
state and an extended production soak remain outside this acceptance record.

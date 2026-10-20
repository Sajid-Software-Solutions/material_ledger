# Rental Properties audit and source intake — 20 October 2026

Status: implementation and acceptance checks in progress. This document does
not record a production import or release until the evidence below is updated.

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

Acceptance records will be appended after final gates. Local evidence already
includes a complete 52-row server rehearsal and same-key replay with zero
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

Pending final gate, staging validation, exact migration/Edge deployment,
immutable web candidate verification, canonical promotion, live UI import and
post-import reconciliation. Local fixture tests alone do not establish real OS
delivery, every device/browser state, or an extended production soak.

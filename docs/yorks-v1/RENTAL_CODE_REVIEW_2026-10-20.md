# Rental code review and corrections — 20 October 2026

Status: independent review, regression fixes, staging and all integrated gates
passed; the corrections are deployed to live Yorks. All 52 source properties
are reconciled. Physical production browser/OS checks remain unavailable while
the Mac is locked.

The owner requested a code review of the rental changes, resolution of open
states and bugs, and publication of the rental data to the website. The review
covers the changes from `6222a075` through `5cfdaec`, with separate database,
Flutter/import and notification reviewers and cross-review of new recovery SQL.
The original [release record](RENTAL_TRUST_AUDIT_2026-10-20.md) remains historical
evidence; no business facts are overwritten merely to repeat the upload.

## Findings and corrections

| Finding | Correction and regression evidence |
|---|---|
| Concurrent payment and rent-schedule editing used conflicting lock orders, causing a PostgreSQL deadlock that rejected valid payment. | Property → lease → period ordering. An independent-session race now retains the original charge and receipt, and rejects unsafe repricing. |
| PostgreSQL accepted NaN as nonnegative money; sub-cent receipts could be rounded in storage while the response reported another amount. | Finite numeric constraints and explicit exact-cent payment/cheque validation. Invalid input is rejected without financial effects. |
| A cheque could be created against an archived property. | The trusted command checks the locked property and rejects new obligations on archived records. |
| Correcting a Unit Code and uploading the original tracker again could create a second record for the same immutable source row. | Preview identifies complete original-row evidence; a unique canonical source fingerprint enforces the same rule under concurrent direct RPC requests. No row-position guessing, merging or source rewrite. |
| Cheque and archive dialogs could discard entered data before a write was confirmed. | Editors retain values, freeze uncertain submissions and retry the original command. Dismissal is disabled while a command is running. |
| Import preview could be closed through its header during confirmation. | The header close action observes the same running-command guard as other dismissal paths. |
| Property/import command keys could be lost on closing or reopening after a timeout. | Actor-scoped persisted hashes/UUIDs now cover all six rental command types. Exact retries retain their key without persisting tenant/payment payloads. |
| Changed input after an uncertain, already committed payment could automatically submit a second payment. | Recovery is explicit and stops after resolving the earlier result. A new financial action requires another submission. |
| A persisted unfinished command with no recoverable input could permanently block later work. | An active-Admin, actor-scoped settlement RPC shares the original command's advisory lock. It preserves committed outcomes or fences an uncommitted key against late requests, with an audit event. The UI exposes explicit review and resolution. |
| A rejected retry could clear a previously uncertain command fence while its earlier request was unresolved. | Every rejected retry retains its fence until explicit settlement; an initial definitive rejection still allows corrected input. |
| Switching actors or disposing a controller during a command could affect the wrong pending state. | Actor identity is checked after persistence and response; late/disposed completions retain the original actor's reference without a late state write. |
| Two command types sharing a UUID could collide on the abandonment audit key. | The settlement audit key is deterministic and command-scoped; both commands settle independently, retaining the previous orphan request hash in protected audit evidence. |
| The old detailed workbook format still required now-optional facts and could select annual frequency with only a monthly amount. | Optional fields and sparse updates follow the owner's later approval; annual/monthly amounts remain separate and conflicting supplied values fail preview. |
| The Urgent notification filter omitted rental overdue events. | The protected recipient-only page includes `rental_rent_overdue`; role isolation remains enforced. |
| An initial notification cohort above 100 could send old milestones externally on a later batch. | A durable initialization checkpoint remains incomplete until all initial recipient/milestone identities are represented; earlier inbox-only events are never requeued. |

The original three deployed migrations are unchanged. Corrections are additive:

- [Financial serialization and source identity](../../supabase/migrations/20261020115356_yorks_rental_financial_serialization.sql)
- [Notification filtering and initial batching](../../supabase/migrations/20261020115421_rental_notification_review_closure.sql)
- [Explicit unfinished-command settlement](../../supabase/migrations/20261020120051_rental_command_intent_settlement.sql)

## Live state and acceptance boundary

Read-only preflight confirms 52 properties, 52 leases, AED 710,238 annual rent,
52 distinct complete original-source fingerprints and no non-finite amounts.
Periods, receipts and actual cheques remain zero. All 572 original cells were
reconciled in the initial release. The actual protected live response also
decodes successfully through the Dart model: 52 annual records, 39 supplied
annual amounts and 52 explicit billing/completion warnings.

The first real hourly cron tick succeeded at 12:00 UTC in approximately 121ms,
emitted zero duplicates and left no pending rental jobs. Its [snapshot](evidence/rental-audit-20261020/review-first-scheduler-tick.json)
closes the previously pending scheduled-run check. The existing provider
acceptance covers five registered devices. One Admin has no registered device
and retains the required inbox reminder.

The Mac remains locked. Production browser file selection/rendering, physical
OS receipt/click and the resulting acknowledgement are not recorded as passed.
Automatic tests, server reconciliation and provider acceptance are separate
evidence. No tenant was contacted, no opening balance inferred, and no prior
notification or business history was deleted.

## Integrated verification and follow-up release

The integrated gate passed:

- `flutter pub get`, formatting of eight changed Dart/test files (zero changes),
  clean full `flutter analyze`, and `git diff --check`;
- full `flutter test`: **2,880 passed**, four retained skips;
- isolated `supabase db reset --local` and full `supabase test db --local`:
  **4,876 assertions across 143 files passed**; the developer's original local
  project was not reset, and only the audit stack is stopped afterward;
- CI web build and unchanged startup ceiling: main bundle 9,902,069 raw /
  2,851,778 gzip bytes, index 11,024 bytes;
- CI release APK build with explicitly enabled ephemeral signing: passed,
  114.1MB. This is build validation, not a distribution release;
- focused recovery, cheque/archive, import/codec and payment tests; desktop
  1366px and 360px recovery goldens visually reviewed; real competing-writer
  payment/edit, import/source identity, archive/cheque, producer and both
  settlement/save race orderings passed;
- 30 unchanged Edge transport/payload tests passed in the independent review.

Dedicated staging applied the exact new migrations as `20261020120929`,
`20261020120932` and `20261020120935`. All eight replaced/new function bodies
match the reviewed local source and deny anonymous execution. A rollback-only
actual-source rehearsal retained 52 properties/leases/source fingerprints,
annual rent AED 710,238 and zero periods/receipts/cheques; settlement preserved
the completed import. Staging returned to zero properties with rental producer
and cron off. Security advisors have no ERROR-level findings; existing
platform advisories remain recorded rather than silently changed by this task.

## Verified follow-up release

The clean implementation commit is
`e1015f5fab3db4c4f9993b0939cda87049c20709`. Production preserves all existing
Accounts, Workforce, Company Requests, Analytics, Project Setup, Calculator,
FCM and PostHog configuration. The production main bundle is 9,965,112 raw /
2,872,493 gzip bytes measured by the unchanged Dart startup verifier. SHA-256:
`74f816e18549d25105a9de1352e05f271999e8006a127bb2a643658ad9bb04d0`.
No staging/CI backend, service-role JWT or private key appears in the artifact.

Production migrations are `20261020121453`, `20261020121456` and
`20261020121459`. All eight updated/new function bodies match the reviewed
source, and all seven rental tables retain RLS without direct client CRUD.
The source identity index is valid/unique and all four finite-money constraints
are validated. The unchanged `send-push` Function remains version 16. Security
advisors have no ERROR-level findings; anonymous definer findings remain the
same two historical functions, and the new authenticated settlement RPC is
guarded by the tested exact-active-Admin/actor checks.

Deployment `dpl_ABmQsPZ2TefLjD9PWYiZLKewSRP1` was checked before promotion:
<https://yorks-r35-ppgjwz916-sajid-alis-projects-0ec775a2.vercel.app>.
All 34 route/asset hashes passed for both this immutable deployment and
<https://yorks-r35.vercel.app>. The canonical domain resolves to that exact
deployment. The prior artifact `dpl_AAZBeSPhGcR6Rj8Cjssk3Ckq5F3u` is retained.

The authorized original import command was safely replayed with its original
key, then reconciled again: **52 properties, 52 leases, 572 preserved source
cells, 52 unique original identities, AED 710,238 annual rent, zero source/code/
amount/frequency mismatches and exactly one import audit**. No periods,
receipts, actual cheques or inferred historical balances were created. All 52
incomplete records retain their completion/billing-setup warnings.

Rental generation, external delivery and hourly cron remain enabled. The new
producer executed under normal controls with initialization complete, emitted
zero and queued zero external candidates. There are still 69 initial inbox
events, no duplicate milestone groups, no outbox rows for the 66 suppressed
initial lease milestones, and zero pending/retrying push jobs or new dead
letters. The Owner's prior digest remains provider-accepted on four devices;
its `seen_at` remains unset. The Mac lock still prevents a physical click or
visual acceptance witness, so those limits are explicitly retained.

The [production evidence](evidence/rental-audit-20261020/review-production-release.json),
[artifact measurements](evidence/rental-audit-20261020/review-production-artifact.json),
[immutable checks](evidence/rental-audit-20261020/review-verify-candidate.jsonl)
and [canonical checks](evidence/rental-audit-20261020/review-verify-canonical.jsonl)
record the concrete release. The existing dated import template remains valid;
neither supplied workbook was overwritten. The isolated audit database was
stopped after its successful full gate; the original local services remain.

Rollback preserves the source, constraints, idempotency fences and audit rows.
Disable rental generation/external delivery/cron if containment is needed, and
promote the retained prior web artifact. Do not remove an abandonment fence or
reuse its key: that would permit a delayed old request to execute.

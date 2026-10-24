# Material Request draft audit and repair plan — 7 October 2026

Status: original audit complete. The subsequently authorized implementation, cleanup and verification are recorded in [the repair report](MATERIAL_REQUEST_DRAFT_REPAIR_20261007.md). Findings below describe the pre-repair state.

## Finding

The recurring Delete Draft failure is a lifecycle reconciliation defect. A device recovery row can still say “unsaved draft” after its UUID already became a saved/submitted Material Request. The UI offers recovery deletion, while the server correctly refuses to remove a business record through that command.

This needs coordinated client/server recovery handling. Removing the server guard, retrying the same command, refreshing the page alone, deleting every cloud snapshot, or treating an authorization error as “draft absent” would be unsafe fixes.

## Evidence and scope

- Source baseline: `3efc0699ebe821213346a44eec5dc7f204791ef9`, verified against remote `main` when the audit started.
- Isolated branch: `codex/mr-draft-lifecycle-audit-20261007`. The original dirty checkout was preserved.
- Production Supabase: `czykuksmlwswjsgotrpo` (`yorks-godownpro-demo`, despite its historical name). Dedicated staging is `iqltcyimlqtcwyzlemwx`.
- PostHog: project `600792`, UTC reporting configuration.
- Analytics interval: **24 September 2026 00:00 through 7 October 2026 15:05 PKT**, end exclusive (`2026-09-23T19:00:00Z` to `2026-10-07T10:05:00Z`).
- Production/schema-v2 events only. Counts below are ad hoc debugging aggregates, not an approved catalog metric. The catalog was empty.
- Production database reads occurred around 15:02–15:11 PKT. This is a live audit across several queries, not one transactionally frozen backup.
- Inspection included every normalized Project draft, every private cloud recovery row, retirement markers, Company MR rows, the legacy `materialRequests` collection, deployed RPC bodies/grants, relevant foreign keys/triggers, Flutter models/providers/controllers/routes/UI, analytics classification, and existing tests.
- No production writes, user impersonation, request deletion, migration, deployment, flag change, or PostHog configuration change occurred.
- No employee device storage was inspected. Local-only drafts and exact affected browser contents cannot be enumerated from Supabase.

## Measured impact

| Operation | Measured outcomes | Success | Failure | People measured | People with failures |
|---|---:|---:|---:|---:|---:|
| Delete Draft | 36 | 9 | 27 (75%) | 6 | 5 |
| Save Draft | 14 | 10 | 4 | 6 | 2 |

Do not add `material request draft delete failed` to failed `operation completed` events: they describe the same logical attempts. These counts include production-tagged Admin/operator activity; they do not prove every employee encountered the defect.

| Delete environment | Measured | Failed |
|---|---:|---:|
| Admin, macOS Chrome | 18 | 14 |
| Project Engineer, Windows Edge | 6 | 5 |
| Project Engineer, Windows Chrome | 3 | 3 |
| Workshop In-Charge, Android Chrome | 5 | 3 |
| Site Engineer, Android Chrome | 2 | 2 |
| Site Engineer, macOS Chrome | 2 | 0 |

The screenshot reproduces exactly in PostHog: **3 attempts, 3 failures** on 7 October at **14:30–14:31 PKT**, Workshop In-Charge, Android/Chrome, release `74a6fd599bdcfbdbbce7c63cbaa5611037645aea`. Durations were **368 ms, 937 ms, and 2,121 ms**. The median is 937 ms, matching the screenshot.

Supabase PostgreSQL logs in that interval contain four `V1_PRIVATE_DRAFT_ALREADY_SAVED` responses with SQLSTATE `55000`. This is a terminal workflow mismatch, not evidence of malformed material rows. The event pipeline groups `invalidTransition` under `validation`, explaining the dashboard label.

The timestamps and deployed code support the diagnosis strongly. Privacy-safe analytics deliberately omit request IDs, so there is no one-to-one event-to-request identity join and the fourth server response cannot be attributed to a specific measured click.

The four Save Draft failures were `permission_denied` for two Project Engineers on 29 September. Resuming a progressed UUID through the draft-save RPC can produce this category, but the historical events do not retain the server reason; this is a hypothesis, not a proven explanation for those four failures. Do not weaken permissions to suppress them.

## Production inventory

There are **19 distinct current draft identities** across the normalized/private stores: **10 saved Project drafts + 9 private-only drafts**. The four overlaps below are counted once.

| Storage/state | Rows | Interpretation |
|---|---:|---|
| Normalized Project requests in `draft` | 10 | Genuine saved drafts; 70 material lines; none previously submitted |
| Private cloud recovery snapshots | 54 | 376 snapshot lines, across 12 owners |
| Private-only snapshots | 9 | No normalized request yet; four have one line, five have zero lines |
| Recovery snapshots overlapping saved drafts | 4 | Preserve and compare; one has newer additional work |
| Recovery snapshots overlapping progressed requests | 41 | Historical recovery data, not additional active business drafts |
| Retirement markers | 9 | Across four owners; preserve anti-resurrection evidence |
| Company requests, all states | 0 | No production Company drafts to reconcile |
| Legacy `materialRequests` records | 0 | No legacy cloud drafts to migrate |

The 41 progressed overlaps are: 18 closed, 11 arranging, 5 cancelled, 3 received, 2 approved for arrangement, 1 awaiting request approval, and 1 approved. Every one had a recovery timestamp older than its normalized request timestamp. That alone is not permission to destroy its contents.

There are no owner mismatches between the 45 overlapping snapshots and normalized requests, and no retirement marker overlaps among the 54 snapshots. A bounded scan found no top-level line keys `unit_cost`, `total_cost`, or `currency_code` in the private snapshots. This is not a complete commercial-leakage or RLS proof.

All 10 saved drafts have active owners, active projects and active scopes. They have no nonpositive quantity, blank description/unit, or broken source BOQ linkage in the structural checks performed. All are version 1. None has submission, decision, dispatch or revision-snapshot history. One has a retained comment and must not be hard-deleted with linked history.

### Every saved Project draft

Audit aliases below are ordered by creation time; business names and UUIDs are intentionally omitted from this repository report.

| Audit row | Owner role | Created (UTC date) | Lines | Cloud recovery copies |
|---|---|---|---:|---:|
| D01 | site_engineer | 2026-08-14 | 12 | 0 |
| D02 | site_engineer | 2026-08-26 | 26 | 1 |
| D03 | admin | 2026-08-27 | 2 | 0 |
| D04 | admin | 2026-08-28 | 9 | 0 |
| D05 | admin | 2026-09-18 | 1 | 0 |
| D06 | admin | 2026-09-18 | 1 | 0 |
| D07 | admin | 2026-09-18 | 1 | 0 |
| D08 | project_engineer | 2026-09-28 | 13 | 1 |
| D09 | site_engineer | 2026-09-30 | 3 | 1 |
| D10 | project_engineer | 2026-10-05 | 2 | 1 |

**D02 is a preservation exception:** its saved request has **26 lines**, while its later private recovery snapshot has **27**, including **one line ID absent from the saved request**. It also has one retained comment. A blanket cleanup or unconditional preference for the normalized row could lose unsaved work or discussion history.

D08, D09 and D10 also have recovery copies. Their line IDs/counts match, but this audit did not claim complete equality of every field. Compare canonical non-commercial payloads before clearing or suppressing divergent content.

### Every private-only account draft

| Audit row | Owner role | Last sync (UTC date) | Lines | Sync version |
|---|---|---|---:|---:|
| R01 | site_engineer | 2026-08-21 | 1 | 4 |
| R02 | site_engineer | 2026-08-23 | 0 | 2 |
| R03 | site_engineer | 2026-08-27 | 1 | 7 |
| R04 | project_engineer | 2026-09-03 | 1 | 3 |
| R05 | site_engineer | 2026-09-14 | 0 | 4 |
| R06 | site_engineer | 2026-09-16 | 0 | 1 |
| R07 | project_engineer | 2026-09-17 | 0 | 5 |
| R08 | site_engineer | 2026-09-18 | 1 | 4 |
| R09 | project_engineer | 2026-09-21 | 0 | 4 |

All nine owners, projects and scopes were active in the checks performed. Zero lines is a permitted incomplete recovery draft, not corruption or proof of abandonment.

## Defects and contributing gaps

### P1 — Device/cloud/workflow state is not reconciled

[`yorks_v1_material_request_provider.dart`](../../lib/shared/providers/yorks_v1_material_request_provider.dart) filters device rows using the stored `serverRecordVersion == 0`. It does not establish current server lifecycle for those UUIDs.

The deployed `v1_list_my_material_request_private_drafts` excludes any UUID in `v1_material_requests`, while `_mergeRecoverableDrafts` in [the Material Request screen](../../lib/features/materials/presentation/screens/yorks_v1_material_request_screens.dart) merges device rows back using timestamps. Absence from the cloud list is not interpreted, and must not be interpreted, as proof of deletion.

Result: a stale device row can reappear as an actionable private draft after Save/Submit on another device, a lost response, or local cleanup failure.

### P1 — Delete reports a dead end instead of resolving “already saved”

[`discardLocal`](../../lib/shared/controllers/yorks_v1_material_request_draft_controller.dart) sends recovery deletion. The server deliberately raises `V1_PRIVATE_DRAFT_ALREADY_SAVED` when any normalized request exists.

The UI refreshes only the account index. The local row persists and the same Delete remains available. Its `invalidTransition` message says a Save/Submit is “still being checked,” even when a durable saved/approved/closed request already exists.

The server safety guard is correct; the missing reconciliation/action model is the defect. A repaired UI must never call this “Draft deleted” unless an actual private draft was acknowledged deleted.

### P1 — Resume can revive an obsolete editing context

The deployed `v1_get_my_material_request_private_draft` checks actor ownership and retirement, but unlike the list function does not exclude an existing normalized request. The private resume route hydrates that snapshot without first resolving the current request lifecycle.

The client understands the `DELETED` terminal code, but has no corresponding authoritative “saved elsewhere / submitted elsewhere” recovery state. A progressed recovery snapshot can therefore enter a draft editor, then fail Save or sync instead of opening its existing request.

### P1 — Post-submit cleanup cannot use the private-delete contract

After a confirmed submission, `discardLocal(submissionConfirmed: true)` best-effort calls private deletion when a sync version is known. The same delete RPC rejects every normalized UUID. Its error is swallowed to preserve the successful workflow outcome.

This explains why retained cloud snapshots accumulate. It does not prove that every affected device failed its local cleanup. The successful submission must remain successful; recovery reconciliation/retirement needs its own contract.

### P2 — Saved drafts with newer recovery work need explicit comparison

The list function hides all normalized overlaps, including D02's extra line. A simple “prefer server and remove recovery” fix would conceal or destroy work. Preserve both snapshots, compare semantic content, and offer explicit review of differences under the saved request's current authorization/version.

### P2 — Legacy normalized deletion is not ready to become a UI shortcut

The still-callable `v1_delete_material_request_draft(uuid)` only checks `state='draft'` and creator equality, then deletes lines and the request. It has no explicit active-actor, expected-version, idempotency, never-submitted or audit check. No current UI caller was found.

Foreign keys retain linked history, including D02's comment; do not remove those constraints to make deletion succeed. This is a separate hardening requirement before exposing saved-draft deletion. No destructive production test was performed.

### P2 — Recovery list reachability and freshness

The notice renders only the first three rows in compact mode or five otherwise without a list-expansion control in that component. Additional device/account drafts can become inaccessible through this notice. The cloud RPC supports 50 by default and caps at 100 without a cursor.

The account index is auto-disposed/refetched on reopening and explicitly after delete, but has no equivalent permission/realtime/foreground invalidation contract to the main request register. Address this without restoring a cloud RPC per keystroke.

### P2 — Diagnostics hide distinct recovery outcomes

The broad `validation` bucket conflates stale workflow identity with invalid form input. Add only bounded outcomes such as `already_saved`, `already_submitted`, `retired_elsewhere`, `version_conflict`, `pending_confirmation`, `permission_denied`, and `storage_failure`. Keep IDs, payloads and raw errors out of PostHog.

### Coverage boundary — Company drafts

Company drafts use a separate composer and saved-request RPCs; no rows exist in production. The composer holds unsaved input in widget state and offers Save/Discard on navigation. Project recovery guarantees must not be assumed to apply to it. Company offline/refresh/lost-response behavior needs its own acceptance cases; it is not evidence for this Project delete incident.

## Concrete repair plan

### Slice 1 — Authoritative recovery classification and truthful actions

1. Introduce a bounded, owner-scoped recovery reconciliation projection for candidate local UUIDs. Resolve **private**, **saved draft**, **submitted/progressed**, **retired**, **pending receipt**, and **unavailable/denied** distinctly.
2. Keep the result metadata-only until the user opens a record. Recheck active identity and applicable project/capability access. Unknown/denied is never “absent.”
3. Share that result between register, dashboard, resume, delete preflight and post-command cleanup. Realtime remains an invalidation signal.
4. Offer Resume/Delete only for an authoritative private draft. Offer Open Request for progressed records. Offer Review Recovered Changes for a saved draft with divergent input.
5. Preserve unconfirmed Save/Submit intent and idempotency identity until receipt reconciliation. Offline keeps local content and an honest unverified state.
6. If a race still reaches `ALREADY_SAVED`, re-fetch classification and show the existing-record action; do not re-offer an impossible delete or emit a deletion-success event.

### Slice 2 — Durable retirement and safe recovery preservation

1. Separate “delete my unfinished private draft” from “this recovery snapshot has been superseded by a confirmed business request.”
2. Preserve saved-draft edits and every unresolved/divergent snapshot. D02 must be a mandatory fixture.
3. For confirmed progressed requests, mark recovery as superseded under the same deterministic UUID/owner lock used by private Save/Delete. Preserve historical bytes until the retention policy is explicit; do not bulk-delete production snapshots in this change.
4. Make delayed autosave/old-device resume observe the terminal lifecycle. Keep retirement markers and prevent stale UUID resurrection.
5. Server acknowledgement precedes local cleanup; local cleanup failure is independently retryable and never reverses the business outcome.
6. Harden any normalized delete command separately with active actor, scope/capability, expected version, never-submitted/history checks, idempotency and append-only audit. Preserve foreign keys and return a bounded domain denial for linked history.

### Slice 3 — Usable list and diagnostic coverage

1. Provide access to every draft, with visible local/account/needs-review/pending-confirmation status and explicit refresh failure.
2. Invalidate owner projections on identity/permission changes, foreground resume and relevant server changes. Debounce/coalesce; never fetch on each keystroke.
3. Preserve English and configured secondary languages and at least 44×44 mobile targets.
4. Distinguish reconciliation from deletion in telemetry and in the dashboard. Do not relabel historical failures as successes.

### Slice 4 — Verification and staged release

Add tests that the existing happy-path fakes miss:

- Two devices: private on A; Save, Submit, Cancel and Close on B; A opens, resumes and deletes.
- Same-ID private + saved draft with 26 versus 27 lines; preserve the extra line and retained comment.
- Private list absence versus authoritative deletion; 50/100-row boundaries and more than five visible drafts.
- Late hydration/autosave during Save, Submit and Delete; both transaction commit orders in real independent database sessions.
- Exact retry, lost response, device persistence failure, tab close, auth switch, membership/capability revocation, inactive user and anonymous calls.
- Project Engineer, Site Engineer, Procurement and Admin positive/negative boundaries; exact Workshop In-Charge incident persona.
- No commercial values in read models, caches, exports or diagnostics.
- Desktop and 360px English/RTL visual evidence for private, saved elsewhere, recovery review, pending, conflict, offline and failure states.
- Company draft creation/resume/save/exit remains a separate regression lane.

Then run the complete applicable Flutter, fresh local Supabase/pgTAP, real concurrency, web and Android gates. Build one staging candidate, witness the actual Android Chrome/PWA flow, and verify the PostHog outcomes. Production migration/promotion and any data cleanup remain explicit release decisions. Observe real outcomes after release before claiming the problem is resolved for everyone.

## Exact implementation surface

- Models: `lib/shared/models/yorks_v1_material_request.dart`, localized MR strings, bounded analytics vocabulary.
- Repositories/store: `lib/shared/repositories/yorks_v1_material_request_repository.dart`, existing preservation-safe draft store.
- Controllers/providers: MR draft controller, local/private indexes and authority invalidation in MR provider.
- UI/routes: MR screens and centre, draft entry-mode resolution; existing GoRouter destinations.
- Database: new forward-only migration over recovery list/get/sync/delete and proposed reconciliation/retirement commands; normalized deletion hardening separately bounded.
- Tests: draft deletion/reliability/controller tests, provider/route/widget/golden tests, pgTAP deletion and reliability suites, existing two-session concurrency harness.
- No changes to stock, approval quantities, dispatch, receipt, Inventory, Rentals, People/HR or Accounts semantics.

## Current validation

Current baseline `3efc069`, before any behavior change:

- `flutter pub get`: passed.
- `flutter analyze`: passed, no issues.
- Focused `flutter test test/yorks_v1_material_request_draft_deletion_test.dart test/yorks_v1_material_request_test.dart`: **96 passed**.
- Full `flutter test`: **2,503 passed, 4 skipped**, no failures.
- Database reset/pgTAP and concurrency were not run: Docker was not running. Production RPCs were inspected read-only, not exercised as mutation tests.
- Web/APK builds and new desktop/mobile visual evidence were not produced for this audit-only change.
- The passing baseline does not cover or disprove the live cross-store defect.
- Documentation whitespace and internal-link checks: passed.

## References

- [Draft lifecycle contract](MATERIAL_REQUEST_DRAFT_LIFECYCLE.md)
- [Product decisions](PRODUCT_DECISIONS.md)
- [Architecture and security](ARCHITECTURE_AND_SECURITY_CONTRACT.md)
- [Migration and rollback](MIGRATION_AND_ROLLBACK_PLAN.md)
- [Test and acceptance plan](TEST_AND_ACCEPTANCE_PLAN.md)
- [Analytics contract](../analytics/POSTHOG_ANALYTICS.md)
- [PostHog project](https://us.posthog.com/project/600792)
- [Production Supabase project](https://supabase.com/dashboard/project/czykuksmlwswjsgotrpo)
- [PostHog HogQL documentation](https://posthog.com/docs/product-analytics/hogql)
- [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)

This report is an audit and implementation design, not a production repair or acceptance sign-off.

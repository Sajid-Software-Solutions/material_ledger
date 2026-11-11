# Material Request recovery lifecycle repair — 7 October 2026

Status: **released and verified in production**, including the web app, database repair and authorized obsolete-copy cleanup. This follows the [draft audit](MATERIAL_REQUEST_DRAFT_AUDIT_20261007.md) and the owner's explicit request to fix the defect and remove obsolete drafts.

## Changes

- Recovery deletion removes only the actor's version-checked recovery copy. An existing saved/progressed request no longer turns the operation into `V1_PRIVATE_DRAFT_ALREADY_SAVED`; no business request or line is deleted.
- Matching recovery input is archived in the same transaction as a successful Save. Submission/state progression archives the remaining creator recovery. Differing saved-draft input stays available for review. Archives preserve exact JSON, versions and original timestamps, including unknown fields, and have no ordinary client grants.
- Delayed private autosaves cannot recreate recovery for a normalized request. Existing advisory locks, optimistic version checks, idempotency, bounded HTTP 409 errors and owner isolation remain in force.
- Owner-scoped metadata reconciliation hides positively obsolete device entries without erasing device bytes. Unknown/denied/offline results retain them. Pending Save/Submit intents are exempt until receipt resolution. Stable identity keys avoid a request per keystroke.
- Resuming saved recovery opens a comparison before editing. Users can open the current request or explicitly carry recovered changes onto the reviewed saved version; the eventual Save still rechecks authorization/version. Progressed requests cannot be resumed as drafts. Extra lines remain intact.
- Recovery notices show all returned entries and refresh on permission/realtime changes. Delete confirmation now explains that saved/submitted history remains available.

## Authorized production cleanup

Before: 54 active private snapshots, including 41 overlapping progressed requests. After: **13 active snapshots, zero progressed overlaps**, and **41 protected archive records**. The 13 retained copies are nine genuine private-only drafts and four saved-draft recovery copies.

All **10 normalized saved drafts and 70 lines** remain unchanged. The 27-line recovery alongside its 26-line saved draft remains intact. Zero lines or age alone was not classified as defective. No normalized request, line, comment, dispatch or business history was deleted.

Cleanup used one repeatable-read transaction with bounded lock/statement timeouts, deterministic owner/UUID advisory locks and request share locks. Assertions compared every archived payload/timestamp to its source and normalized request/line hashes before commit. A first verification statement had an ambiguous PL/pgSQL alias; that transaction rolled back. The corrected transaction passed every assertion and committed once.

Prior production function definitions are retained privately under `/Users/eapple/.codex/private-backups/yorks/mr-recovery-20261007/`. This is a function-definition backup, not a full database disaster-recovery backup. Superseded data is preserved in the protected server archive.

## Verification

- `flutter pub get`, changed-file formatting and `flutter analyze`: passed.
- Full Flutter suite: **2,509 passed, four existing skips**. Final focused controller/mobile suite after small follow-up adjustments: **193 passed**.
- Clean isolated local Supabase reset and all **124 SQL files / 3,644 assertions**: passed.
- **12 two-session races** (Save/Delete and Sync/Delete in both orders) and local REST conflict/retry/anonymous probes: passed. One concurrent run timed out behind the full database suite; rerunning after that suite completed passed without changing timeouts.
- CI web build/startup budget and ephemeral CI-signed Android release build: passed. The APK is validation evidence, not a store release or production-signing claim.
- [360px review](../../test/goldens/r35/mr_recovery_review_360.png) and [desktop review](../../test/goldens/r35/mr_recovery_review_1366.png): rendered and inspected; existing mobile/draft tests passed.
- Staging and production trusted-RPC witnesses: Save, atomic archive, recovery removal, subsequent versioned draft edit, and rejected stale autosave passed. All witness records were rolled back.
- Production archive permissions: no authenticated SELECT/INSERT/UPDATE/DELETE; ordinary callers cannot invoke its internal cleanup helper.

These checks establish the tested lifecycle guarantees, not a promise that software can never have another defect. Physical-device acceptance, long-running production telemetry and every role's live browser session are separate from local/transactional verification. The historical four permission-denied Save events still lack sufficient evidence for precise attribution; permissions were not weakened.

## Rollback / preservation

Keep archive and retirement records. If needed, publish a corrective function/client version; never restore active progressed snapshots or drop the archive as a rollback. The previous client remains compatible with recovery deletion. Retain the current normalized workflow and all history. The primary dirty checkout and unrelated project configuration remain untouched.

## Published web release

- Live: [Yorks Material Requests](https://yorks-r35.vercel.app/#/yorks/material-requests).
- Source: `2f3a641d0b73d8ec11ad7b4075960121d6cd64a0`; [PR #53](https://github.com/SajidAfridi/material_ledger/pull/53) retains the reviewable source changes.
- Deployment: `dpl_3fGy4maBLq7753XSvm6wMfPrrD3L`, promoted after verification; [immutable artifact](https://yorks-r35-ciga17g67-sajid-alis-projects-0ec775a2.vercel.app).
- Main bundle: 9,938,312 bytes; SHA-256 `c5ed6c1c36d700bef059a2020563f6c30a02f3fd01663b80e1396918faaf94db`.
- All 26 candidate and all 26 public route/asset byte checks passed. Source stamp and production backend were verified; no staging backend, CI placeholder or service-role JWT was found in the artifact.
- Calculator/Project Setup flags were explicitly preserved alongside the existing production Accounts, Company Requests, Workforce, Analytics, PostHog and FCM configuration. Static artifact inspection excluded deployment metadata and credentials.
- Production migration ledger: `20261007104316`, `material_request_recovery_lifecycle`. All eight relevant function hashes match verified staging.
- Public browser: existing signed-in Owner/Admin loaded Material Requests and My Material Requests, opened an existing saved draft with its retained line, and returned without saving/submitting successfully; no console errors. Candidate startup also passed. No real request was saved, submitted or deleted during browser verification.
- Prior verified client for rollback: `dpl_EvfCnBCDQSLT3F2CoAMMJzE58ups`. Retain the repaired database lifecycle and archive when rolling back the client.

The source PR remains available for repository review; this release is the verified immutable hotfix artifact above. Existing browser sessions should refresh once to load the updated client. Historical failure events are retained in analytics; they do not reset when a repair ships.

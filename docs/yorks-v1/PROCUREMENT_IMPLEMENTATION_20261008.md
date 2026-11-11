# Procurement workspace implementation and staging release

Date: 8 October 2026
Scope: initially owner-authorized implementation and staging review. The later
owner-authorized production release is recorded in
[release evidence](PROCUREMENT_PRODUCTION_RELEASE_20261009.md).
Source branch: `codex/procurement-workspace-staging`.

## Implemented

- Arrangement opens inside the universal office shell as a full workspace. The desktop editor uses a bounded lazy list, pinned item identity and column headers, search and decision filters, and persistent Save progress / Review arrangement actions. All lines remain part of validation even when filtered.
- Warehouse selection separates a selected catalogue item from available quantity and rejects unrelated search results. Shared-item shortages identify every affected line. Existing clarification, supplier optionality, readiness policy and commercial access rules remain in force.
- Arrangement and dispatch share private account checkpoints, raw incomplete-input recovery, explicit recovery choices and version-conflict handling. Browser recovery excludes costs and is scoped to backend, actor and editor. Account commercial progress uses a separate protected relation.
- Mobile arrangement now exposes Save progress and the same conflict, retry and recovery controls in the list, line editor and review. A focused regression verifies that an incomplete quantity such as `1.` is preserved exactly without submitting an arrangement.
- The universal Back/Forward controls and route exit share an unsaved-work guard. Desktop Ctrl/Cmd+S saves progress. Browser unload uses the standard browser warning; it does not attempt a workflow transaction.
- Final arrangement/dispatch submissions freeze the exact payload and command identity before preparation. Uncertain outcomes offer status reconciliation and exact retry. Explicit abandonment is server-fenced against a delayed commit; a confirmed command cannot be reused as editable progress.
- Dispatch preparation uses decimal-safe shared-stock suggestions and row validation, including negative, over-cap and combined stock shortages. An explicit manifest review precedes the stock command. Saved preparation moves no stock.
- Dispatch Centre uses trusted remaining-demand readiness, including replacement demand, instead of assuming readiness from aggregate workflow status.
- Delivery documents have an explicit immutable revision selector. Original dispatch snapshots and receipt-reviewed reports remain distinct. Excel, print and PDF use the selected revision.
- Bounded analytics record save/restore/failure/reconciliation outcomes without record IDs, free text, costs, quantities or command payloads.

## Backend and preservation

Apply these additive migrations in order before deploying the client:

1. [Aggregate dispatch stock protection](../../supabase/migrations/20261008162353_procurement_dispatch_aggregate_stock_guard.sql).
2. [Private progress and prepared commands](../../supabase/migrations/20261008162546_procurement_private_progress.sql).
3. [Dispatch readiness](../../supabase/migrations/20261008163612_procurement_dispatch_readiness.sql).

Project and Company dispatch both lock stock deterministically and validate the sum for each inventory item, accounting for reservations in both lanes. Existing IDs, stock movements, documents and historical workflows are preserved. Checkpoints have owner isolation and revision compare-and-swap. No ordinary authenticated or anonymous table reads are granted for progress, commercial progress or prepared intents. Public RPCs re-check authorization; internal assertion helpers are not executable by ordinary clients.

Rollback: restore the preceding client first; retain additive progress data and the stock correction. Do not delete checkpoints or reverse historical stock movements to roll back a UI release. Reconcile any prepared submission before editing it in another client.

## Verification

- Full Flutter suite: **2,613 passed**, four pre-existing fixture skips.
- Final focused dispatch suite after correcting its visual-test theme: **17 passed**.
- Mobile follow-up: **60 focused visual/flow tests**, then **47 progress, command-preparation and mobile regressions passed**; analyzer remained clean.
- Analyzer: **no issues**.
- Clean local database reset and full database suite: **3,774 tests / 130 files passed**.
- Two-connection database checks cover competing dispatches and delayed-command versus abandonment fencing in disposable local database clones.
- CI web build and startup budget passed; CI APK build passed using ephemeral CI signing. This APK is not a production distribution artifact.
- Desktop and 360px widget goldens cover arrangement, dispatch, validation and document revisions. The existing receipt and return regression flows pass.

## Staging backend

Only `iqltcyimlqtcwyzlemwx` was changed. Hosted ledger timestamps are:

| Migration | Hosted version |
| --- | --- |
| procurement_dispatch_aggregate_stock_guard | 20261008174300 |
| procurement_private_progress | 20261008174306 |
| procurement_dispatch_readiness | 20261008174309 |

Post-migration checks confirm RLS and denied direct table reads for all three new tables, denied anonymous execution for the public progress RPCs, and denied ordinary execution of the internal assertion helper. Security advisers report no ERROR findings. Their no-policy notices are expected for RPC-only tables; the authenticated security-definer notices describe deliberately authorized RPC entry points. Existing anonymous-helper notices and disabled leaked-password protection remain outside this change ([adviser guidance](https://supabase.com/docs/guides/database/database-linter)).

## Evidence boundary and next review

This implements the core stock, recovery, editing and document changes from the [approved review](PROCUREMENT_WORKSPACE_REVIEW_20261008.md). The larger proposal also described future catalogue/server pagination, richer row details and staff timing studies. Those are not claimed as completed or measured here. Project and Company backend stock protection is tested; Company Use retains its separate editor and does not acquire this Project MR progress UI.

Named Procurement-persona acceptance, physical-device/network-loss exercises, large-catalogue runtime profiling and long-running monitoring remain review activities. Automated tests are not a claim that every real user scenario has been exercised. The staging browser and deployment checks below cover the named interactions only.

### Startup performance correction

The first staging-configured build exceeded the unchanged 2,900,000-byte gzip startup budget by 1,692 bytes. Arrangement now loads through the existing deferred-route pattern with a retry action if its library cannot download. This avoids downloading the editor at application startup. The guarded route and domain providers are retained. The 39 routing and arrangement tests passed after this change; final staging build measurement is recorded with deployment evidence.


## Verified staging deployment

- Staging: <https://yorks-r35-staging.vercel.app>.
- Source: `2b8520f48241c350bd298c47d45fce74543e3ac8` (clean before artifact build).
- Deployment: `dpl_6HpsAjCpbszRbwuVs8TMuPnW5UeS`.
- Immutable preview: <https://yorks-r35-cb6okkxb3-sajid-alis-projects-0ec775a2.vercel.app>.
- Isolated upload: `/tmp/yorks-procurement-staging-final-20261008`; 62 application files plus local Vercel project metadata; nine deferred JavaScript parts.
- Startup measurement: `main.dart.js` 9,934,646 bytes; level-6 gzip 2,861,422 bytes, below the unchanged 2,900,000-byte budget.
- Main bundle SHA-256: `c69deb87d8fc4e49f5fdf6fbbbf143e24cd1f1701e37214b3af2a8d138ed92fe`.
- The compiled JavaScript includes the staging backend reference and excludes the production and CI backend references.
- All **28 route/asset byte checks passed** for both the immutable preview and staging alias, including every deferred part.
- The final mobile correction also passed the ephemeral CI APK build. It is compilation evidence, not a signed production-native release.
- Production remains `dpl_BzugN8M8Wawfa2rUU2zhdWLN9EC1` / `yorks-r35-lcw7nigzf-sajid-alis-projects-0ec775a2.vercel.app`, matching the pre-deployment observation.

### Browser evidence

Checked the staging Local Admin session at 1456px desktop and 360x800 mobile:

1. Arrangement opens within the existing office shell via the deferred editor.
2. Save progress confirms an account checkpoint; shared Back/reopen and a full reload restore it.
3. Review blocks the existing three invalid rows, including the two lines jointly requiring 32 against 27 available from the same inventory item.
4. Mobile list and line editor expose Save progress. The real line-editor save transitions from Saving progress to Progress saved to your account.
5. Dispatch Centre renders its server-backed queue and opens an existing delivery's dispatch/receipt history.
6. No browser console errors were captured in these checks. The temporary viewport override was reset.

Only the existing demo arrangement's private checkpoint was saved; no final arrangement, dispatch, stock movement or delivery snapshot was committed during browser verification. Delivery revision selection/output is covered by widget and document tests; physical printing and a new end-to-end delivery were not exercised in this browser session.

Local screenshots:

- `/tmp/yorks-procurement-evidence-20261008/staging-arrangement-desktop.png`
- `/tmp/yorks-procurement-evidence-20261008/staging-arrangement-mobile.png`

Local build/release logs:

- `/tmp/procurement-staging-final-build.log`
- `/tmp/procurement-staging-final-deploy.log`
- `/tmp/procurement-final-candidate-verify.log`
- `/tmp/procurement-final-alias-verify.log`
- `/tmp/procurement-mobile-save-regression.log`
- `/tmp/procurement-mobile-analyze.log`
- `/tmp/procurement-mobile-final-apk.log`

Frontend rollback target before this task: `dpl_6yuZXKMrqpnbSgRd3HWnexymCrMH` / `yorks-r35-7ka2qjrcm-sajid-alis-projects-0ec775a2.vercel.app`. Retain the additive database changes as described above.

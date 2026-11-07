# Release runbook — Accounts Workspace V2

How to take the six-tab Accounts workspace (V2) live. The V2 screens ship
**disabled by default** behind `YORKS_V1_ACCOUNTS_WORKSPACE_V2`.

**The flag only controls the screens.** Applying the database bundle changes
functions that V1 Accounts and the Accountant office already use, whether or not
the flag is on. See [What the bundle changes](#what-the-bundle-changes).

## Current state

- V1 Accounts tabs: Overview · Billing Progress · Claims & Invoices · Receipts &
  PDC · Supplier Bills · Documents · Activity.
- V2 tabs: Summary · Contract · Progress & claims · Invoices & payments ·
  Supplier bills · History. PR #54 merged the first version; PR #55 adds the
  later features and fixes, and the bundle grows from 12 to 25 migrations.
- The embed swaps to V2 only when `flags.accountsWorkspaceV2` is true, which is
  `YORKS_V1_ACCOUNTS && YORKS_V1_ACCOUNTS_WORKSPACE_V2`. So V2 needs **both**
  flags true in the build.

## Migration drift — READ FIRST (blocks the DB step)

The live staging/production database has **~30 migrations that are not in this
git repository** (dated Oct 7 – Nov 5). Git is therefore *not* a complete record
of the live schema. Because of that:

- **Do NOT run `supabase db push`.** It refuses with
  `DbPushMissingLocalError` (remote has history git doesn't), and forcing it is
  not safe while the 30 migrations' origin is unknown.
- **Do NOT run `supabase migration repair --status reverted`.** That rewrites
  the remote migration ledger and can orphan live objects.
- **Do NOT delete, rename or re-timestamp the 30 unknown migrations.** Leave
  them exactly as they are until their origin is understood. That investigation
  is separate.

**Apply `supabase/release/accounts_v2_bundle.sql` by hand instead.** It holds all
25 V2 migrations in dependency order, inside one `BEGIN/COMMIT`, so a failure
rolls the whole script back.

A database may already have some of the V2 migrations, for example the first 12.
That is fine: apply the whole bundle anyway.

## What the bundle changes

- **Adds** 6 tables, 21 functions, and columns and indexes that use
  `IF NOT EXISTS`.
- **Replaces 10 functions that existed before V2**, which V1 Accounts and the
  office rely on. Payment recording and claim validation are among them:
  `v1_accounts_consumed_claim_amount`, `v1_accounts_invoice_snapshot`,
  `v1_accounts_validate_claim_lines`, `v1_get_accounts_documents`,
  `v1_get_accounts_export`, `v1_get_accounts_office_register`,
  `v1_get_accounts_portfolio`, `v1_get_project_accounts_overview`,
  `v1_list_client_invoices`, `v1_record_client_payment`.
- **Changes figures straight away.** For example, the office Receipts & PDC total
  stops counting a cleared cheque twice, and retention can reduce client payable
  (`PRODUCT_DECISIONS.md` §28).
- **Inserts company settings** (TRN, address, phone and similar) with
  `ON CONFLICT DO NOTHING`, so existing values are kept.
- **Drops no table or column.** It widens one check constraint on
  `v1_accounts_billing_progress_revisions` and drops and recreates
  `v1_save_accounts_contract_references` to change its signature.

**Tested on local databases, 7 November 2026:**

| Test | Result |
|---|---|
| Run on a database built from the 186 migrations before V2 (a local stand-in replaced `pg_cron`) | Succeeds; all 801 public functions match a normally migrated database |
| Run a second time on that database | Succeeds; functions unchanged |
| Run on a fully migrated database, then rolled back | Succeeds; functions unchanged |

**Not tested:** a database with the ~30 unknown migrations. If any of them changed
one of the 10 functions above, the bundle overwrites that change. The overlap
check in step 2 looks for this.

## The enable lever (build-time)

`tool/r35.sh` honours `YORKS_V1_ACCOUNTS_WORKSPACE_V2` (default `false`), exactly
like `YORKS_V1_ACCOUNTS` (also default `false`). To build with V2 on, set both:

```bash
YORKS_V1_ACCOUNTS=true YORKS_V1_ACCOUNTS_WORKSPACE_V2=true \
R35_ENVIRONMENT=staging SUPABASE_URL=… SUPABASE_ANON_KEY=… \
  ./tool/r35.sh build-web
```

**`.github/workflows/release-production.yml` sets neither flag today**, and a CI
checkout has no `.r35.env`. Dispatched as it stands, it builds with Accounts off
altogether. Before using it for this release, add both flags to the job's `env:`
in a reviewed commit on `main`. If production is built another way, set them
there.

## Go-live sequence

1. **Merge** PR #55 → `main`. This changes nothing live until step 2 or a deploy.
2. **Apply the bundle by hand to staging.** Production follows in step 7, and any
   build with V2 on must be deployed after its database has the bundle.
   1. **Take a fresh backup** (Supabase dashboard → Database → Backups → create,
      or a `pg_dump`). This backup is the only way to undo the bundle.
   2. **Check for overlap.** This query is read-only:

      ```sql
      select version, name
      from supabase_migrations.schema_migrations
      where statements::text ilike any (array[
        '%v1_accounts_consumed_claim_amount%',
        '%v1_accounts_invoice_snapshot%',
        '%v1_accounts_validate_claim_lines%',
        '%v1_get_accounts_documents%',
        '%v1_get_accounts_export%',
        '%v1_get_accounts_office_register%',
        '%v1_get_accounts_portfolio%',
        '%v1_get_project_accounts_overview%',
        '%v1_list_client_invoices%',
        '%v1_record_client_payment%'
      ])
      order by version;
      ```

      Compare each row with `supabase/migrations/`. A row with no matching file
      there is an unknown migration touching a function the bundle replaces.
      **Stop and review that migration before applying.** Migrations run by hand
      in the SQL editor are not recorded in this table, so an empty result does
      not rule out every change.
   3. In the **SQL editor**, paste and run all of
      `supabase/release/accounts_v2_bundle.sql`. Re-running it is harmless.
   4. It does **not** register in `supabase_migrations.schema_migrations`. That is
      fine for enabling V2. Reconciling the git ↔ DB ledger is the separate drift
      cleanup, not a release blocker.
3. **P1 pre-flight on staging — AFTER step 2** (the query calls
   `v1_accounts_progress_eligible_amount`, which **the bundle creates**). Run
   `supabase/preflight/accounts_v2_p1_preflight.sql` in the SQL editor. It is
   **read-only**. **Zero rows = proceed.** Any row = stop and investigate that
   dimension before enabling.
4. **Staging build with both flags on** (command above) and deploy to staging.
   This walkthrough is the **staging-acceptance evidence** the production
   workflow requires as input. Walk all six tabs against a real project as
   Accountant, Project Engineer and Site Engineer, including what has not been
   run live yet:
   - issue → certify → pay → **revise** an invoice, and **reverse** a payment;
   - record a cheque and take it through to cleared;
   - supplier bill through matched, approved and paid;
   - upload a file using the **native file chooser**, and **download** one;
   - print the tax-invoice PDF (now 3+ pages) and **check the printed pages**;
   - **import a real master file**;
   - check V1 Accounts and the office against known figures, since the bundle
     changes the functions behind them.
5. **Reconfirm the YRA-322 contract value.** The owner chose 17,192,000, but master
   files from 26 September and 23 October show 18,085,468
   ([timeline](ACCOUNTS_V2_IMPORT_MASTER_FILE_SCOPE.md)).
6. **Acknowledge D4** (one-fil rounding): a multi-building invoice may show a
   gross one fil below the legacy Excel (e.g. `5,983,597.44` vs `.45`). This is
   intentional (see `D4_ROUNDING_OWNER_DECISION.md`); confirm no client
   reconciles to the fil against the historical PDFs.
7. **Apply the bundle to production**, as in step 2, then run the pre-flight.
8. **Dispatch** `release-production.yml` (workflow_dispatch) from `main` with the
   staging-acceptance reference and release-owner note, after adding both flags
   (see above). The protected `production` environment requires the designated
   reviewer to approve before it deploys to Vercel.
9. **Verify** on production: the six tabs load; a known project's figures match
   what was checked on staging. Keep V1 code in place for one cycle.

## Rollback

**Screens:** re-run the release without `YORKS_V1_ACCOUNTS_WORKSPACE_V2` (or set
it `false`) and deploy. The embed falls back to V1 immediately.

**Database:** turning the flag off does not undo the bundle. The 10 replaced
functions stay in their new form, and there are no down migrations. To revert
them, restore the backup from step 2. That also loses anything written after the
backup, so decide before real work has been recorded on the new version.

## Not in this release (optional, post-launch)

- **Item-level invoice pages.** The real Yorks invoice also prints per-building
  delivered-material item sheets (6 AC units, 20 of 55 dampers, …). V2 matches
  the approved prototype (stage-level: tax invoice + main summary + per-building
  breakdown). The item sheets need the document RPC to also return item
  quantities — a self-contained follow-up.
- **Drawer payment-reversal widget test.** The reversal flow is wired and the
  controller mirrors the tested pay path; a dedicated widget test needs a full
  invoice-detail fixture (deferred).
- **Site Engineer suggestions on per-item stages.** Suggestions work on
  percent-mode stages only.
- **Phone layout.** The per-item contract table scrolls sideways, and KPI tiles
  are tall.

## Open decisions

- Should Project Managers and Senior Mechanical Engineers edit contracts? The plan
  says yes; the server refuses.
- Should Project Engineers see commercial values by default? The local setup shows
  them; the plan and `AGENTS.md` say no.
- Reversing a payment that came from a cleared cheque leaves the cheque marked
  Cleared. Should that be blocked, or should it reopen the cheque?

## Gates (local, PR #55 at `73eefce`)

| Check | Result |
|---|---|
| `flutter analyze` | Clean |
| `flutter test` | 2,649 pass, 4 skipped, **2 fail** |
| `supabase db reset` + `supabase test db` | 139 files, 3,803 tests pass |
| Web build with startup budget | Passes |
| APK with CI ephemeral signing | Builds; not a release artifact |

- The 2 failures are the R38.4 property and rental register goldens in
  `test/yorks_v1_rental_test.dart`. They also fail at `c6755f5`, before these
  fixes, and need their own resolution.
- **GitHub CI has not checked this work.** The Flutter quality gate has no runs on
  this branch, and its latest run in the repository is from 3 October 2026.
- A properly signed Android lane is still required for an Android release.

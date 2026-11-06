# Release runbook — Accounts Workspace V2

How to take the six-tab Accounts workspace (V2) live. It ships **disabled by
default** behind `YORKS_V1_ACCOUNTS_WORKSPACE_V2`; nothing below changes what
users see until the flag is turned on in a build.

## Current state

- Production renders **V1 Accounts** (Overview · Billing Progress · Claims &
  Invoices · Receipts & PDC · Supplier Bills · Documents · Activity).
- V2 (Summary · Contract · Progress & claims · Invoices & payments · Supplier
  bills · History) is built and tested, on PR #54, **flag off**.
- The embed swaps to V2 only when `flags.accountsWorkspaceV2` is true, which is
  `YORKS_V1_ACCOUNTS && YORKS_V1_ACCOUNTS_WORKSPACE_V2`. So V2 needs **both**
  flags true in the build.

## Migration drift — READ FIRST (blocks the DB step)

The live staging/production database has **~30 migrations that are not in this
git repository** (dated Oct 7 – Nov 5), and the **12 V2 migrations below are not
yet on the database**. Git is therefore *not* a complete record of the live
schema. Because of that:

- **Do NOT run `supabase db push`.** It refuses with
  `DbPushMissingLocalError` (remote has history git doesn't), and forcing it is
  not safe while the 30 migrations' origin is unknown.
- **Do NOT run `supabase migration repair --status reverted`.** That rewrites
  the remote migration ledger and can orphan live objects.
- **Do NOT delete, rename or re-timestamp the 30 unknown migrations.** Leave
  them exactly as they are until their origin is understood (a separate
  investigation — not a blocker for V2, which is additive).

**The 12 V2 migrations are safe to apply by hand, out of the drift problem.**
Static analysis confirms they are purely **additive and idempotent**: no
destructive `DROP`s (the one constraint drop is `if exists` + re-add as a wider
superset); every new table is `CREATE TABLE IF NOT EXISTS` (5 new V2 tables,
names that cannot pre-exist); every column add is `ADD COLUMN IF NOT EXISTS`;
every function is `CREATE OR REPLACE`. They only *read* the existing R39 base
tables, which production already has (it runs V1 Accounts). So they slot on top
of the real schema and can be re-run without harm — see the surgical apply in
the go-live sequence.

## The enable lever (build-time)

`tool/r35.sh` now honours `YORKS_V1_ACCOUNTS_WORKSPACE_V2` (default `false`),
exactly like the existing `YORKS_V1_ACCOUNTS` flag. To build with V2 on, set it
in the build environment **alongside** `YORKS_V1_ACCOUNTS=true`:

```bash
YORKS_V1_ACCOUNTS=true YORKS_V1_ACCOUNTS_WORKSPACE_V2=true \
R35_ENVIRONMENT=staging SUPABASE_URL=… SUPABASE_ANON_KEY=… \
  ./tool/r35.sh build-web
```

Leave it unset (or `false`) and the build is byte-identical to today's — V1
stays. In the production release (`.github/workflows/release-production.yml`),
set `YORKS_V1_ACCOUNTS_WORKSPACE_V2=true` in the **same place** `YORKS_V1_ACCOUNTS`
is already set true for production, only for the release that turns V2 on.

## Go-live sequence

1. **Merge** PR #54 → `main`. No user impact (flag off), fully reversible.
   *(Done.)*
2. **Apply the 12 V2 migrations to the database — by hand, surgically.** Do this
   on **staging first**, then production. Do **not** use `db push` (see the
   drift section). For each database:
   1. **Take a fresh backup first** (Supabase dashboard → Database → Backups →
      create, or a `pg_dump`). This is the real safety net, not the migration
      tool.
   2. In the **SQL editor**, paste and run the 12 files **in this exact order**,
      one at a time, checking each succeeds:
      `20261105094500_accounts_v2_p1_dimension_claim_cap` →
      `…_p2_item_breakdown` → `…_p2_save_setup` →
      `…_p3_claim_workbench_read` → `…_p3_invoice_issue` →
      `…_p3_invoice_revise` → `…_p3_save_workbench` →
      `…_p4_company_settings` → `…_p4_workspace` →
      `…_p6_commercial_setup_read` → `…_p8_pdc_register` →
      `20261106120000_accounts_v2_p7_invoice_document_pages`.
      They are additive/idempotent; re-running a file is harmless.
   3. They do **not** register in `supabase_migrations.schema_migrations`
      (you ran them by hand). That is fine for enabling V2. Reconciling the git
      ↔ DB ledger is the separate drift cleanup, not a release blocker.
3. **P1 pre-flight on production — AFTER step 2** (the query calls
   `v1_accounts_progress_eligible_amount`, which **the P1 migration creates**;
   it does not exist until step 2 runs). Run
   `supabase/preflight/accounts_v2_p1_preflight.sql` in the production SQL
   editor — it is **read-only**. **Zero rows = proceed.** Any row = stop and
   investigate that dimension before enabling.
4. **Staging build with the flag on** (command above) and deploy to staging.
   Walk all six tabs against a real project; issue → certify → pay → revise an
   invoice; record and transition a PDC; print the tax-invoice PDF (now 3+
   pages). This walkthrough is the **staging-acceptance evidence** the
   production workflow requires as input.
5. **Acknowledge D4** (one-fil rounding): a multi-building invoice may show a
   gross one fil below the legacy Excel (e.g. `5,983,597.44` vs `.45`). This is
   intentional (see `D4_ROUNDING_OWNER_DECISION.md`); confirm no client
   reconciles to the fil against the historical PDFs.
6. **Dispatch** `release-production.yml` (workflow_dispatch) from `main` with the
   staging-acceptance reference + release-owner note, **and** the V2 flag set in
   the build env. The protected `production` environment requires the designated
   reviewer to approve before it deploys to Vercel.
7. **Verify** on production: the six tabs load; a known project's figures match
   V1. Keep V1 code in place for one cycle.

## Rollback

Re-run the release **without** `YORKS_V1_ACCOUNTS_WORKSPACE_V2` (or set it
`false`) and deploy. The embed falls back to V1 immediately. No data migration is
involved — every V2 server addition is additive and unused by V1, so nothing
needs reverting on the database.

## Not in this release (optional, post-launch)

- **Item-level invoice pages.** The real Yorks invoice also prints per-building
  delivered-material item sheets (6 AC units, 20 of 55 dampers, …). V2 matches
  the approved prototype (stage-level: tax invoice + main summary + per-building
  breakdown). The item sheets need the document RPC to also return item
  quantities — a self-contained follow-up.
- **Drawer payment-reversal widget test.** The reversal flow is wired and the
  controller mirrors the tested pay path; a dedicated widget test needs a full
  invoice-detail fixture (deferred).

## Gates (green on PR #54)

`flutter analyze` clean · focused `flutter test test/yorks_r39_accounts_v2_*`
(72) · `supabase db reset && supabase test db` (3735) · CI web build. Run the
full `flutter test` suite and a signed APK lane as the formal release gate.

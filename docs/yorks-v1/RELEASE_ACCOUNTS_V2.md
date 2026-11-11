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
  later features and fixes, and the bundle grows from 12 to 30 migrations. The
  8 November release adds a 31st (Excel rounding, the signed invoice layout and
  History dates). The 9 November release adds a 32nd (claim rights for Admin
  and the organization-wide engineering roles) and a 33rd (the invoice's
  per-building Material and Installation sheets); see `PRODUCT_DECISIONS.md`
  §35. A 34th (`20261111130000`) keeps those claim rights in the Accounts
  scope function after the 11 November Project Engineer full-access migration
  (§34) redefined it; `accounts_project_engineer_bundle.sql` and its rollback
  carry the same definition, so either bundle can be re-applied in any order.
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
33 V2 migrations in dependency order, inside one `BEGIN/COMMIT`, so a failure
rolls the whole script back.

A database may already have some of the V2 migrations, for example the first 12.
That is fine: apply the whole bundle anyway.

## What the bundle changes

- **Adds** 7 tables, 42 functions, and columns and indexes that use
  `IF NOT EXISTS`.
- **Replaces 17 functions that existed before V2**, which V1 Accounts and the
  office rely on. Payment recording, cheque steps, reversals, invoice cancelling,
  claim validation and the Accounts permission scope are among them:
  `v1_accounts_consumed_claim_amount`, `v1_accounts_has_project_scope`,
  `v1_accounts_invoice_snapshot`, `v1_accounts_receivables_commands`,
  `v1_accounts_supplier_commands`, `v1_accounts_transition_invoice`,
  `v1_accounts_validate_claim_lines`, `v1_get_accounts_documents`,
  `v1_get_accounts_export`, `v1_get_accounts_office_register`,
  `v1_get_accounts_portfolio`, `v1_get_project_accounts_overview`,
  `v1_list_client_invoices`, `v1_record_client_payment`,
  `v1_reverse_client_payment`, `v1_reverse_supplier_payment`,
  `v1_transition_client_pdc`.
- **Changes who can do what straight away.** Project Engineer, Senior Mechanical
  Engineer, Project Manager and Accountant can edit contracts as soon as it runs,
  with the flag on or off. Everyone who can reverse or correct money can use the
  new commands (`PRODUCT_DECISIONS.md` section 29).
- **Hides claim amounts from people without commercial access.** The claim
  workbench stops returning the claim total and each claim line's amounts to
  anyone who can read Accounts but not commercial values, such as a Site
  Engineer. Before this, they received them.
- **Returns more for the rebuilt Accounts screens**
  (`20261107150000_accounts_v2_workbench_claim_values.sql`): progress done before
  each claim and in it, per building, stage and item; who prepared and checked a
  claim; the invoice a claim produced; each invoice's latest certification date,
  last receipt date, the invoice a revision replaces and whether a revision is
  being prepared; and the project's job/contract reference and site for the
  Contract tab. Money among these is returned only with commercial access.
- **Links Material Supply items to BOQ folders** (last migration,
  `20261107160000_accounts_v2_material_boq_links.sql`, owner request of
  7 November 2026). A new table records which BOQ folders of a building stand
  for a contract item; it starts empty, so nothing changes until someone links
  a folder. `v1_get_accounts_material_sources` returns each building's folders
  and, per linked item, the good quantity received on confirmed receipt reviews
  less confirmed returns. `v1_save_accounts_material_boq_links` replaces the
  links with a reason and an audit event, for anyone who can edit contracts.
  Common / All Buildings, Workshop Materials and archived folders cannot be
  linked. The read returns quantities and delivery numbers only, never money,
  so anyone who can read Accounts sees it (an Accountant included: folder names
  and quantities). BOQ, request, dispatch and receipt tables are only read.
- **Rounds claims and invoices as the Yorks workbook does**
  (`20261108100000_accounts_v2_excel_rounding_and_dates.sql`, owner decisions of
  8 November 2026, `PRODUCT_DECISIONS.md` §30). Claim lines gain a nullable
  `claimed_amount_exact`; a new invoice's gross, VAT and total are each rounded
  once from the exact sum, so its total may differ from ex-VAT + VAT by at most
  0.01 (the invoice and certification checks are relaxed to exactly that; no
  existing row differs). Certifying in full carries the invoice's VAT and total.
  The invoice document (frozen at issue) gains the bill-to party, references, VAT
  and grand-total rows, and counts every earlier invoiced claim as "till
  previous"; a historical import may set the letterhead and bank its signed copy
  carried through the transaction-local setting `yorks.invoice_company_override`.
  History entries carry a business date and references and are ordered by it;
  the Overview's "to come" becomes invoiced-and-unpaid. Existing invoices,
  frozen documents and audit rows are unchanged. Replaced functions:
  `v1_accounts_validate_claim_lines`, `v1_accounts_replace_claim_lines`,
  `v1_revise_client_invoice`, `v1_create_client_invoice_draft`,
  `v1_record_client_certification`, `v1_correct_client_certification`,
  `v1_accounts_claim_snapshot`, `v1_accounts_invoice_snapshot`,
  `v1_list_client_claims`, `v1_get_claim_workbench`,
  `v1_get_accounts_office_register`, `v1_get_accounts_export`,
  `v1_get_project_commercial_setup`, `v1_get_project_accounts_workspace`,
  `v1_accounts_build_invoice_document`, `v1_get_accounts_activity`; new internal
  helpers are not callable by app users.
- **Changes figures straight away.** For example, the office Receipts & PDC total
  stops counting a cleared cheque twice, and retention can reduce client payable
  (`PRODUCT_DECISIONS.md` §28).
- **Inserts company settings** (TRN, address, phone and similar) with
  `ON CONFLICT DO NOTHING`, so existing values are kept.
- **Drops no table or column.** It widens one check constraint on
  `v1_accounts_billing_progress_revisions`, and drops and recreates
  `v1_save_accounts_contract_references` and `v1_reverse_client_payment` to change
  their signatures. It replaces three unique indexes on payment references and
  cheque receipts with ones that allow a reversed entry to be entered again.

**Tested on local databases, 7 November 2026:**

| Test | Result |
|---|---|
| Run on a database built from the 186 migrations before V2 (a local stand-in replaced `pg_cron`) | Succeeds; all 822 public functions match a normally migrated database (8 November, 31 files) |
| Run a second time on that database | Succeeds; functions unchanged |
| Run on a fully migrated database, then rolled back | Succeeds; functions unchanged |

**Not tested:** a database with the ~30 unknown migrations. If any of them changed
one of the 17 functions above, the bundle overwrites that change. The overlap
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
        '%v1_accounts_has_project_scope%',
        '%v1_accounts_invoice_snapshot%',
        '%v1_accounts_receivables_commands%',
        '%v1_accounts_supplier_commands%',
        '%v1_accounts_transition_invoice%',
        '%v1_accounts_validate_claim_lines%',
        '%v1_get_accounts_documents%',
        '%v1_get_accounts_export%',
        '%v1_get_accounts_office_register%',
        '%v1_get_accounts_portfolio%',
        '%v1_get_project_accounts_overview%',
        '%v1_list_client_invoices%',
        '%v1_record_client_payment%',
        '%v1_reverse_client_payment%',
        '%v1_reverse_supplier_payment%',
        '%v1_transition_client_pdc%'
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
   - record a cheque, take it through to cleared, undo the clearing and clear it
     again with the same bank reference;
   - edit a payment, a certification and a cheque, and reopen a supplier bill;
   - supplier bill through matched, approved and paid;
   - upload a file using the **native file chooser**, and **download** one;
   - print the tax-invoice PDF (now 3+ pages) and **check the printed pages**;
   - **import a real master file**;
   - check V1 Accounts and the office against known figures, since the bundle
     changes the functions behind them.
5. **Check YRA-322 shows AED 17,192,000.** The owner confirmed this value; master
   files showing 18,085,468 are not authoritative
   ([section 29](PRODUCT_DECISIONS.md)).
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

**Database:** turning the flag off does not undo the bundle. The 17 replaced
functions and the wider contract-editing access stay in their new form, and there are no down migrations. To revert
them, restore the backup from step 2. That also loses anything written after the
backup, so decide before real work has been recorded on the new version.

The BOQ links migration alone can be removed without a backup: drop
`v1_save_accounts_material_boq_links`, `v1_get_accounts_material_sources`,
`v1_accounts_boq_number`, `v1_accounts_unit_key` and the
`v1_accounts_material_boq_links` table. Nothing else refers to them; the links
are lost, the audit events stay.

## Not in this release (optional, post-launch)

- **Item-level invoice pages.** The real Yorks invoice also prints per-building
  delivered-material item sheets (6 AC units, 20 of 55 dampers, …). V2 matches
  the approved prototype (stage-level: tax invoice + main summary + per-building
  breakdown). The item sheets need the document RPC to also return item
  quantities — a self-contained follow-up.
- **Site Engineer suggestions on per-item stages.** Suggestions work on
  percent-mode stages only.
- **Phone layout.** The per-item contract table scrolls sideways, and KPI tiles
  are tall.

## Gates (local, 9 November 2026, claim rights and the invoice item sheets)

| Check | Result |
|---|---|
| `flutter analyze` | Clean |
| `flutter test` | 2,721 pass, 4 skipped, **2 fail** (the same R38.4 rental register goldens) |
| `supabase db reset` + `supabase test db` | 143 files, 4,052 tests pass |
| Web build with startup budget | Passes |

Applied by hand on 9 November 2026: staging, then production (files 32 and 33
only, after checking that the live definitions of the three replaced functions
matched the repository). Production web `dpl_6TH2qa1CTRLoAYQg5jsBeteCz992`;
rollback target `dpl_2SSWkyuWKzb8ZT9SGPrfeUHPhgLJ`.

## Gates (local, 8 November 2026, with Excel rounding, the signed invoice layout and History dates)

| Check | Result |
|---|---|
| `flutter analyze` | Clean |
| `flutter test` | 2,717 pass, 4 skipped, **2 fail** (after the History file-name and local-time fix) |
| `supabase db reset` + `supabase test db` | 142 files, 4,006 tests pass |
| Web build with startup budget | Passes |
| APK with CI ephemeral signing | Builds; not a release artifact |

- The 2 failures are the R38.4 property and rental register goldens in
  `test/yorks_v1_rental_test.dart`. They also fail at `c6755f5`, before these
  fixes, and need their own resolution: the saved images predate a lease that
  now expires within the alert window (31 Dec 2026), so they change with the
  date.
- **GitHub CI has not checked this work.** The Flutter quality gate has no runs on
  this branch, and its latest run in the repository is from 3 October 2026.
- A properly signed Android lane is still required for an Android release.

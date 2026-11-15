# Production function drift — 15 November 2026

Status: **investigated; fix prepared, not applied.** Nothing was written to
staging or production. Applying the bundle needs the owner's explicit OK.

## Summary

A read-only comparison on 15 November 2026 of every `public` function on
production (`czykuksmlwswjsgotrpo`) against a fresh local reset of `main`
(`849affb`, the commit the live web runs) found 19 functions that differ:
8 exist only on `main` and 11 have different text. Five legacy helpers also
have different execute grants. There are no other function differences
(1,064 on production, 1,072 on `main`). Staging (`iqltcyimlqtcwyzlemwx`)
matches `main` exactly for all of them.

The drift has four causes. None of them is a recent hand edit:

1. **The three 28 October reliability migrations were applied to staging
   only.** `20261028125701`, `20261028131620` and `20261028133155` are in
   staging's migration ledger (applied through the API) but have never been in
   production's. On 5 November, commit `52c19b8` added them to the repository
   as "already in production"; their text is a verbatim copy of staging's
   ledger. Production's ledger ends at `20261105090000`, and every later
   production change went through hand-applied bundles that do not write the
   ledger, so nothing flagged the gap.
2. **The legacy baseline `20260724000000` never ran on production.** The
   5 August reconciliation
   ([PRODUCTION_MIGRATION_RECONCILIATION_2026-08-05.md](PRODUCTION_MIGRATION_RECONCILIATION_2026-08-05.md))
   recorded it as applied because production already had the legacy tables.
   Production therefore still has the hand-applied July helpers
   ([`docs/supabase/PRODUCTION_STATUS.md`](../supabase/PRODUCTION_STATUS.md)):
   `app_role()` falls back to the JWT's top-level `role`, broadcasts are
   visible without an app user id, `anon` and `PUBLIC` may execute the
   helpers, and the four `app_legacy_*` helpers were never created.
3. **`20260803224536` was recorded on production without its
   `v1_can_confirm_material_return` change.** The same reconciliation marked
   it applied after checking that the delivery-order and return functions
   existed. That check found them by name, not by body: production still has
   the `20260802050000` rule, and no later migration redefined the function.
4. **Formatting only.** On 24 July and 3 August production received
   timestamp-shifted, compacted copies of four migrations. Later migrations
   patch `v1_import_boq_worksheet` in place by text replacement
   (`20260808100023`, `20260809143000`, which handles the compact form
   explicitly), so production keeps the compact text. The token streams match
   `main` exactly; the only other difference is whitespace inside a JSON
   literal, which parses to the same `jsonb` value.

## Per-function report

"Web" means the live web at `849affbea19c4a838e8265148e509555803019d9`
(checked in the deployed `main.dart.js`).

| Function | `main`'s version from | Production has | Web calls it / depends on `main` | Bundle |
|---|---|---|---|---|
| `v1_material_search_normalize(text)` | `20261028125701` | missing | no (helper of the two search RPCs) | create, `service_role` only |
| `v1_material_search_synonyms(text)` | `20261028125701` | missing | no (helper) | create, `service_role` only |
| `v1_material_search_one_edit(text,text)` | `20261028125701` | missing | no (helper) | create, `service_role` only |
| `v1_search_material_request_candidates(uuid,uuid,text,integer)` | `20261028125701` | older: exactly `20260820213603` | yes, MR item search; works with both (ignores `match_path`) | replace |
| `v1_search_company_material_request_candidates(uuid,uuid,text,integer)` | `20261028125701` | older: exactly `20260924221348` | yes, Company MR search; works with both | replace |
| `v1_material_request_overview(integer)` | `20261028131620` | older: exactly `20260902163200` | yes, launch cards; same output (see evidence) | replace |
| `v1_material_request_submission_diagnostic(uuid,uuid,uuid)` | `20261028133155` | missing | no, not referenced by the app | create |
| `v1_can_confirm_material_return(uuid)` | `20260803224536` | older: exactly `20260802050000` | indirectly, through `v1_returns_documents_workspace_projection` (Returns & Documents screen) | replace |
| `app_role()` | `20260724000000` | older: hand-applied July helper; falls back to the JWT `role`; `anon`/`PUBLIC` execute | no; legacy collection policies | replace, revoke `anon`/`PUBLIC` |
| `app_user_id()` | `20260724000000` | same logic, July text; `anon`/`PUBLIC` execute | no; legacy collection policies | replace (formatting), revoke |
| `notification_visible_to_caller(jsonb)` | `20260724000000` | older: July helper (broadcasts need no app user id); `anon`/`PUBLIC` execute | no; legacy `notifications` policy used by the retained notification sync | replace, revoke |
| `app_legacy_project_readable(jsonb)`, `app_legacy_project_writable(jsonb)`, `app_legacy_plan_readable(jsonb)`, `app_legacy_plan_writable(jsonb)` | `20260724000000` | missing; production keeps its own `projects_all` and `materialplans_all` policies | no | create; unused on production until the legacy policies are aligned |
| `project_progress_definitions(jsonb)` | `20260724050201` | compacted copy, same value | no (legacy `projects` trigger) | replace (formatting) |
| `project_require_approved_phase1()` | `20260724050201` | compacted copy, same tokens | no (legacy `projects` trigger) | replace (formatting) |
| `v1_create_document_version(uuid,text,bigint,text)` | `20260803211633` | compacted copy, same tokens | no; called by the `finalize-document-upload` Edge Function | replace (formatting) |
| `v1_import_boq_worksheet(jsonb,uuid)` | `20260803192654`, patched by `20260803224536`, `20260808100023`, `20260809143000` | compacted copy patched the same way, same tokens | yes, BOQ Excel import; no behaviour change | replace (formatting) |

`app_has_cap(text)` and `app_touch_updated_at()` have the same body on both
sides; only their grants differ (`anon` and `PUBLIC` may execute them on
production). The bundle revokes those grants as `main` does.

## What changes for users

- **Material search** (Project and Company Material Requests) finds more of
  the right items. Results from the old production function compared with
  `main`'s on the same items:

  | Query | Production today | After the bundle |
  |---|---|---|
  | `galvanized iron pipe` | nothing | GI Pipe 25mm (synonym) |
  | `stainless steel` | nothing | SS304 Sheet 1.5mm (synonym) |
  | `fan coil unit`, `volume control damper`, `non return valve` | nothing | FCU…, VCD…, NRV… (synonym) |
  | `copper-pipe`, `pipe copper` | nothing | Copper Pipe 1/2" |
  | `insulaton` | nothing | Insulation Tape 3" (one typo in the last word) |
  | `gi pipe`, `flexible duct` | found | found, same order |

  Authorization and the non-commercial response fields are unchanged; each
  result gains `match_path`, which the live web ignores.
- **Launch cards** (`v1_material_request_overview`) show the same cards and
  counts; the server works them out in one pass instead of per request.
- **Return confirmation.** Only Procurement or Admin (the roles that can
  actually confirm a return, `v1_can_receive_project_material_return`) get
  `can_confirm_material_return`, Confirm/Reject on submitted returns and the
  inventory list in the Returns & Documents projection. Today engineers who may
  generate a Delivery Order also receive them. Production has no return in the
  `submitted` state (2 approved, 1 awaiting approval, 1 confirmed,
  3 dispatched), so no button changes today; engineers stop receiving the
  inventory list.
- **Legacy helpers.** `anon` and `PUBLIC` can no longer execute the JWT
  helpers. Every `PUBLIC` policy on the legacy collection tables calls one of
  them, so the anon key can no longer reach those tables through them.
  Today the public anon key can insert legacy `materialRequests`, `projects`
  and `leaveRecords` rows whose owner field is empty. This was reproduced
  locally with production's grants and policies, not attempted on production.
  After the bundle the same request fails with
  `permission denied for function app_has_cap`. `app_role()` reads only
  `app_metadata.role`. Broadcast notifications need an app user id. On today's
  data no user sees a change: 31 of 32 accounts carry both claims, and all 11
  legacy notifications are role broadcasts.
- **Formatting-only functions**: no change.

## Not covered by this bundle

- **Legacy collection tables.** `anon` still has table privileges on the 19
  legacy JSON tables, and production keeps its own `PUBLIC` policies on them
  (`projects_all`, `materialplans_all`, …). It lacks `main`'s policies, the
  generated columns on `rentalUnits`, `rentPayments` and `leaveRecords`, and
  the views `v_rent_roll`, `v_rent_outstanding` and `v_leave_taken`. With the
  helper grants revoked, anon requests to those tables fail, but the table
  grants and policy differences need their own reviewed bundle with RLS
  tests. No existing legacy row is readable by anon today (0 matching rows);
  the write path is described above.
- **Migration ledger.** Like every hand-applied bundle, this one does not
  write `supabase_migrations.schema_migrations` (no `migration repair`).
  Production's ledger will still lack the three 28 October versions, and its
  entries for `20260724000000` and `20260803224536` overstate what ran there.

## Files

- Preflight (read-only):
  [`supabase/preflight/production_function_alignment_preflight.sql`](../../supabase/preflight/production_function_alignment_preflight.sql)
- Bundle:
  [`supabase/release/production_function_alignment_bundle.sql`](../../supabase/release/production_function_alignment_bundle.sql)
- Rollback:
  [`supabase/release/production_function_alignment_rollback.sql`](../../supabase/release/production_function_alignment_rollback.sql)

The bundle's function text is `main`'s `pg_get_functiondef` output, and the
rollback's is production's of 15 November, so fingerprints match exactly in
both directions. Fingerprint:
`md5(prosrc || coalesce(proconfig::text, '') || provolatile::text || prosecdef::text)`.

Both scripts run in one transaction and start with a guard. Each of the 21
functions must be at production's 15 November fingerprint or `main`'s, and
everything the new bodies call or read must exist. Otherwise the script stops
before changing anything. The bundle ends with a self-check of every
fingerprint, the `anon`/`authenticated`/`service_role` execute grants, no
`PUBLIC` grant and owner `postgres`. Both scripts are safe to re-run. The
rollback drops the 8 added functions unless something has come to depend on
one of them.

## How to apply (owner's OK required)

1. Preflight on the target; continue only when `ready_to_apply` is `true`:

   ```bash
   npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/production_function_alignment_preflight.sql
   ```

   On 15 November production returned `ready_to_apply: true` (all 19 at
   `production_20261115`, 5 grant differences, no missing dependency).
   Staging returned `already_applied: true`.
2. Staging already matches `main`; running the bundle there is a harmless
   re-run that proves it on a hosted database first.
3. Production:

   ```bash
   npx supabase@latest db query --remote=czykuksmlwswjsgotrpo --yes -f supabase/release/production_function_alignment_bundle.sql
   ```

4. Re-run the preflight: `already_applied` must be `true`.

Rollback, if needed:

```bash
npx supabase@latest db query --remote=czykuksmlwswjsgotrpo --yes -f supabase/release/production_function_alignment_rollback.sql
```

The live web works with either set of definitions. No data changes in either
direction.

## Evidence (private local stack, 15 November 2026)

A private database-only stack (`ml_fn_drift`), separate from the shared local
container:

- **Exact round trip.** On a fresh reset of `main`, with production's two
  legacy policies substituted, the rollback produced a function catalog
  identical to production's: 1,064 functions, same fingerprints, same grants,
  same owner. The bundle then produced one identical to `main`'s
  (1,072 functions). A second bundle run, a second rollback run and another
  rollback/bundle cycle left the catalog identical each time.
- **Fails closed.** With one function changed to an unreviewed body, both the
  bundle and the rollback stopped with nothing changed, and the preflight
  reported `unknown`. With a dependency renamed away, the bundle stopped with
  nothing changed, and the preflight listed it.
- **Overview equivalence.** Production's and `main`'s overview functions ran
  side by side for all 8 seeded personas. The fixture had 44 requests in all
  14 states, on an active and an on-hold project, with arrangements,
  self-created approvals, a pending amendment and an expired membership.
  Three rotated windows covered every visible request. Outputs were
  identical, with 0 `actor_can_act` differences.
- **Full gate.** Fresh reset, then rollback, then bundle: the catalog was
  identical to `main`, and `supabase test db` passed 192 files and
  6,348 tests, the same as `main`. An authenticated legacy write still fires
  the `app_touch_updated_at` trigger after its execute grant is revoked.
- **Anon probe.** With production's anon table grants and `PUBLIC` policy
  roles reproduced locally, an anon insert into `materialRequests` with an
  empty `engineerId` succeeded before the bundle. After it, the insert failed
  with `permission denied for function app_has_cap` and the notification
  read with `permission denied for function notification_visible_to_caller`.
- **Search.** The old and new search functions ran side by side on the same
  items; that is the table above.

# Worker Records

Status: slice 1 (database foundation and read-only register) implemented;
not yet applied to any database. Authority:
[`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) section 33.

## What it is

The employment record kept beside each Workforce worker: company, trade
licence number, passport number, basic salary, housing, others, total salary
and a photo. It is shown in User Management on a **Workers** tab. It is
reference data, not payroll.

## Access

| Capability | Allows | Default holders |
|---|---|---|
| `worker_records.view` | Read the register, a record and photos | Admin, Accountant |
| `worker_records.manage` | Create, edit, set photo, import (later slices) | Admin, Accountant |

Admin may grant either capability to one person in User Access; that is how
PR staff receive it.

Accountant is otherwise an Accounts-only role (R39). The migration widens
that rule by exactly these two keys through
`v1_accountant_may_hold_capability`, replacing only that test inside
`v1_permission_candidate_raw`, `v1_permission_legacy_raw` and
`v1_permission_guard_assignment`. The replacement refuses to run unless each
live definition contains the expected text exactly once, so later changes to
those functions are preserved. Neither capability depends on `workforce.view`, and no
`users.*` capability is involved, so a holder gains no attendance access and
cannot see or change login accounts.

The client shows the tab only when `YORKS_V1_WORKER_RECORDS` is on and the
confirmed permission snapshot grants `worker_records.view`. Hiding is not the
boundary: every function below rechecks the capability and the active actor.

## Database

Migration `supabase/migrations/20261110120000_worker_records_foundation.sql`;
apply script `supabase/release/worker_records_bundle.sql`.

| Object | Purpose |
|---|---|
| `v1_worker_employment_records` | One row per worker. No client grants. `total_salary` is generated. Unique passport number. No hard delete. |
| `v1_worker_employment_record_revisions` | Append-only before/after of each change. No client grants. |
| `v1_list_worker_records(search, company, status, limit, offset)` | Register page, counts, company list and totals over the whole filtered set. |
| `v1_get_worker_record(worker_id)` | One record. |
| `yorks-worker-photos` bucket | Private. Read needs `view`; upload needs `manage` and an existing worker. Path `workers/<worker_id>/<uuid>.<jpg|png|webp>`. |

Money is `numeric(12,2)` in Postgres and decimal text on the wire. A null
amount means "not entered".

Company is the existing `v1_workforce_workers.employer_company`. Nothing in
the Workforce tables, functions or projections is changed.

## Client

`Widget -> controller -> repository -> RPC`:

- `lib/shared/models/yorks_v1_worker_record.dart`
- `lib/shared/repositories/yorks_v1_worker_record_repository.dart`
- `lib/shared/providers/yorks_v1_worker_record_provider.dart`
- `lib/features/admin/presentation/widgets/yorks_v1_worker_records_tab.dart`
- access in `YorksV1UserManagementAccess`
  (`lib/features/admin/presentation/screens/user_management_screen.dart`),
  the sidebar (`lib/app/yorks_v1_workspace_shell.dart`) and the route guard
  (`lib/app/router.dart`).

Reads need connectivity. Nothing is shown optimistically, and a failed load
shows an error with the last confirmed rows, never an empty register.

## Release

1. Run `supabase db reset` and `supabase test db` locally
   (`supabase/tests/database/yorks_worker_records_foundation.test.sql`).
2. Paste `supabase/release/worker_records_bundle.sql` into the SQL editor on
   staging. Do not use `supabase db push` or `supabase migration repair`.
3. Build staging with `YORKS_V1_WORKER_RECORDS=true` and check as Admin,
   Accountant, a person granted `worker_records.view`, and an engineer
   without it.
4. Repeat the bundle on production, then deploy with the flag on.

## Data preservation and rollback

Additive except for the Accountant rule above: two capabilities, two tables,
new functions, one bucket and two storage policies. No existing row, policy
or grant is changed.
To roll back, turn the flag off and set `is_assignable = false` on both
catalogue rows. Keep every record, revision and stored photo.

## Not yet built

- Slice 2: create and edit a record, upload a photo.
- Slice 3: Excel import with a preview.

## Not included

Payroll calculation, payslips, WPS or bank files, salary history reports,
Excel export of the register, document scans and expiry reminders, a PRO
role, and any change to attendance.

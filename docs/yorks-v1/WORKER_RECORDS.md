# Worker Records

Status: all three slices implemented (register; add/edit and photo; Excel
import). Database tests pass locally. Not yet applied to staging or
production. Authority:
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
| `worker_records.manage` | Create and edit a record, set a photo, import a sheet | Admin, Accountant |

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

Migrations `20261110120000_worker_records_foundation.sql`,
`20261110130000_worker_records_save_and_photo.sql` and
`20261111100000_worker_records_import.sql` in `supabase/migrations/`; all
three, in order, in the apply script `supabase/release/worker_records_bundle.sql`.

| Object | Purpose |
|---|---|
| `v1_worker_employment_records` | One row per worker. No client grants. `total_salary` is generated. Unique passport number. No hard delete. |
| `v1_worker_employment_record_revisions` | Append-only before/after of each change. No client grants. |
| `v1_list_worker_records(search, company, status, limit, offset)` | Register page, counts, company list and totals over the whole filtered set. |
| `v1_get_worker_record(worker_id)` | One record. |
| `v1_save_worker_record(payload, expected_version, idempotency_key)` | Create a worker with a record, or update one record. Version-checked and retry-safe. |
| `v1_set_worker_photo(worker_id, object_path, expected_version, idempotency_key)` | Attach an already-stored photo. Version-checked and retry-safe. |
| `v1_preview_worker_records_import(rows)` | Classifies each sheet row (new, update, unchanged, problem). Writes nothing. |
| `v1_import_worker_records(payload, idempotency_key)` | Imports every row or none; refuses if any row has a problem or the data changed since the preview. |
| `yorks-worker-photos` bucket | Private. Read needs `view`; upload needs `manage` and an existing worker. Path `workers/<worker_id>/<uuid>.<jpg|png|webp>`. |

Money is `numeric(12,2)` in Postgres and decimal text on the wire. A null
amount means "not entered".

Company is the existing `v1_workforce_workers.employer_company`. No Workforce
function or projection is changed.

### Writes

- A new worker gets number `WR-000001…`, type `yorks_employee`, status
  `active` and the entered joining date.
- On an existing worker the save may correct name, company and designation
  only. Status, dates, trade, type and assignments stay with Workforce
  Administration and its own checks.
- `expected_version` is the employment record version the form opened with
  (0 when the worker had no record). A stale version is a conflict; nothing
  is overwritten.
- The idempotency ledger and the audit trail store the worker id, the record
  version and the names of changed fields — never a salary or passport value.
  The full before/after is in the protected revisions table.
- Import matching: passport number first (names must agree), then exact
  name + company (spacing and case ignored), otherwise a new worker. A
  passport held by a differently named worker, a different stored passport,
  two saved workers with the same name and company, or a person repeated in
  the file is a row problem, and any problem blocks the whole file. On the
  device, a Total Salary that is not Basic + Housing + Others, or an amount
  that is not a number, is also a problem.
- An import never renames or re-dates an existing worker, and a blank cell
  keeps the stored value. New workers take one designation and joining date
  chosen in the preview, because the sheet has neither.
- At most 500 rows per file. The import's audit event and idempotency entry
  hold counts only; each changed worker gets one `imported` revision.
- A photo is cropped square, resized to 512 px and re-encoded as JPEG on the
  device (which also drops camera metadata such as location), uploaded, then
  attached. Replaced photos are kept.

## Client

`Widget -> controller -> repository -> RPC`:

- `lib/shared/models/yorks_v1_worker_record.dart`
- `lib/shared/repositories/yorks_v1_worker_record_repository.dart`
- `lib/shared/providers/yorks_v1_worker_record_provider.dart`
- `lib/features/admin/presentation/widgets/yorks_v1_worker_records_tab.dart`
- `lib/features/admin/presentation/widgets/yorks_v1_worker_record_form.dart`
- `lib/shared/services/yorks_v1_worker_photo_service.dart`
- `lib/shared/services/yorks_v1_worker_workbook_service.dart` (sheet reader, template)
- `lib/features/admin/presentation/widgets/yorks_v1_worker_import_dialog.dart`
- access in `YorksV1UserManagementAccess`
  (`lib/features/admin/presentation/screens/user_management_screen.dart`),
  the sidebar (`lib/app/yorks_v1_workspace_shell.dart`) and the route guard
  (`lib/app/router.dart`).

Reads need connectivity. Nothing is shown optimistically, and a failed load
shows an error with the last confirmed rows, never an empty register.

## Release

1. Run `supabase db reset` and `supabase test db` locally
   (`yorks_worker_records_foundation`, `yorks_worker_records_save_and_photo`
   and `yorks_worker_records_import` in `supabase/tests/database/`).
2. Paste `supabase/release/worker_records_bundle.sql` into the SQL editor on
   staging. Do not use `supabase db push` or `supabase migration repair`.
3. Build staging with `YORKS_V1_WORKER_RECORDS=true` and check as Admin,
   Accountant, a person granted `worker_records.view`, and an engineer
   without it.
4. Repeat the bundle on production, then deploy with the flag on.

## Data preservation and rollback

Additive except for the Accountant rule above: two capabilities, two tables,
one sequence, the functions above with their internal helpers, one bucket and
two storage policies. No existing row, policy or grant is changed.
To roll back, turn the flag off and set `is_assignable = false` on both
catalogue rows. Keep every record, revision and stored photo.

## Not yet built

- A "Worker records" link from Workforce Administration.

## Not included

Payroll calculation, payslips, WPS or bank files, salary history reports,
Excel export of the register, document scans and expiry reminders, a PRO
role, and any change to attendance.

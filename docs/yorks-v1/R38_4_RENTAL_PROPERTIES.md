# Yorks R38.4 Rental Properties

Status: implemented locally; production deployment is a separate release-owner
action.

The owner's 20 October 2026 rental-only revision is recorded in
[`RENTAL_TRUST_AUDIT_2026-10-20.md`](RENTAL_TRUST_AUDIT_2026-10-20.md).
It adds direct intake of the supplied eleven-column property tracker, optional
incomplete details with completion recommendations, separate annual/monthly
rent, explicit billing setup and protected rental reminders. That later
approval supersedes the original occupied-lease required-field and monthly-only
assumptions below. Release/import completion remains evidence-dependent.

## Delivered scope

R38.4 replaces the retained local rental screen with one normalized,
server-authoritative Admin workspace:

- overview KPIs, attention queue, search, status filters and a dense property
  register;
- property, tenant and current-lease create/edit with record-version conflict
  checks;
- generated monthly rent schedule, partial/full receipts and outstanding
  balances;
- CDC/PDC registration and controlled status transitions;
- lease expiry monitoring, archive-with-reason and append-only activity;
- five-sheet Excel download/import with a read-only preview before the final
  trusted command;
- Property & Lease, Rent Schedule, Payment History, CDC/PDC and Lease Expiry
  Excel exports;
- rental attachments and revisions through the existing Yorks controlled
  Documents storage, version and audit chain.

The full desktop register keeps the complete property, tenant, contract, rent,
current-period, outstanding, next-cheque and lease state visible in one row at
1366 px. At 360 px the same authorized record becomes a bounded card rather
than a compressed spreadsheet.

## Trust and authorization boundary

The Flutter path remains:

`Widget -> Riverpod controller/provider -> rental repository -> trusted RPC`

The route, every rental RPC and rental document target require the exact
server-controlled `admin` role. Per-user or legacy rental capability overrides
cannot expose this commercial workspace. Authenticated clients receive no
direct grants on the normalized rental tables. Tenant, rent, receipt and cheque
records are returned only through shape-controlled RPC projections.

Critical writes validate actor, role, record version, current lease, amounts,
dates and idempotency keys on the server. Payments and cheque transitions are
append-only audit events; a retry cannot duplicate a receipt, cheque command,
import or document upload intent.

## Data model and commands

The additive model uses:

- `v1_rental_properties`
- `v1_rental_leases`
- `v1_rental_periods`
- `v1_rental_receipts`
- `v1_rental_cheques`

Trusted commands/projections include:

- `v1_save_rental_property`
- `v1_record_rent_payment`
- `v1_save_rental_cheque`
- `v1_transition_rental_cheque`
- `v1_archive_rental_property`
- `v1_get_rental_portfolio`
- `v1_get_rental_property`
- `v1_import_rental_workbook`
- `v1_get_rental_export_data`
- `v1_prepare_rental_document_upload`
- `v1_rental_document_workspace_projection`

## Workbook contract

The import format contains exactly these sheets:

1. `Instructions`
2. `Rental Properties`
3. `Payment History`
4. `Cheque Register`
5. `Lists`

File selection and decoding perform no mutation. The preview classifies create,
update, warning and blocking rows. Only Confirm Import calls the idempotent
transactional RPC, which repeats uniqueness, linkage, amount, date and role
validation before committing the entire workbook.

## Migrations and preservation

- `20260811045718_yorks_r38_4_rental_properties.sql` adds normalized rental,
  rent, receipt and cheque records plus Admin-only commands.
- `20260811060245_yorks_r38_4_rental_import_export.sql` adds the transactional
  workbook command and export projection.
- `20260811080119_yorks_r38_4_rental_documents.sql` adds `rental_property` as a
  controlled-document target without creating a parallel file store.

Historical `rentalUnits` and `rentPayments` data is not deleted, rewritten or
silently promoted. Rollback is therefore non-destructive: disable the R38.4
route, stop calling the new RPCs and retain the new relations for audit and a
later reconciliation. Do not drop populated rental tables or copy protected
rent/tenant data back into the legacy generic collection.

## Evidence and acceptance

Flutter evidence is captured at:

- `test/goldens/r38_4/rental_register_desktop.png`
- `test/goldens/r38_4/rental_register_mobile.png`
- `test/goldens/r38_4/rental_property_register_desktop.png`
- `test/goldens/r38_4/rental_property_register_mobile.png`
- `test/goldens/r38_4/rental_detail_desktop.png`
- `test/goldens/r38_4/rental_detail_mobile.png`

The focused Flutter suite covers the five-sheet contract, preview-only import,
blocking duplicate payment rows, all five exports, responsive overview/register
and property detail, and controlled Documents integration. pgTAP covers Admin
positive access, non-Admin denial, direct-table denial, idempotency, conflicts,
amount/state invariants, import atomicity and document authorization.

Production remains untouched until the release owner explicitly authorizes the
migrations and matching Flutter web/mobile build.

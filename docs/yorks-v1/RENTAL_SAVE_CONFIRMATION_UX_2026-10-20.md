# Rental save confirmation — 20 October 2026

The owner requested a clear summary of updated and remaining details after
saving a property, on web and mobile.

## Behavior and scope

- A confirmed create or edit opens a persistent confirmation with the property
  identity, the fields updated in that save, and the current missing details.
  Cleared fields are explicitly marked. A save without field changes says so.
- Updated fields compare the original projection with the refreshed server
  projection at the expected next record version. Editor defaults are not
  treated as saved lease facts for a property without a lease. If a newer
  version has already arrived, the confirmation explains that the current
  details reflect a subsequent edit instead of attributing those edits to this
  save.
- The existing trusted save command remains the authority for success. A
  follow-up read failure cannot turn an acknowledged save into a failed save.
  The confirmation retains success and offers Refresh details, which performs
  no write. Done remains available while the read is loading or unavailable.
- Missing details come from the server's current completion projection.
  Billing setup remains explicit and separate from optional details. No
  opening balance is inferred, and no mandatory field or financial policy
  changes.
- Complete remaining details opens the existing focused editor with the
  refreshed version and saved values. A further save has its own command and
  confirmation. Cancel keeps the earlier successful save. New-property
  navigation uses the dashboard State context so its refresh cannot invalidate
  the navigation context while confirmation is open.
- The bounded dialog scrolls its contents while keeping actions reachable.
  Phone actions stack at full width; desktop actions wrap. New copy and field
  labels support English, Arabic, Urdu and Hindi, with success/read status
  exposed as an accessibility live region.

Affected files are the rental presentation screen, its localized strings,
the presentation receipt model, and focused rental tests/visual baselines.
Controllers, repositories, RPC/RLS, routes, notification transport and schema
are unchanged. The receipt is transient UI feedback, not another audit store.

## Verification and release

The focused tests cover changed/cleared/no-change fields, persisted versus
submitted values, absent leases, intervening versions, loading/read failure,
read-only refresh retry, rejected saves, successive completion with the new
version, creation navigation and existing uncertain-save idempotency.

Visual evidence:

- `test/goldens/r38_4/rental_save_summary_1366.png`
- `test/goldens/r38_4/rental_save_summary_360.png`
- `test/goldens/r38_4/rental_save_summary_ar_360.png` at 1.3 text scale

Final gate and deployment results will be recorded after verification.

## Preservation and rollback

No production business records are changed for testing. No migration or data
rollback is needed. The preceding retained web deployment is
`dpl_B96grAdqY4GbnnG72eJj1c8xBDLv`.

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

The completed combined release passed:

- Dependency resolution, changed-file formatting, full analyzer and diff checks.
- **2,898 Flutter tests**, with four existing skips, including the rental
  confirmation and deployed authentication boundary regressions.
- CI web and APK builds. The APK uses ephemeral CI signing and is not an Android
  distribution artifact.
- **4,876 database assertions across 143 files**, after a successful reset of
  the isolated rental audit project. No schema files changed during integration.
  The audit project was stopped with its backup retained.
- Desktop 1366px, phone 360px and Arabic phone at 1.3 text scale visual review.
  Save journeys use the real command controller with deterministic repository
  fixtures. No live property saves or physical mobile-device test are claimed.

The first full-suite attempt was interrupted by insufficient local disk space.
Inactive generated Flutter build-cache entries in the rental worktree were
removed, and Docker recovered before the final successful gates. No primary
checkout source or production records were changed by that recovery.

Implementation commit `5e904d718eeaba0a13c39f5b9b7b79539e7e649f` was combined
with the authentication fix that reached production during verification,
`5652860bb3dc5e86a0e32678a8cb1b9828f60f0d`. Clean runtime commit
`ae7e909d9dc92bba5435dae77b503a9403ec1ef4` retains both. The earlier rental-only
candidate was not promoted over the newer authentication release.

Production deployment `dpl_2DGSApN2EadBAQJG2zRC2XrsJin8` is READY and serves
<https://yorks-r35.vercel.app>. Both the staged artifact and canonical URL
passed **34 route/asset hash checks**. Its main bundle is 9,969,915 bytes
(2,872,700 gzip bytes at the startup gate), SHA-256
`47fed4e2e4d97d3298fc1477d6f5e531da0865135a69715ea482f98bd2f64b5e`.

Evidence: [release record](evidence/rental-save-confirmation-20261020/release.json),
[artifact measurements](evidence/rental-save-confirmation-20261020/artifact.json),
[candidate hashes](evidence/rental-save-confirmation-20261020/verify-candidate.jsonl)
and [canonical hashes](evidence/rental-save-confirmation-20261020/verify-canonical.jsonl).

## Preservation and rollback

No production business records are changed for testing. No migration or data
rollback is needed. The preceding retained web deployment is
`dpl_E2Yedn4SoTnHZxgrshspvvBUcLaB`, which retains the deployed authentication fix.

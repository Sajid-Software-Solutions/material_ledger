# Rental navigation and actionable guidance — 20 October 2026

The owner requested clear next steps from Action Required, property details
inside the existing workspace chrome, reliable rental Back navigation, and
predictable desktop/mobile behavior. This presentation-only follow-up starts
from the verified rental release `9bd2ccd` / deployed implementation `e1015f5`.

## Findings and implementation

- `/rentals/:id` used an unframed root route. It now uses the same Yorks shell
  wrapper as other record pages, retaining the sidebar/header, selected Rentals
  destination and native navigation stack. Direct rental links return to the
  register. Only rental destination matching and its direct-link fallback were
  added to the shell; shared Back/Forward helpers and other routes are unchanged.
- Action Required described a condition and opened a generic overview. A shared
  presentation model now produces explicit rent, cheque, expired/upcoming lease,
  opening-balance and missing-detail guidance from the protected projection.
  The list and detail use the same reasons and named review buttons. The clicked
  reason stays first; rent and cheque links select the corresponding section.
  Review buttons reveal the section or open the existing editor. No click saves
  business data, infers a balance, converts a rent amount or renews a lease.
- Expired leases now say "expired". Ordinary vacancy is a register status, not
  an urgent problem. Confirmed financial work sorts before optional completion;
  a count and View all control expose every affected property, not only six.
- Details show the actual missing fields and state that saved records can be
  completed later. A stale action link explains when its issue has resolved.
  Archived properties offer only remaining confirmed rent review.
- The overview register no longer squeezes desktop money/tenant columns into
  a half-width panel. Readable property summaries show annual/monthly units,
  tenant, status and unconfirmed opening balances; the full register remains
  accessible. Mobile panel actions wrap beneath headings, tabs have meaningful
  icons, and action buttons keep at least 44px targets.
- New guidance is localized in English, Arabic, Urdu and Hindi. Existing import,
  command recovery, immutable source evidence, edit/save, permissions and
  notification services remain intact.

## Verification

The new route journey test uses the actual application router, deferred rental
loader and workspace shell. It covers desktop and 360px navigation, Back/Forward,
system Back, direct links, explicit editing, stale actions, rent/cheque section
selection and Arabic at 1.3 text scale. Its scenarios share one app-lifetime
zone because production deliberately caches the deferred-library future.

Visual evidence is under `test/goldens/r38_4/rental_action_shell_*` and
`rental_action_cheques_360.png`, together with updated rental dashboard/detail
and editor/recovery baselines. Full gate and release results are recorded below
after verification.

## Completed gates and live release

- `flutter pub get`, changed-file format check, full `flutter analyze` and
  `git diff --check` passed. The final full Flutter suite passed **2,882 tests**
  with four existing skips. The 52 focused rental tests and 15 cheque-action
  tests also passed.
- CI web and APK builds passed. The APK uses the requested ephemeral CI
  signing lane; it is not an Android distribution artifact.
- A reset of the isolated audit database and its full pgTAP suite passed
  **4,876 assertions across 143 files**. The audit project was stopped with its
  backup retained; the primary local database was untouched.
- Production was built from clean implementation commit
  `e39c01697751990f81c3e99a5cd1cf9f5e4978b5`. The unchanged startup gate measured
  `main.dart.js` at 9,965,418 raw / 2,872,492 gzip bytes. Its SHA-256 is
  `57422b0ad8d93b65333816242e3d43fbc8dad93129a36678edd598532250979f`.
  The bundle targets the existing production backend and contains no staging/
  CI backend or credential detected by the reviewed main-bundle checks.
- Staged production deployment `dpl_JCnBZWcMEKVy633C1gFNyCqXzry6` passed all
  **34 route/asset hash checks** before promotion. The canonical site passed the
  same checks and resolves to that exact deployment:
  <https://yorks-r35.vercel.app>.
- Live Chrome verification opened the expired-lease action for `OFFICE-AC1-5`,
  confirmed its precise reason and next-step buttons, and visually confirmed
  the retained sidebar/header and Rentals selection. Complete details opened
  the existing editor; Cancel made no business changes. The workspace header
  Back returned to the rental overview and its original action item.
  The register still showed the 52 completion items and AED 710,238 annual
  rent. Desktop, 360px/mobile, Arabic/text scaling, Forward/system Back and
  direct-link fallback are covered by the automated route/visual checks.
  No physical mobile-device or new push-delivery acceptance is claimed.

The [release record](evidence/rental-navigation-20261020/release.json),
[artifact measurements](evidence/rental-navigation-20261020/artifact.json),
[candidate hashes](evidence/rental-navigation-20261020/verify-candidate.jsonl)
and [canonical hashes](evidence/rental-navigation-20261020/verify-canonical.jsonl)
retain the verification evidence.

## Preservation and rollback

No repository/RPC, database migration, backend role, financial rule or business
record changes are required. All 52 imported records and original-source
metadata remain in place. Rollback is promotion of the previous retained web
artifact `dpl_ABmQsPZ2TefLjD9PWYiZLKewSRP1`; no database reversal or
notification replay is needed.

## Further usability opportunities

Keep subsequent improvements small: filter the action queue by issue type;
open the relevant editor group for each completion task; and preserve a clear
"saved / still missing" result after an edit. Any future renewal flow should
retain the previous lease rather than overwrite its history. These are future
options, not additional workflow changes in this release.

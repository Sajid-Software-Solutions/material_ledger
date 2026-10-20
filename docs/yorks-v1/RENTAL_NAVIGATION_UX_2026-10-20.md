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

## Preservation and rollback

No repository/RPC, database migration, backend role, financial rule or business
record changes are required. All 52 imported records and original-source
metadata remain in place. Rollback is promotion of the previous retained web
artifact; no database reversal or notification replay is needed.

## Further usability opportunities

Keep subsequent improvements small: filter the action queue by issue type;
open the relevant editor group for each completion task; and preserve a clear
"saved / still missing" result after an edit. Any future renewal flow should
retain the previous lease rather than overwrite its history. These are future
options, not additional workflow changes in this release.

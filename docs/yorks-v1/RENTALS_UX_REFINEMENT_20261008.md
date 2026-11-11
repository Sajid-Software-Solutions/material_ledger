# Rentals UX refinement — 8 October 2026

## Request and scope

The owner asked to apply the Overview/Analytics improvement approach to Rentals.
The first reversible UI slice is prepared for staging review. Production rollout
preference was requested separately and has not yet been confirmed for this slice.

The [R38.4 rental contract](R38_4_RENTAL_PROPERTIES.md) continues to govern every
property, lease, receipt, cheque, workbook and document operation. Exact Admin
access, server version checks, idempotency and historical records are unchanged.

## Observed problems

Read-only production inspection of `/rentals` at desktop width showed repeated
headings, an import/export toolbar competing with the title, six monetary/ratio
cards before records and a misleading 0% occupancy for an empty portfolio.
Source inspection found mobile sections in a horizontal rail, property navigation
using replacement rather than a returnable detail route, and a wide property
editor whose two-column breakpoint made mid-width screens inefficient.

## First slice implemented

- One workspace heading in the existing universal shell.
- Compact import/template and export menus; Add property stays prominent.
- A mobile section dropdown exposes every existing register in one control.
- Property attention precedes the preview and KPI cards. Archived properties do
  not become vacancy/expiry actions, but outstanding balances remain visible.
- Empty portfolios explain Add property / workbook import without empty KPIs.
  Zero denominators render no percentage even in a nonempty historical portfolio.
- Property detail navigation uses push, preserving the register's search and tab
  when returning. Refresh loading does not present old data as newly confirmed.
- The property editor is bounded at 920px and uses two columns from 560px of
  form content; all existing fields and validation remain available.
- Changed workspace controls use centralized EN/AR/UR/HI copy, separate from
  stable workbook names and persisted business values.

## Further review identified

The remaining property-detail and editor copy is inherited English-only content;
full module localization is not claimed by this slice. A second slice should
simplify detail actions and progressive disclosure in the longer lease form.

The existing editor closes before its asynchronous save completes. In addition,
`saveProperty` performs a detail read after the mutation, so a rejected detail
read can be presented as a save failure after a successful write. A separate
command-result/recovery slice should preserve input, distinguish unconfirmed
outcomes, and retain the command key on retry. Do not treat a UI-only redesign as
proof of these transaction recovery semantics. No live payments or other business
records were created to test the design.

## Verification

The focused rental suite covers five-sheet template/import preview, duplicate
payment blocking, five Excel exports, controlled Documents, desktop/mobile
registers and detail, plus the empty-state/import-menu regression. Updated
visuals are under `test/goldens/r38_4/`. Full gate and staging results are recorded
below when complete. Physical-device, screen-reader and real-user acceptance
remain separate from browser and automated evidence.

### Completed gate and staging record

- Source: `3de1d8046bab49a0492fcdf6febd218d741df050`.
- Full Flutter suite: 2,560 passed, four retained skips; rental suite: 12 passed.
- Analyzer, dependency resolution, changed-file format and diff checks passed.
- CI web and ephemeral-signed APK gates passed. No distribution Android release.
- Local database reset and pgTAP: 125 files, 3,661 tests passed. No hosted schema
  or business data changes were made.
- Staging deployment: `dpl_DgQYDFzyFKLSfT2bJt6yDUbjaZCo` at
  `https://yorks-r35-n6jalcgky-sajid-alis-projects-0ec775a2.vercel.app`.
- Existing staging alias updated after 27 route/asset hash checks passed:
  `https://yorks-r35-staging.vercel.app/#/rentals`.
- Production remains unchanged. This is the first UI refinement, not completion
  of the wider save-recovery, detail-form and full localization work identified
  above.

## Second slice: property forms and save recovery

- Property detail now uses the universal navigation instead of a duplicate back
  control. Every detail section is available in the mobile dropdown.
- Vacant-property creation starts with property facts. Tenant, contract and rent
  sections expand on demand; occupied properties and existing leases expose them.
- Save keeps the editor open with its values until the command is confirmed.
  Submission disables duplicate clicks and dismissal while in flight.
- The repository returns the confirmed property ID directly; a subsequent detail
  read failure cannot masquerade as a failed write.
- An uncertain result locks the submitted values and offers Confirm save using
  the same payload and idempotency key. A corrected rejected payload gets a new
  key. Conflicts retain the values and instruct the user to reload current data.
- New command messages and detail navigation labels use EN/AR/UR/HI resources.
- Regression tests cover rejected saves, corrected retries, uncertain outcomes,
  duplicate clicks, confirmed writes without detail reads, and editor goldens at
  1200px and 360px. The focused suite now has 17 tests.

This recovery is scoped to property saves. Payment and cheque dialogs retain
existing behavior. Values are retained in the open editor, not as durable drafts
across explicit dismissal or browser closure. Full inherited-copy localization,
physical-device and real-user acceptance are not claimed. No migrations or
hosted business-data mutations are part of this slice.

### Second-slice verification and staging

- Source: `39478ff` (save recovery: `0373eef`).
- Full Flutter gate: 2,565 passed, four retained skips. Local database reset and
  pgTAP: 125 files, 3,661 tests passed. Analyzer, format and diff checks passed.
- CI web and ephemeral-signed APK builds passed before the final mobile field
  minimum-height adjustment. After that small visual change, the 17-test rental
  suite, analyzer and staging web build were rerun and passed.
- Mobile text and dropdown fields have a minimum 48px interaction height.
- Final staging deployment: `dpl_6yuZXKMrqpnbSgRd3HWnexymCrMH`, immutable URL
  `https://yorks-r35-7ka2qjrcm-sajid-alis-projects-0ec775a2.vercel.app`.
- Production is unchanged; this record does not authorize production promotion.
- Candidate and staging alias each passed all 27 route/asset hash checks.
- Authenticated staging browser checks covered the empty portfolio and property
  editor at desktop and 360px. Screenshot evidence is in
  `/private/tmp/yorks-rentals-evidence-20261008/final-editor-desktop.jpg` and
  `/private/tmp/yorks-rentals-evidence-20261008/final-editor-mobile.jpg`.
  Populated property details and save-failure paths were fixture-tested locally;
  no live property, lease, cheque or payment was created during verification.

## Owner-authorized production release — 8 October 2026

The owner explicitly requested “update production” after reviewing the completed
staging slice. The production artifact was rebuilt from clean source `1a503cf`
with the existing production configuration. Accounts, Company Use, Workforce,
Calculator Workspace and Project Setup enablement were preserved. No database
migration or live business-record mutation was required.

- Production candidate: `dpl_ATbb2j7yzeGgc3ggwMPEhFa2woc3`.
- Immutable URL: `https://yorks-r35-ovnt890ju-sajid-alis-projects-0ec775a2.vercel.app`.
- Local artifact: `/private/tmp/yorks-rentals-production-20261008`.
- Previous production, retained for rollback:
  `dpl_5jsSC2katbrBQnFoXxyb4CUVTAgV`,
  `https://yorks-r35-l86ndm73j-sajid-alis-projects-0ec775a2.vercel.app`.
- Production backend binding, absence of CI/staging placeholders and required
  Flutter/PWA assets were checked before upload. The artifact was deployed with
  `--prod --skip-domain`, then verified before promotion.
- Promotion succeeded. Candidate and `https://yorks-r35.vercel.app` each passed
  all 26 production route/asset hash checks (production deferred bundles differ
  from the staging build).
- Authenticated production browser verification confirmed the new Rentals home
  and property editor at desktop and 360px. Console error scan returned none;
  Vercel's bounded 10-minute error query returned no logs. This static-host scan
  is not proof of all backend/runtime behavior or long-term monitoring.
- Screenshots: `/private/tmp/yorks-rentals-evidence-20261008/production-home.jpg`,
  `production-editor-desktop.jpg`, and `production-editor-mobile.jpg` in the same
  directory. No business record was created or changed for this smoke check.
- Existing automated/staging evidence above remains the save-recovery evidence;
  production verification did not submit a live property or payment.

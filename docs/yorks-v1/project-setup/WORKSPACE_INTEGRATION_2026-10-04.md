# Project setup workspace integration — 4 October 2026

**Historical release.** The later product-owner correction requires the new
forms inside the original Yorks top bar and persistent sidebar. The
feature-owned chrome decision below is superseded by
[the universal workspace and local-save correction](UNIVERSAL_WORKSPACE_AND_DRAFT_SAVE_2026-10-04.md).

## Root cause and correction

The staging candidate deployed the full application from `lib/main.dart`, not
the synthetic visual fixture. Its setup route nevertheless bypassed the shared
Yorks workspace shell. The desktop hamburger collapsed only the setup stage
rail, the phone drawer contained only Projects and setup stages, and search
offered only Projects as a module shortcut. Profile, notifications and sign-out
already used the real shared services, but normal workspace navigation was
missing from the new chrome.

The [route wrapper](../../../lib/app/router.dart) now uses
[`YorksV1WorkspaceShell(featureOwnsChrome: true)`](../../../lib/app/yorks_v1_workspace_shell.dart).
The [navigation scope](../../../lib/app/yorks_v1_workspace_navigation_scope.dart)
connects both setup headers to the canonical permission-filtered drawer, search
targets and session-scoped navigation history. The supplied header, stage rail,
mobile stepper and form layout remain feature-owned, with one header and one
zoom host. The local stage-only drawer and desktop collapse action are removed.

Create and Edit still enter through the existing application routes
(`/projects/new` and `/yorks/projects/<project-id>/edit`). Their GoRouter exit
guards and the feature's draft-aware pop/save decisions remain active; the outer
workspace pop handler does not issue a competing Back action. Draft identity,
acknowledgement, ownership, uncertain-command recovery and server authority are
unchanged. `YORKS_V1_PROJECT_SETUP` remains default off and browser-only; native
routes retain the accepted legacy experience. This correction changes no SQL,
RLS, RPC or commercial capability.

## Staging alias mismatch

Independent release inspection found that the stable staging alias
`yorks-r35-staging.vercel.app` still served the **26 September** candidate:

| Evidence | Observed value |
| --- | --- |
| Source | `449a0e01` |
| Deployment | `dpl_FxKmjTWKHzdo34uNXjDe9E4WHbNZ` |
| `main.dart.js` bytes | `10,423,896` |
| `main.dart.js` SHA-256 | `a535f2c106fb5018221cf9e593a6974d860b3cf96fe4320f608f285606452e44` |
| Compiled backend-reference occurrences | Staging `1`; production `0` |

The earlier 4 October preview from source `9dc91b8` had not been assigned to
that alias. The new full-app preview has now been built and byte-verified, and
**only the staging alias** was assigned to it. Production release remains a later,
separate step.
These observations preserve the older [staging release report](STAGING_RELEASE_2026-10-04.md)
as historical evidence rather than treating its preview as the current alias.

## Validation and remaining work

- **Eight focused integration tests passed:**
  [test source](../../../test/yorks_v1_project_setup_workspace_integration_test.dart).
  They cover real Projects → Create entry and re-entry, retained draft ID/name
  and acknowledged revision, zero dispatched project commands, and actual
  permission loading/denial boundaries on desktop and phone.
- The final full suite passed **2,272 tests with four retained skips**, including
  the drawer label assertion and both Projects → Create re-entry cases.
  Analysis found no issues; all seven changed Dart files were formatted.
  CI web passed the startup budget (10,007,045 bytes / verifier gzip 2,880,695).
  CI APK built with CI Ephemeral signing; it is not a production artifact.
- Actual browser inspection exposed a macOS platform Drawer warning caused by
  a null route label. The shared drawer now supplies the existing localized
  `quickNavigation` semantic label, with a regression assertion. Fresh final
  desktop and phone sessions showed no captured warnings/errors. A debug engine
  semantics-map error on a post-enable breakpoint resize remains an open browser
  accessibility gate; no semantics suppression or unproven form-key workaround
  was added.
- [Browser captures and inspection scope](visual-evidence/workspace-integration-2026-10-04/README.md)
  accompany this report. Synthetic visual fixtures can demonstrate the chrome;
  they do not establish authenticated remote navigation or live create/upload
  success.

## Verified staging release

- [Open the integrated Yorks staging website](https://yorks-r35-staging.vercel.app/yorks/projects),
  then use **Projects → Create project** with an authorized Engineering/Admin account.
- Clean source/build identity: `d218cf57a2e899ebfd8b36dd012d468dd8817f30`;
  committed and pushed before building the ordinary `lib/main.dart` application.
- Deployment: `dpl_6RaX6nWDp1cnXPbV2hh1xVet6ovq`, READY preview;
  [immutable preview](https://yorks-r35-qf5rat3sj-sajid-alis-projects-0ec775a2.vercel.app).
- Artifact: 59 static files / 54,035,149 bytes; main JavaScript 10,033,379 bytes,
  startup-verifier gzip 2,888,505; SHA-256
  `82d70d8ffb2908298414bb1ee0bd7588833cbe21fdb6854b8bb737b4e6e60b3c`.
- The bundle contains the dedicated staging reference twice, no production/CI/
  visual-fixture markers and no service credentials. The isolated upload has the
  reviewed existing Vercel project/team link and an explicit preview target.
- Both immutable preview and staging alias passed byte verification for all
  23 routes/assets, including six deferred modules and PWA files. Both additional
  Create/Edit deep routes deliver the exact SPA shell; these are delivery checks.
- The stable alias browser retained its existing Procurement session and rendered
  the real view-only Projects portfolio without console warnings/errors.
  Read-only browser resource inspection confirmed its resident main script
  matches the new bundle byte-for-byte, including SHA-256. This
  role correctly has no Create action. No privileges, business records or roles
  were changed. Authorized Engineering/Admin live creation and upload remain
  unrun; the positive entry/re-entry tests use simulated permitted reads.
- Production alias still resolves to `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`. Its
  9,678,001-byte JavaScript is byte-identical before/after: SHA-256
  `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.

The [machine release record](WORKSPACE_INTEGRATION_2026-10-04.json) preserves
source, deployment, old/new alias, hashes, checks and acceptance boundaries.
This staging release is not a production release or a complete source acceptance
pass. CI Android signature v2 and the CI Ephemeral certificate were verified;
production Android signing is a separate release lane.

Application rollback remains the default-off flag or prior verified staging
deployment. Preserve draft, journal, quarantine and tombstone namespaces; no
database rollback is needed for this shell correction.

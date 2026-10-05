# Project setup staging release — 4 October 2026

The owner requested staging publication so the new project creation experience
can be reviewed before a later production update. This authorizes this staging
candidate only. PR #44 remains a draft; its tracked flag default remains off.

## Review

- [Open staging project creation](https://yorks-r35-dqvwmxbrf-sajid-alis-projects-0ec775a2.vercel.app/projects/new).
- Sign in with an authorized **staging** account, then open **Projects → Create project**.
- The new desktop, tablet and mobile browser layouts are enabled by
  `YORKS_V1_PROJECT_SETUP=true`. Native apps retain the accepted legacy flow.
- The new preview origin has separate device drafts and sign-in storage.
- The live browser reached the protected Sign In page with
  `returnTo=/projects/new`; no startup warnings or errors were observed.
  [Live screenshot](visual-evidence/staging-2026-10-04/login.jpg).

The earlier six-screen desktop/mobile visual evidence is linked from
[the implementation index](README.md). Those captures use a synthetic
permitted fixture. This release does **not** claim authenticated staging
creation, activation, upload, conflict or uncertain-response UAT.

## Artifact and deployment

| Item | Verified value |
| --- | --- |
| Source | `9dc91b87a59178a7e8be438904388ac61b8b86ec`; clean, committed and pushed before building |
| Vercel project | `yorks-r35` / `prj_5jbKMKUBHdccpOCifJCgSOB6snDj` |
| Team scope | `sajid-alis-projects-0ec775a2` |
| Deployment | `dpl_AdFuaVR3FVUQEgTCPuPY2e8Sad3X` — READY |
| Target | Explicit `--target=preview`; API target `null`, aliases empty |
| Backend | Dedicated staging `iqltcyimlqtcwyzlemwx` |
| Static files | 59 files / 54,036,331 bytes |
| Archive dry run | One generated archive part / 19,765,416 bytes; base path is the isolated static directory and `.vercel` is ignored |
| `main.dart.js` | 10,034,560 bytes; startup-verifier gzip 2,888,952 bytes |
| JavaScript SHA256 | `82428f1ddfccd5165c8b9f666c848353da0264a3ad8e4dfc9faf766a4d571cd4` |

The canonical launcher used the existing ignored operator staging config with
an explicit staging environment and project-setup flag. Parent-process Supabase
URL/key overrides were removed before build. Existing Accounts, Company Material
Requests, Workforce and Analytics flags remained true; PostHog remained disabled.
The compiled JavaScript contains the staging backend reference and contains no
production project reference or CI placeholders.

Deployment uploaded an isolated copy of `build/web`, with the existing project
link and explicit team scope. No repository/toolchain files, dotenv files,
symlinks or service credentials were included. The dry-run archive is temporary;
its generated path is not a retained local tar file.

The [machine evidence](STAGING_RELEASE_2026-10-04.json) records byte-identical
verification of 23 routes/assets, including all generated deferred modules,
PWA workers and manifest. Two additional affected deep routes returned the exact
SPA shell: `/projects/new` and a non-record edit URL. These HTTP checks prove
routing/artifact delivery, not authenticated record access or workflow execution.

## Staging backend

Existing protected project, directory, permission and document contracts were
inspected without invoking business commands. The deployed document finalizer v5
is byte-identical to the source: SHA256
`fdb6b54c68a8a70b40c68e34ba7c49926da75d2a2d59147395b7c10569f15ce2`.
Its RPC remains service-only. The document bucket remains private, with the
existing 20 MiB and PDF/PNG/JPEG/XLSX/DOCX constraints.

Only the tracked additive migration
`20261003160930_project_setup_preserve_building_dependencies.sql` was applied.
A pinned transaction checked the exact effective update-function hash, applied
the source guard, checked the exact resulting hash, and recorded the original
version/name/source in the migration ledger. No generic database push or
historical-ledger repair was performed. Divergent historical staging versions
were preserved.

| Check | Before | After |
| --- | --- | --- |
| Update function MD5 | `877bce13b0f98339f4fcc516590de4a3` | `3db69005873353968c3eda754ef1de13` |
| Guard markers | 0 | 1 |
| Migration ledger entries | 182 | 183 |
| Projects / scopes / members / parties | 2 / 5 / 4 / 0 | 2 / 5 / 4 / 0 |
| BOQ rows / MRs / documents / audit events | 50 / 19 / 2 / 813 | 50 / 19 / 2 / 813 |

Source migration SHA256:
`a8894a6c8ffcb91cbc8a3cfd53d5f62640dcbaf97861980c5884f92cf7c3296e`.
The ledger's exact source MD5 is `ac8dde2c14ee6dee25f57a9c3cf251a8`.
Protected RPC grants are unchanged. Compared create/state/prepare/finalizer
function hashes are unchanged. No project or document record was created for
this deployment verification.

The guard rejects an edit that omits an existing active physical scope before
mutations. Older clients sending incomplete building IDs will receive the
reconciliation error. Common, supported renames/additions and existing history
remain protected.

The client also now recognizes the server's retained
`document_id` / `document_version_id` / `revision_number` upload receipt.
Recovery preserves the original payload/key and skips repeated Storage/finalizer
writes after a lost successful response. Invalid or contradictory receipts fail
closed. No Edge function redeployment was needed.

## Checks for this release

| Gate | Result |
| --- | --- |
| `flutter clean` / `flutter pub get` | Passed; lockfile unchanged |
| Changed Dart format / `git diff --check` | Passed |
| `flutter analyze` | No issues |
| Full `flutter test` | **2,264 passed / four retained skips** |
| Document finalization recovery | **28 passed**, included in full suite |
| Local project setup database recovery | **13 pgTAP assertions passed** |
| CI web with candidate flag | Passed; JavaScript 10,008,214 bytes, verifier gzip 2,880,823 bytes |
| CI APK with candidate flag | Passed; 110.6 MB; CI Ephemeral certificate verified |
| Actual staging web | Passed; startup size budget passed |
| Live route / asset hashes | All 25 checks passed |
| Live browser | Protected sign-in renders; zero observed startup warnings/errors |

The prior full local database suite (122 files / 3,546 assertions on Postgres
15.19) is recorded in [mobile validation](MOBILE_VALIDATION_2026-10-04.md).
The SQL source is unchanged since that gate; its focused 13-assertion recovery
suite was rerun for staging. Android's ephemeral certificate is verification
only, not a production signing identity. Hosted CI and named-persona UAT are
not converted into passes by these local checks.

Release logs remain under `/tmp/yorks-project-setup-staging-*`, including
`analyze.log`, `full-tests.log`, `ci-web.log`, `ci-apk.log`, `build-web.log`,
`guard-apply.log` and `live-verification.log`. The document-recovery log is
`/tmp/yorks-document-retained-receipt-compatibility-tests.log`.

## Production preservation and rollback

Production `yorks-r35.vercel.app` still resolves to
`dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`. Its `main.dart.js` remained
9,678,001 bytes with identical before/after SHA256:
`739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.
No production backend, alias, flag, deployment setting or PR merge was changed.

To roll back the browser candidate, use the prior staging artifact or build
with `YORKS_V1_PROJECT_SETUP=false`. Retain the building-history guard: do not
restore retirement behavior until the controlled dependency reconciliation
policy and release gate are accepted. Production promotion remains a later
owner decision.

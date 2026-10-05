# Combined production release — 6 October 2026

Status: **released and verified** at [yorks-r35.vercel.app](https://yorks-r35.vercel.app).
The product owner authorized production publication of the completed project
setup changes and all completed work from the chat **Update project view
layout**, with investigation and further improvements to follow tomorrow.

The machine-readable evidence is retained in
[`COMBINED_PRODUCTION_RELEASE_20261006.json`](COMBINED_PRODUCTION_RELEASE_20261006.json).

## Released source and included work

| Evidence | Value |
|---|---|
| Application source on merged `main` | `bb4432558ea6bdef0da958d6af4d50dd761d3d0e` |
| Tested combined candidate | `1ad40d3d951329a3e5b2e611530b7c113bc5374c` |
| Identical tree for candidate and merged `main` | `4f0411311a16282ec8cfba7ce95fde5abe7403a2` |
| Merged pull requests | [#44](https://github.com/SajidAfridi/material_ledger/pull/44), [#45](https://github.com/SajidAfridi/material_ledger/pull/45) |
| Production deployment | `dpl_GKcFd2A49YWDNHCiyL8Eh5Hnkqf3` — `READY` |
| Immutable deployment URL | [verified deployment](https://yorks-r35-gu8hyjnul-sajid-alis-projects-0ec775a2.vercel.app) |

The tested candidate and merged source have the same Git tree. Production was
built from the clean merged `main` revision, so its analytics release ID names
that revision rather than the candidate merge commit.

The inclusion audit covers these completed slices:

- Project workspace and tab layout, BOQ overview/folders/worksheet refinements,
  and embedded Project Accounts. The earlier released source `92169b6b` and
  retained main ancestor `af7c1b9` share tree
  `12958706aebcdbe03d4fe41cb494503e45bc84d3`; the preserved production snapshot
  therefore includes that work despite the historical source reconciliation.
- Subsequent Accounts responsive screens, complete exports and navigation,
  senior staff workspace, draft-conflict guard, set-wise MR register and
  arrangement/chat reconciliation. Their completed releases through PRs
  #33–#37 and #41 are already ancestors of the combined source.
- Project setup through `74720c32a71de7eb832f9b32f89c5efa52884831`: the five-stage
  desktop/mobile flow inside the universal workspace, confirmed draft feedback,
  saved-draft discovery, independent new drafts, direct Resume into editing,
  attachment/finalization recovery and retained building identity.
- `fb95b7e100795ec52e145b7ed81c20d95c57190f` and
  `1e3d0ac08c00a3f5dbd41dba52dd2cce3f3097ae`: authority-scoped MR read
  coalescing, short navigation freshness, targeted refreshes, reduced eager
  Procurement loading for engineering roles and bounded coordination analytics.
- `48c61643fa4627c999eaea81d9877a17995c5517`: authentication, authorization and
  other non-connectivity failures purge a record's previous protected
  projection before surfacing the error, preventing later fallback to denied
  data. Offline/backend failures alone may preserve the last authorized result.

Unfinished Accounts work in [PR #40](https://github.com/SajidAfridi/material_ledger/pull/40)
is outside this release. Completion of other source work does not imply that
unfinished work or staging demonstration records were published.

## Validation and artifact identity

| Gate | Result |
|---|---|
| Flutter analysis | No issues |
| Full Flutter suite | 2,448 passed; 4 retained fixture-dependent skips |
| Dart formatting | Zero changes |
| Clean local database reset and complete pgTAP suite | 122 files; 3,546 assertions passed |
| Project setup recovery | 13 assertions passed |
| Project editing and safe archive | 16 assertions passed |
| CI web build | Passed from the tested candidate |
| Android build | Passed with Yorks CI Ephemeral v2 signing; not publishable |
| Isolated candidate routes/assets | 24 core checks plus 2 project-setup deep routes: 26 checks passed |
| Promoted production routes/assets | The same 26 checks passed |
| Vercel project settings | Unchanged |

The database assertions include positive Project Engineer, assigned Site
Engineer and Admin edits that retain physical scope IDs; denied scope retirement
for those actors; denied Procurement edits; exact idempotent replay; changed
payload rejection; preserved active Common/building identities; and immutable
audit/version effects. These are local database tests, not production writes.

Production contains 60 artifact files totaling 54,183,998 bytes.
`main.dart.js` is 9,770,261 bytes, with gzip size 2,815,590 bytes and SHA-256
`a6a376d1ea0e86539ee2f5e458d171deb82f279f8e6532841a53f99cf487d345`.
The deployed routes, PWA files, workers and JavaScript assets matched the local
verified artifact. Production markers were present; staging, CI and fixture
markers were absent, and the clean release marker occurred once.

The CI Android APK is 111,057,968 bytes with SHA-256
`4eadede057f0ac886d29a4110e1b61ea8e03be31dbda9324c56b3fc0788a0b88`.
Its ephemeral signature verifies the build lane; this release publishes web
and does not publish a native Android store artifact.

## Production database guard and finalizer

The reviewed source migration is
[`20261003160930_project_setup_preserve_building_dependencies.sql`](../../supabase/migrations/20261003160930_project_setup_preserve_building_dependencies.sql),
SHA-256 `a8894a6c8ffcb91cbc8a3cfd53d5f62640dcbaf97861980c5884f92cf7c3296e`.
It patches only `public.v1_update_project(jsonb,uuid)` to reject omitted active
physical buildings until an accepted dependency reconciliation path exists.
It performs no business-table DML and removes no records or history.

The production MCP application deliberately recorded this reviewed migration as
remote ledger version **`20261005230010`**, name
`project_setup_preserve_building_dependencies`. That version differs from the
canonical source filename **`20261003160930`**. Body and privilege verification
establish the applied change; these ledger versions must not be described as
aligned. Future reconciliation must account for this mapping before any CLI
migration operation. A generic `db push` is not a safe reconciliation step.

| Function evidence | Before | After |
|---|---|---|
| Definition MD5 | `877bce13b0f98339f4fcc516590de4a3` | `3db69005873353968c3eda754ef1de13` |
| Guard marker | Absent; expected insertion anchor present | Present; body matches reviewed staging |
| Security definer | `true` | `true` |
| Trusted search path | Empty | Empty |
| Execute ACL | `postgres`, `service_role`, `authenticated` | Unchanged |

The installed production `finalize-document-upload` Function, version 2,
already matches the tracked source SHA-256
`fdb6b54c68a8a70b40c68e34ba7c49926da75d2a2d59147395b7c10569f15ce2`.
Its existing RPC receipt contract includes `document_id`, `document_version_id`
and `revision_number`. No Edge Function redeployment was needed.

## Live browser witness and its limits

An authenticated Admin opened production Overview and a fresh New Project
flow at 1280×720 CSS pixels, DPR 2. The universal sidebar/top bar remained
present. All eight setup fields were empty; no Take over action appeared.
Back from the empty setup returned cleanly without a save/discard dialog.
No remote project command was issued during this witness.

The production project register and an existing project view also loaded.
The six workspace sections remain present: Overview, BOQ, Material Requests,
Accounts, Documents and Material Movement. No console errors were observed in
this browser smoke check. This confirms readable navigation, not a business
transaction or an all-persona acceptance run.

Retained evidence contains only the blank setup:

- [Screenshot](evidence/combined-production-20261006/production-fresh-setup.png)
- [Accessibility state](evidence/combined-production-20261006/production-fresh-setup.ax.txt)

Overview financial data and screenshots are not retained in this evidence
package. Existing user drafts were not resumed in production, and no live
create/update/submit or other business mutation is claimed. Desktop/mobile
creation and Resume behavior retain their earlier automated/staging evidence;
this production witness does not substitute for those tests or physical-device
acceptance.

## Rollback and follow-up

The previous production deployment is `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`,
[immutable previous artifact](https://yorks-r35-5ih3bpqik-sajid-alis-projects-0ec775a2.vercel.app).
Its `main.dart.js` SHA-256 is
`739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.
Application rollback can promote that artifact while retaining the conservative
building-retirement guard. Do not remove the guard merely to roll back the web
client; any function reversal requires a reviewed forward migration and accepted
dependency reconciliation.

For tomorrow's PostHog investigation, select
`release_id=bb4432558ea6bdef0da958d6af4d50dd761d3d0e`,
`environment=production`, `schema_version=2`, `platform=web` and
`build_mode=release`. Analytics is enabled with debug disabled. Compare
`material_request_load` and `procurement_workspace_load` failures, P95 and
calls per detail entry, together with `protected read coordinated` outcomes
and triggers. Android Chrome/PWA belongs to the web cohort; the ephemeral APK
does not establish a native production cohort. Keep request/project/user and
business content out of the investigation output.

Physical Android Wi-Fi/mobile-data transition acceptance and one operational
day of post-release observation remain **not performed**. The owner's production
directive authorizes this publication followed by investigation; it does not
convert those remaining observations into passed gates.

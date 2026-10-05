# Universal Yorks workspace and explicit local draft save — 4 October 2026

Status: implementation and local gates passed; staging refreshed and verified.

## Product-owner correction

The supplied new form designs belong inside the existing universal Yorks top
bar and persistent office sidebar. The previous release retained feature-owned
global chrome and connected its drawer/search to the workspace; that did not
satisfy the requested integration.

The create/edit route now renders the ordinary `YorksV1WorkspaceShell`.
Project setup supplies only content: heading, local save state, stages, forms,
review and action footer. The original shared header/sidebar, capability-filtered
destinations, keyboard search, account controls, sync state and navigation history
remain visible. Only draft-aware Back handling is delegated to the feature via
`featureOwnsBackNavigation`; there is one workspace zoom host. Layout decisions
use the content width remaining after the universal sidebar.

## Reported Save draft behavior

The previous manual button had no acknowledgement feedback beyond the same
already-autosaved status. Leaving still displayed the saved-draft dialog after a
manual save. Explicit Save draft now waits for durable local acknowledgement,
reports the result and permits leaving unchanged input without another warning.
Subsequent semantic edits restore the guard; navigation/disclosure state does
not invalidate the acknowledgement. Selection/composition-only date notifications
also preserve the confirmation; unfinished newly typed dates remain recoverable
and restore the exit guard. Local persistence failures retain input and report
failure instead of claiming a save. The confirmation toast belongs to the feature
Scaffold and leaves the stage rail and footer available.

A stable keyed route viewport preserves the actual editor State, controllers,
selection and pending input across sidebar/layout changes. Transient 1×1 browser
views defer impossible chrome without remounting the editor. Initial ownership
claim failures can retry with the existing fence. If storage recovery discovers
a newer/different/retired draft or another owner, it preserves both the original
slot and the current proposal in a unique quarantine record; it does not take
ownership or overwrite retained data. Delayed native acknowledgements also
capture newer proposal revisions before publishing a read-only refusal. Failed
quarantine acknowledgement retains the latest visible input and blocks unsafe
exit.

There is no new server command, SQL, RLS, role/capability or cloud draft behavior.
Save draft remains private to the current Auth user, backend and device.
Production remains a later release.

## Local validation

- `flutter pub get`: passed; dependency lock unchanged.
- `dart format --output=none --set-exit-if-changed` for all 14 changed Dart
  files: passed.
- `flutter analyze`: no issues.
- `flutter test`: **2,297 passed, four existing skips**.
- Focused draft reliability: **22 passed**, including retry, retained records,
  competing ownership and delayed acknowledgement/newer-input failure cases.
- Canonical workspace integration: **20 passed**, including permissions loading
  and denial, real Projects → Create entry/reentry, shared search/Back/Forward,
  Save → immediate exit and 1536 → 360 → 1×1 → desktop state preservation.
- Desktop/mobile interactions: **41 passed** without golden updates. Twenty-four
  affected goldens were intentionally refreshed for content-only presentation;
  no unrelated golden was updated.
- CI web with `YORKS_V1_PROJECT_SETUP=true`: passed, including startup budget:
  main JavaScript 10,004,347 bytes / verifier gzip 2,881,058.
- CI APK with `YORKS_CI_EPHEMERAL_SIGNING=true`: passed. APK signature v2 verified;
  certificate `CN=Yorks CI Ephemeral, OU=CI Only, O=Yorks, C=AE`. This is a CI
  validation artifact, not a production-signed Android release.
- `git diff --check` and all local links in changed reports: passed.

[Browser captures and scope](visual-evidence/universal-workspace-2026-10-04/README.md)
cover all five stages and confirmed-result presentation on desktop and 360px,
manual Save/exit/reentry, building-edit guarding and Arabic at 200% text using
a synthetic local fixture. Separate authenticated staging captures verify the
existing-project local edit draft and shared navigation. The previous
post-accessibility breakpoint-resize Flutter engine semantics-map error remains
an open browser accessibility gate. Fresh phone/RTL sessions were error-free;
state/input/save decisions remained operational through the resize reproduction.
The SDK and accessibility remain unchanged.

There are no database changes. Database reset/RLS deployment, authenticated
live Create/Update/upload, real-device Android acceptance, production signing
and hosted-CI acceptance are not claimed. Historical evidence is retained in
earlier reports rather than relabelled as a pass for this change.

## Staging release

- Source: pushed commit `cf15c70c8bf129db72a69809048f0eddfc3ed8f8` on
  `codex/project-creation-ux`; local HEAD and remote ref matched before building.
  Subsequent documentation commits do not change the deployed source.
- The full `lib/main.dart` application was rebuilt from that clean source with
  `YORKS_V1_PROJECT_SETUP=true`, the staging configuration and PostHog disabled.
  No fixture entrypoint or CI backend appeared in the release artifact.
- Backend: staging `iqltcyimlqtcwyzlemwx`; production backend markers were absent.
  No service-role JWT or secret key was found in the compiled assets.
- Isolated upload: 59 static files / 54,032,461 bytes, without repository build
  context. Main JavaScript: 10,030,686 bytes, verifier gzip 2,888,218, SHA-256
  `67c798d097602b09fe4be7dbb0707be72db03d329651283c2c848b77938f7cba`.
- Vercel accepted a preview deployment, `dpl_G1EJYYDsSwXZNcpmTarzfLHn2V7g`,
  and reported READY. [Immutable preview](https://yorks-r35-qvah0q2wf-sajid-alis-projects-0ec775a2.vercel.app).
- Only [the staging alias](https://yorks-r35-staging.vercel.app/yorks/projects#/yorks/projects)
  was assigned. Twenty-three routes/assets and two additional create/edit deep
  routes matched the built hashes on both the immutable preview and stable alias.
  This includes deferred modules and PWA worker files. Project settings were
  unchanged.
- Production remained `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`; the read-only before/after
  checks matched its main JavaScript size of 9,678,001 and SHA-256
  `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.

### Authenticated staging browser verification

Using the already signed-in Local Admin in a separate tab, the existing
`YRA-123` project opened inside the original workspace. On Review, **Save draft**
displayed **Changes saved on this device. Not applied to the project.** Leaving
returned directly to Projects without an exit warning. Reopening Edit restored
the review stage and project values, with **No project detail changes**. The
save/exit sequence also passed in the desktop content layout at 1367×911.

The portfolio's Create Project entry resumed the user's retained confirmed
project result with its pending file re-selection notice. That retained state
was preserved. It proves integration of the completion view, not a newly issued
Create command. No final Create Project, Save changes, upload, access mutation
or production command was used for live verification. The fresh staging tab
reported no captured warning/error console logs during these checks. Temporary
viewport overrides were reset, and the user's original tab was left untouched.
Browser-resident JavaScript hashing was unavailable through the resource API;
the HTTP artifact hashes and observed UI are the verified evidence.

[Machine-readable release evidence](UNIVERSAL_WORKSPACE_AND_DRAFT_SAVE_2026-10-04.json)
records deployment identities, route results and validation boundaries. The
draft [PR #44](https://github.com/SajidAfridi/material_ledger/pull/44) remains open;
Vercel check success is not hosted Flutter CI acceptance.

Rollback is the default-off `YORKS_V1_PROJECT_SETUP` flag or the previous verified
staging deployment `dpl_6RaX6nWDp1cnXPbV2hh1xVet6ovq`. Preserve draft, journal,
quarantine and tombstone namespaces.
No database rollback or historical-data mutation is needed.

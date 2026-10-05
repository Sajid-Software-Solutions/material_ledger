# Direct project navigation and fresh Create — 4 October 2026

Status: implemented, local Flutter gates passed, staging deployed and verified.

## Later product-owner correction

The owner removed the Project created screen. This supersedes the earlier
desktop/mobile confirmed-result presentation and sticky-completion behavior.
Confirmed creation/update now opens the authorized project directly, with
Projects as the fallback when the actor cannot open that project. An uncertain
core outcome remains guarded; there is no optimistic navigation or new intent.

## Cause and correction

The old active proposal retired only after activation and every file finished.
Its `latest_operation` pointer restored a prior confirmed core whenever any
follow-up remained pending. The next Create therefore reopened that result.

A durably acknowledged core now releases its matching proposal independently
of pending follow-up. The exact journal, command keys, confirmed result,
attachment hashes/manifests and tombstone remain stored. A project-scoped
recovery locator is acknowledged before the slot is freed. New Create skips
confirmed prior-core pointer fallback while retaining the original unresolved
core guard. Historical confirmed proposals are rotated without server replay.

When reconciling an earlier original intent against a different current
proposal, only the historical project locator is added. The different proposal's
input, ID, writer epoch and envelope remain untouched. Historical recovery
cannot replace the active latest-operation pointer or use a disposed owner.

Pending activation/files are available separately in the existing project's
Edit view. Explicit actions use the original intent, file key and content hash,
with current owner, capability, membership and file-classification checks.
Opening the view does not dispatch or upload. Changed file bytes are refused;
uncertain uploads cannot be removed as though they were uncommitted selections.
Unpublished edit input remains independent of these actions.

The ordinary universal Yorks header/sidebar remain the route wrapper. Setup
supplies content only. The owner's screenshot shows the former navy feature
header, which is absent from the current routed source. Fresh HTTP assets match
the previous verified correction; an already running older tab does not replace
its JavaScript merely because the alias changes. No cache/draft wipe, Firebase
unregistration, automatic reload or global update framework was added.

## Local validation

- Dependency resolution passed; lockfile unchanged.
- Formatting gate: 14 changed Dart files, zero remaining changes.
- Full analyzer: no issues.
- Full Flutter suite after the live ownership correction: **2,330 passed,
  four retained skips**.
- Flow/workspace/desktop/mobile regression and interaction coverage: **128
  cases** in the complete passing gate; the focused flow/workspace rerun passed
  86 before the final Retry race case was added.
- Draft/recovery suite now includes **56 cases** in the complete passing gate.
- Project-linked recovery widget: **12 passed**, including original keys/hash,
  denied/stale permissions, owner switch, classification redaction, independent
  edit input and 360px RTL at 200% text with 44px actions.
- Exactly three Review hint goldens were deliberately updated and visually
  checked: desktop and mobile top/bottom. No other baseline changed.
- Candidate CI web passed after the live ownership correction: main 10,011,592
  bytes, verifier gzip 2,882,734.
- CI release APK passed; Android v2 signature verified with the ephemeral
  `Yorks CI Ephemeral` certificate. This is a CI artifact, not a production
  signing lane or an Android release.

There are no SQL, RLS, server-role, server-command or production data changes.
No database reset/deployment or fresh live Create/Update/upload acceptance is
inferred from the local gates. The prior accessibility-enabled breakpoint resize
semantics issue remains an open gate; this change does not alter Flutter/semantics.

## Staging delivery

The first preview from `45367b48` exposed an additional installed-browser edge
during the live check. Its confirmed create envelope was schema 2 with an exact
journal, retained writer and epoch 1; the fresh page was another writer. The
automatic history-release branch hid the normal ownership takeover control,
then its fenced retirement failed. The generic catch incorrectly described that
failure as an undecodable record. The ownership guard is corrected before final
acceptance: loading waits for the claim, another owner keeps the explicit
localized Take over draft action, and only a writable owner releases history.
No automatic ownership theft or command replay is introduced.
The added desktop and 360px regressions cover delayed ownership initialization,
explicit takeover, a still-live former writer, exact private manifest/journal
retention and zero remote commands. A local retirement write failure followed
by another writer before Retry exposes takeover instead of acquiring ownership.

Clean pushed source: `2546f9207138eee1ee6d77581e8f049f60cb4cd5`.
The complete `lib/main.dart` application was rebuilt with the staging backend,
setup enabled and PostHog disabled. An isolated 59-file / 54,039,834-byte artifact
was inspected before upload. Staging backend markers: 2; production, CI and
visual-fixture markers: 0. No private credential value or service-role JWT was
found in the artifact.

- [Stable staging](https://yorks-r35-staging.vercel.app/yorks/projects#/yorks/projects)
- [Immutable preview](https://yorks-r35-le5zfrcjv-sajid-alis-projects-0ec775a2.vercel.app)
- READY preview deployment: `dpl_48uDaRkz5M3WBzmQn4BYUQEFMiYJ`.
- Staging main: 10,037,931 bytes; verifier gzip: 2,890,157 bytes.
- Main SHA-256: `3ed5ece7b69478d61939de13cd9507efa0a8829db3cf3f214ca306889c803f51`.
- Index SHA-256: `972a64c127b49a2567a638054c0dc3d4a1373983983ccb019a66558c65668985`.
- Preview and stable alias each passed **23 route/asset hashes plus two
  additional Create/Edit deep routes**. Only the staging alias was assigned.

The production alias still resolves to `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`.
Its 9,678,001-byte bundle retains SHA-256
`739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.
The checked build/protection settings are unchanged. No production promotion,
production mutation, backend configuration/migration or rollout-default change
occurred.

## Authenticated live verification

The existing signed-in Local Admin browser retained its valid confirmed create
record and pending `project_created.png`. In a separate verification tab,
Create exposed the correct ownership notice and explicit Take over draft.
That local action retired/indexed the original confirmed proposal and opened
Project details with all eight rendered inputs blank. Back to Projects exited
directly; another Create again opened the blank current proposal without a
Project created screen or old project summary.

Read-only inspection compared hashed recovery metadata before/after: the full
confirmed core receipt hash and full file-manifest hash are identical. The old
proposal tombstone and project locator exist, while the active proposal has a
different draft ID. Its original pending file remains discoverable in the
existing project's Edit view. The retained edit draft was not taken over or
applied. Captured takeover network requests were only three reads of notification
preferences; no Create/Update/activation/upload command was sent.

Desktop evidence is 1456×787. A fresh 360×900 CSS / DPR 1 session verified the
compact universal header, blank form, lower date/notes fields, readable controls
and sticky actions. Temporary viewport overrides were reset. The original BOQ
tab was preserved; a fresh desktop Create tab was left as a deliverable.

The fresh mobile session had no captured warnings/errors. The desktop session
captured one bundled-font fallback warning. Browser-resident JavaScript
hashing was not measured; HTTP artifact hashes and observed UI are independent
evidence. The previous accessibility-enabled breakpoint resize semantics-map
issue remains open, as do fresh live final Create/Update/upload UAT,
real-device Android, production signing and hosted Flutter CI acceptance.

[Machine-readable release evidence](DIRECT_PROJECT_NAVIGATION_2026-10-04.json)
and [native browser captures](visual-evidence/direct-navigation-2026-10-04/README.md)
record these boundaries. Later documentation commits do not change the deployed
application source above.

Rollback preserves all draft/journal/quarantine/tombstone and completed-project
recovery namespaces. The previous verified staging deployment or default-off
candidate flag restores presentation without deleting historical records.

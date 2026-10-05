# Saved project setup in Projects

Owner-reported missing saved draft, corrected and verified on staging 5 October 2026.

## Change and cause

The Projects portfolio previously displayed only server-created projects. Save
draft acknowledges a device-local setup proposal; it does not create a server
project. Projects now displays **Saved project setup / Saved on this device**
with the actual reference, name, current step, last acknowledged save time and
**Resume setup**. The card stays visible above server search/filter controls and
during server portfolio loading/error. Server records, lifecycle states and
counts remain authoritative.

Resume uses the existing guarded Create entry and restores the same proposal,
stage and unfinished editors. Discovery is a read-only repository/provider:
it does not construct the creation controller, claim ownership, mint IDs,
write/quarantine/migrate storage or issue server commands. It requires the
current authenticated owner, backend, candidate flag, exact eligible role and
trusted create-write permission. Unknown schema/corrupt records stay preserved
with generic recovery copy; inaccessible storage is reported separately.

Only the current supported local Create slot is discovered. An exact confirmed
operation is omitted; an older confirmed pointer cannot hide a newer proposal.
Uncertain original command outcomes retain their existing recovery guard. Empty
and presentation-only checkpoints do not become ghost draft cards, while
partial dates/party/building edits remain discoverable. Completed file recovery
continues in its authorized project context. No cloud or multiple-draft
catalogue is introduced.

Optional asynchronous storage hints refresh this projection after acknowledged
local commits and real browser storage events. Events carry keys only and are
scoped/coalesced; listeners are disposed. No-op writes retain their original
write/acknowledgement semantics and do not emit unchanged-key hints. This does
not change Web Locks ownership fencing or the native cross-process limitation.
Copy is available in English, Arabic, Urdu and Hindi. Original universal workspace
chrome, setup footer navigation, draft schema and rollout defaults are retained.

## Files and validation

- Projects screen and new shared presentation card/localized copy.
- New local draft summary DTO, provider and read-only repository.
- Optional refresh interface and browser/native adapters.
- New discovery units and existing workspace/browser storage regressions.
- No RPC/RLS, migration, route or server workflow changes.

`flutter pub get` passed; lockfile unchanged. Format checked 12 Dart files with
zero changes. Full `flutter analyze` reports no issues. Full Flutter suite:
**2,375 passed, four retained skips**. Workspace integration: **41 passed**;
new discovery units: **35 passed**, both included in the full suite. Real Chrome
storage suite: **six passed**, including asynchronous commit-only hints,
independent-window storage delivery, writer fencing, corruption and partial
retirement failure. No golden baselines changed. `git diff --check` passed.

Intermediate timestamp initialization and test-scrolling errors were corrected
before the final pass. A shell wrapper used zsh's reserved `status` after the
successful full test process; the final **All tests passed** summary and zero
failing cases were independently asserted. The final analyzer wrapper exited
successfully with a task-specific variable.

Candidate CI web passed: main **10,022,306 bytes**, gzip **2,885,918**. CI APK
passed with verified Android v2 signature **Yorks CI Ephemeral**; it is not a
publishable Android artifact. Commands enabled the candidate explicitly:

```bash
YORKS_V1_PROJECT_SETUP=true R35_ENVIRONMENT=ci \
SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key \
./tool/r35.sh build-web

CI=true YORKS_CI_EPHEMERAL_SIGNING=true YORKS_V1_PROJECT_SETUP=true \
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid \
SUPABASE_ANON_KEY=ci-publishable-key ./tool/r35.sh build-apk
```

## Staging delivery

Clean pushed application source: `60ddcda91a883a88e750ee253e007629dc373153`. The full `lib/main.dart`
application was rebuilt after clean/dependency resolution with the ignored
staging configuration, setup enabled and PostHog disabled. The isolated upload
and inspected dry run contained **59 files / 54,050,548 bytes**.
Staging backend markers: two; production/CI/visual-fixture markers: zero.
Private credential/service-role JWT scans passed.

- [Stable staging Projects](https://yorks-r35-staging.vercel.app/yorks/projects#/yorks/projects)
- [Immutable preview](https://yorks-r35-nmhujwm0r-sajid-alis-projects-0ec775a2.vercel.app)
- READY preview: `dpl_GFVECJdEtqmhV2jHnXMgHxCQt9Da`; target preview/null.
- Main: **10,048,656 bytes**, gzip **2,893,085**.
- Main SHA-256: `01f9cea63d0e24da40f7b44009d674780a65d56e858dff3ef48eef88037b2f7a`.
- Index SHA-256: `972a64c127b49a2567a638054c0dc3d4a1373983983ccb019a66558c65668985`.
- Preview and stable alias each passed **23 route/asset hashes plus two
  additional Create/Edit routes**. Only the staging alias was reassigned.

Production remains `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`. Its
**9,678,001-byte** main bundle is byte-identical before/after,
SHA-256 `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`. Checked Vercel
build/protection settings are unchanged. No backend deployment, production
promotion, role change, data mutation or storage cleanup was performed.

## Authenticated browser evidence

Fresh **1456×787 CSS / DPR 1** and **360×900 CSS / DPR 1** sessions displayed
owner's existing **YRA-322 / test** local setup above the three server projects.
Both Resume actions opened **Review & create**, retaining dates, parties,
buildings and the file-reselection state. The existing draft was owned by
another tab, so it remained read-only; no takeover, input edit or final
Create/Update/activation/upload was invoked. Returning to Projects kept the
card and its same **2026-10-04 23:03** local save time visible. Mobile Resume
measured **300×48 CSS px**. Both captured sessions had zero warning/error logs.

- [Desktop Projects and saved setup](visual-evidence/saved-draft-2026-10-05/desktop-projects.jpg)
- [Desktop restored Review](visual-evidence/saved-draft-2026-10-05/desktop-resume.jpg)
- [Phone Projects and saved setup](visual-evidence/saved-draft-2026-10-05/mobile-projects-360.jpg)
- [Phone restored Review](visual-evidence/saved-draft-2026-10-05/mobile-resume-360.jpg)
- [Capture notes](visual-evidence/saved-draft-2026-10-05/README.md)
- [Machine evidence](SAVED_DRAFT_DISCOVERY_2026-10-05.json)

Temporary viewport overrides were reset using a blank tab; verification tabs
were closed and the user's original tab was preserved without forced reload.
Database gates were not rerun because there is no database change. The existing
accessibility-enabled breakpoint resize issue, live final server-command UAT,
real-device/production Android signing and hosted Flutter CI remain separate
open gates. PR 44 remains draft; production acceptance is not claimed.

## Rollback

Reassign staging to the previously verified
`yorks-r35-oyzv4j9lm-sajid-alis-projects-0ec775a2.vercel.app`
(`dpl_7rQK47viZZvLXztcT1srKPdNAYS2`). Source rollback reverts `60ddcda`.
There is no schema/data rollback or draft/journal cleanup.

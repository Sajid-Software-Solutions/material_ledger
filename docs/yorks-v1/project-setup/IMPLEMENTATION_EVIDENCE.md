# Project setup candidate evidence

## Desktop reference update — 4 October 2026

The later six supplied browser references supersede the earlier presentation.
The [measured comparison](DESKTOP_DESIGN_2026-10-04.md) records each original
image hash, screen geometry, actual golden and intentional policy differences.
This update implements the dedicated navy header, five-stage setup rail,
details/help split, searchable team selection, building table with independent
Apply/Cancel editor, document table, compact review and confirmed result screen.
Smaller screens retain the established readable compact flow; final mobile
design matching follows the owner's forthcoming mobile references. Enlarged
text also selects that flow, without changing operating-system text scaling.

The result screen retains known Draft/Active state and separate activation,
document and device-cleanup outcomes. Its actions require actual protected
capabilities and structural role/membership eligibility. It remains visible
until an explicit next action. Successful final file retry/removal acknowledges
cleanup and retires the active draft; a fresh form can be started in the same
session. Historical command receipts and file tombstones remain available.
Pending input is captured before teardown and saved after Riverpod listeners
detach. Failed local housekeeping stays visible as recovery work.

Document finalization now validates the exact returned document/version/revision
receipt, preserves original-key recovery after an uncertain response, and
isolates thrown analytics from dispatch and confirmed business success. Existing
server functions, RLS and quantity/Accounts contracts remain authoritative.
No new SQL, remote database write or rollout change is part of this update.

The fresh local database reset and database suite passed on Postgres
**15.19.0.002**, matching the tracked major 15: **122 files / 3,546 assertions**.
The October 3 major-17 observation below is historical and does not describe
this latest local gate.

### Final checks for this desktop update

| Gate | Result / scope |
| --- | --- |
| `flutter pub get` | Passed; tracked lockfile unchanged. |
| Changed Dart format gate | 17 files passed, zero formatting changes after formatting. |
| `flutter analyze` | Passed, no issues. |
| Full `flutter test` | **2,219 passed / four retained skips**, after final footer, web dropzone and completed-edit shortcut and fresh-edit navigation fixes. |
| Desktop interaction / layout suite | **17 passed**; six full-shell 1536×1024 snapshots. Primary action bounds include visible Buildings/Review hints; dropzone width/height is asserted. Same-container remount starts a blank new draft without manual invalidation or duplicate commands. |
| Existing setup UI suite | **45 passed**, including completed-edit Ctrl/Cmd+S leaving the new active draft blank and the historical tombstone unchanged, plus Edit again routing to a fresh proposal based on confirmed version 5 without a duplicate command. |
| Completion / document finalization suites | **10 / 15 passed**, included in the full suite; capability-negative actions, lifecycle outcomes, malformed receipts and analytics exceptions are covered. |
| Local `supabase db reset --local --yes` / `supabase test db --local` | Passed on Postgres 15.19.0.002; 122 files / 3,546 assertions. No new SQL in this update. |
| CI web, candidate flag explicitly true | Passed; `main.dart.js` 9,943,756 bytes; startup verifier gzip 2,864,579 bytes; budget passed. |
| CI APK, candidate flag true and ephemeral signing | Passed; 110,074,844 bytes; `apksigner verify --print-certs` confirmed Yorks CI Ephemeral. This is a verification artifact, not a production signing identity. |
| Source hashes, internal document links and `git diff --check` | Passed. |

Logs: `/tmp/yorks-setup-desktop-final-analyze.log`,
`/tmp/yorks-setup-desktop-final-full-tests.log`,
`/tmp/yorks-setup-desktop-final-bounds-tests.log`,
`/tmp/yorks-existing-setup-ui-completed-edit-routing.log`,
`/tmp/yorks-project-setup-db-reset-final.log`,
`/tmp/yorks-project-setup-db-tests-final.log`,
`/tmp/yorks-setup-desktop-final-build-web.log` and
`/tmp/yorks-setup-desktop-final-build-apk.log`.

Current verification artifacts were built from this validated working tree:

- Web JavaScript SHA256: `d66b8e5c56306e0e3199ce4091a3182388dd955063d860724c53c212e4e11128`.
- APK SHA256: `9d8fc820bee134f41aadd23fb37d99383b05c69c2cb10b6cea4b6e718493ce61`.

Actual routed-browser views for all six desktop states, a compact mobile review,
a tablet building editor and Arabic details at 200% text are retained in
[the browser evidence](visual-evidence/desktop-2026-10-04/README.md). The fixture
has synthetic permitted context and no configured remote backend. This does not
prove live creation/upload, production personas or cross-session server recovery.

This remains PR #44's default-off candidate. Production deployment, real
personas/uploads, user trials and production Android signing are separate
acceptance gates.

## Earlier candidate evidence — 3 October 2026

Date: 3 October 2026. Branch: `codex/project-creation-ux` in the attached project-creation-ux worktree. Initial code baseline: `7a3f1935724f1d4284fc0c662508175f50d2c028`. Current parent: `1cbfaec` (PR #43 merge); those two commits have identical tracked trees. Unrelated primary-checkout work was preserved.

This is an implemented, default-off web candidate. No production deployment, migration, data write or rollout flag change occurred. The complete [68-scenario map](CANDIDATE_ACCEPTANCE.md) distinguishes automated subcases from full release/user acceptance. The supplied 130 requirements and 68 original acceptance rows remain unchanged and their source hashes verify.

## Implemented slice

- Shared five-section create/edit form, optional fields per the supplied addendum, typed calendar dates and explicit Today, contact disclosure, safe team search and visible automatic creator role.
- Applied physical-building rows have stable identity, independent FRP/floor labels, blank versus explicit duplicate behavior, local undo/reordering, and retained scope IDs/unknown supported metadata. Existing persisted buildings cannot be removed through this candidate.
- Device/backend/user/mode/project-scoped drafts, immutable edit base/version, raw unfinished editors, visited sections and scroll/focus context. Local saved status follows actual revision acknowledgement. Meaningful route exit offers Keep working or Leave with locally saved draft after acknowledgement.
- Browser Web Locks fence writers and deliberate takeover; quota/corruption/future-version and unknown-backend legacy drafts retain recovery data. Session/owner generations fence asynchronous callbacks and lifecycle resume rechecks ownership.
- Durable exact command payload/hash/key/version before dispatch, original-intent reconciliation, confirmed receipt repair, separate core/activation/file outcomes and cleanup tombstones. Explicit unresolved retries wait persisted exponential/jitter eligibility, with at most three sends; restoration does not dispatch automatically.
- Byte-bound file identity, explicit operational classification, truthful selection/reselection/upload/finalization states, stable retry keys and conservative cancellation of never-dispatched pending files. Restricted/commercial documents stay in the authorized Documents flow.
- Real edit before/after, unchanged-edit no-op, retained protected access action and explicit three-way conflict choices. Existing trusted RPCs still decide actor, role, membership, state, versions, uniqueness and activation.
- Debounced 350ms reference advisory queries the caller's existing RLS scope with an ID-only limited projection. No match in accessible projects is not a claim of global availability; stale responses are ignored on identity/role/permission/reference changes.
- Localized input/action names, linked validation focus, manually activated step keyboard navigation, nonblocking instrumentation and finite identifier-free analytics properties. An opaque device recovery reference can be copied for authorized local diagnostics; it is not a backend support ticket or analytics identifier.

## Verification

| Gate | Result / scope |
| --- | --- |
| `flutter pub get` | Passed; tracked lockfile unchanged. |
| Changed Dart format gate | Passed. |
| `flutter analyze --no-pub` | Passed, no issues, after accessibility/reflow fixes. |
| Full `flutter test --no-pub` | 2,176 passed / four retained opt-in or fixture skips, after the final source fixes. |
| Focused setup UI | 44 passed; eight readable golden artifacts use the bundled fonts. |
| Draft/recovery/analytics/flag checks | 74 passed before the final presentation fixes; included immutable-base regression and 24 coordinator recovery cases. Eight additional advisory tests passed. |
| Real Chrome storage suite | 5 passed, including independent top-level window takeover, stale writer rejection and retirement-write failure. This is adapter evidence, not two complete compiled application tabs. |
| `npx supabase db reset --local` | Passed, explicitly local, no linked remote project. |
| `npx supabase test db --local` | 122 files / 3,546 assertions passed, including the new 13-case guard suite. Existing local container is Postgres 17.6; tracked configuration lists major 15. No production database gate is inferred. |
| CI web build, candidate flag explicitly true | Passed after final fixes: main.dart.js 9,826,712 bytes / gzip 2,831,821 bytes; startup budget passed. |
| CI release APK, candidate flag true + ephemeral signing | Passed after final fixes; 109.5 MB verification artifact signed with the non-publishable Yorks CI Ephemeral key. |
| Source hashes, local document links, shell syntax, `git diff --check` | Passed. |

Four full-suite skips are retained external PostHog ingestion opt-in and three absent R38.9 workbook fixtures. They are unrelated to this slice.

Browser inspection used the actual feature in the existing workspace shell with synthetic permitted context and no configured remote backend: all five desktop sections, 360px mobile review, Arabic details/review at 200% text, localized accessible input names, section-specific Edit labels and visible creator membership. It reproduced and corrected unnamed inputs, misleading Edit labels and a narrow enlarged-text header/footer. No live create/upload or user trial is claimed.

Readable artifacts: [desktop review](../../../test/goldens/r35/project_create_review_desktop.png), [360px attachments](../../../test/goldens/r35/project_create_attachments_mobile.png), [mobile details](../../../test/goldens/mobile_batch1/project_create_projectDetails_390.png), [Arabic 360px / 200%](../../../test/goldens/r35/project_create_details_arabic_360_200pct.png). Golden fixtures render the feature without the outer workspace shell; browser inspection covers the shell composition separately.

## Rollout, preservation and rollback

`YORKS_V1_PROJECT_SETUP` defaults false and depends on Projects. New browser routes opt in only when explicitly enabled; native routes retain the accepted legacy experience. The legacy screen/controller/provider remain available, and their regression tests run in the full suite. New flags do not expand server authority.

The additive migration `20261003160930_project_setup_preserve_building_dependencies.sql` inserts an idempotent guard into the existing trusted update function. Omitting an active persisted physical scope fails with `V1_PROJECT_BUILDING_RETIREMENT_REQUIRES_RECONCILIATION`. Add/rename/reorder retain IDs and their prior contracts. No row, BOQ, MR, document, membership or Accounts history is deleted or reallocated. Migration SHA256: `a8894a6c8ffcb91cbc8a3cfd53d5f62640dcbaf97861980c5884f92cf7c3296e`.

Application rollback disables the new flag and uses the retained screen. Preserve new local draft/journal namespaces, quarantines and retirement tombstones for recovery. Do not convert uncertain commands into new create intents. Keep the database guard during application rollback; restoring its prior function body requires a forward migration after the supported dependency resolver is accepted. No destructive down migration is provided.

Before a production rollout: reconcile the target migration ledger/body separately, run direct protected integration/persona and representative create/edit/file/conflict tests, complete the remaining manual scenarios, and validate production Android identity/signing when releasing native artifacts. An ephemeral CI key is not a publishable Android artifact.

## Practical limits

- Web Locks serialize localStorage operations; they do not make multiple journal/pointer keys crash-atomic. The active draft envelope and retirement-first ordering are guarded/tested; file bytes require reselection after restart. Do not advertise filesystem-level durability.
- Native SharedPreferences is only in-process. New critical setup dispatch fails closed there; the new UI remains web-only until an accepted cross-process adapter exists. Unsupported browser ownership primitives also fail closed.
- Current transport exposes no Retry-After header/status guidance. The candidate honors its own bounded retry policy; physical cancellation of already dispatched advisory HTTP is unavailable, so late results are detached/ignored.
- General Excel project import/building paste, cloud collaboration, multiple active drafts, exact analytics run correlation and automatic retention/clearing/export promises remain gated/deferred per D01–D10. Existing-building retirement needs an approved operational/Accounts reconciliation policy.
- Windows/NVDA/Narrator/VoiceOver, real IME/dictation/software keyboard, full 320px/tablet/landscape/high-contrast/reduced-motion matrix, production fault injection/competing sessions, representative old-data rollback, measured scale/performance and user trials remain acceptance work. Details in CANDIDATE_ACCEPTANCE are authoritative; screenshots and local tests are scoped evidence.

## Local review fixture

Run `flutter run --no-pub -d web-server --web-port=8174 --web-hostname=127.0.0.1 -t tool/project_setup_visual_fixture.dart`. Open `http://127.0.0.1:8174/?stage=0&session=review`. Sections use stage 0–4; `language=ar&scale=2` exercises Arabic enlarged text. This fixture seeds synthetic device-only inputs on startup and cannot write a live backend. It is visual evidence, not an end-to-end persistence fixture.

Full command logs are retained in the calling host's `/tmp/yorks-setup-*.log`; they contain local verification output and are not release artifacts. Git handoff identity and final build hashes follow below.

## Verified build hashes

These CI-placeholder artifacts were compiled from the validated candidate working tree before its Git commit; they are not production deployments.

- `build/web/main.dart.js`: SHA256 `e2e13add113e44ed358fdcb924c481b8e15d7a87af4beea0984111449e8a6054`.
- `build/app/outputs/flutter-apk/app-release.apk`: SHA256 `469b238481591a596bee8b9346eea91fe174e6b6a2ea9f8ff70d2a43bf335618`.
- Android certificate verification: `apksigner verify --print-certs` passed; signer is Yorks CI Ephemeral, not a production signing identity.

## Mobile follow-up — 4 October 2026

The supplied six phone references are implemented with a dedicated responsive mobile shell, full sticky action labels, tablet reflow, focused building Apply/Cancel, protected Common/team behavior, truthful file-reselection states, review and explicit confirmed result actions. Desktop baselines remain unchanged. No mobile SQL or backend contract changed. The flag remains default off and no production rollout occurred.

Final local gates: **2,251 Flutter tests passed / four retained skips**, **122 database files / 3,546 assertions passed**, clean analysis/formatting, CI web and ephemeral-signed APK builds passed. The final browser inspected all six normal states, lower controls, narrow phone, Arabic 200% and tablet review without a warning/error in the final state queries. Earlier transient startup sizing was corrected and covered by a same-mount recovery regression.

[Mobile design and exact PNG baselines](MOBILE_DESIGN_2026-10-04.md), [final mobile validation and build identities](MOBILE_VALIDATION_2026-10-04.md), and [actual browser captures](visual-evidence/mobile-2026-10-04/README.md) supersede the earlier compact presentation evidence. Historical desktop evidence and old artifact identities above remain historical. Neither measured source comparison nor local validation constitutes literal pixel equality, complete source acceptance, live production success or production signing.

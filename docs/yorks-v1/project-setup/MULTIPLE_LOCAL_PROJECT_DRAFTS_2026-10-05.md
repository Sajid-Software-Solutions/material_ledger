# Independent saved project setups

Owner-authorized correction, 5 October 2026. The verified application source
is published to staging only. Production deployment, bundle and project
settings remain unchanged. [Machine-readable release evidence](MULTIPLE_LOCAL_PROJECT_DRAFTS_2026-10-05.json)
records the final artifact and validation boundaries.

## Reported issue and confirmed cause

The owner described saving an incomplete setup A, returning to Projects and
choosing Create Project for another project. A's fields were still present.
This matched the implementation: every Create entry used the same retained
owner/backend-scoped creation controller and local record. Save draft
acknowledged that record; reopening Create restored it. There was no separate
identity or entry policy for a new proposal.

Clearing that record would have lost A's saved progress. The correction gives
each proposal its own local identity and distinguishes a fresh entry from
explicit selection of a saved proposal.

## Approved behavior

The owner's request authorizes multiple independently saved **device-local**
project setups. It supersedes the multiple-local-draft deferral in the earlier
project-setup package for this bounded slice. Cloud drafts, collaboration,
cross-device recovery, project imports, building-paste mappings and automatic
retention/cleanup remain deferred. The supplied specification and prior
acceptance/release reports remain historical evidence; their earlier
single-slot claims are not rewritten into current passes.

| Action | Current behavior |
|---|---|
| Create Project | Opens a new empty setup at Project details, with its own draft and creation-command identities. Saving A does not prefill B. |
| Save draft | Acknowledges the current setup on this device. Repeated saves update the same item. It does not create a server project. |
| Projects | Shows saved local setups separately from server rows, states, filters and counts. A bounded list can expand to make every retained entry reachable. |
| Resume setup | Opens the chosen draft ID, its stage, fields, parties, buildings, attachment metadata and unfinished editor input. |
| Refresh or return to an anchored setup URL | Selects that same proposal. A fresh entry is anchored only after its local checkpoint is acknowledged. |
| Missing, unsupported or inaccessible saved data | Presents guarded recovery or unavailable-storage copy. It does not silently fabricate an editable replacement. |
| Confirmed final Create | Retires only the matching proposal when confirmed, preserves pending operation recovery and opens the authorized project. |

Fresh entry remains `/projects/new`. Explicit selection uses
`/projects/new?draft=<draftId>`. The separate
`/projects/new?recovery=legacy` entry reaches the original guarded singleton
recovery when historical bytes or an original unresolved intent require it.
The universal Yorks workspace shell and single setup footer Back action remain
in place.

Context changes reset editor buffers, selected in-memory file bytes, undo
callbacks, validation, focus and asynchronous generations. Stage subtrees are
scoped to owner, backend, draft and stage, so the preceding draft's search or
category filters do not carry into another proposal. A denied local write
cannot authorize navigation away from recoverable unsaved input.

## Local storage and preservation

The original root key remains
`yorks_project_setup_v2_<owner/backend/create-scope hash>`. An additive
`:catalogue` index points to separate `:draft:<draftId>` envelopes. Both use
the existing local atomic-storage abstraction and the root-scoped writer lock.
Index registration precedes a new envelope write, so a sequential partial
failure exposes scoped recovery rather than an acknowledged undiscoverable
draft. Save is not reported successful unless the required writes are
acknowledged.

The original supported singleton resolves by its verified draft ID to its
unchanged original key. It is not copied, cleared or taken over as part of
discovery or fresh Create. Unknown JSON fields, unsupported schemas, existing
quarantines, saved metadata and foreign-writer fences remain preserved.
Catalogue reads create no IDs, claim no lease and perform no migration or
repair. Empty and presentation-only checkpoints are omitted from saved cards;
partial dates and unfinished party/building input remain meaningful progress.

Ordinary Create and Resume use the selected proposal's exact original journal.
They do not adopt or overwrite another proposal's historical latest-operation
pointer. Explicit legacy recovery alone follows that original pointer. A
verified unresolved original intent remains reachable even if a different
root proposal has an exact acknowledged journal. If its per-ID envelope is
missing or cannot independently resume, recovery uses the original guarded
slot and preserves all malformed/foreign bytes.

Command payloads, hashes, idempotency keys and original `:journal:<draftId>`
keys are unchanged. Confirmed project recovery retains its validated
`:completed_project:<projectId>` locator before the confirmed exact journal
is staged, and before later proposal-retirement housekeeping. This ordering
keeps known-core activation/file follow-up reachable under partial local
write failures. Retirement verifies the exact original operation and cannot
retire another saved proposal.

Web Locks continue to fence browser writers. Multi-key localStorage writes
are not advertised as crash-atomic filesystem transactions. Native storage
retains its existing cross-process ownership limitation. File bytes are held
in memory rather than durably stored in the catalogue; after restart a saved
attachment may require reselection without changing its retained identity,
hash or category.

## Security and backend boundary

Discovery and actions remain scoped to the authenticated owner, configured
backend, candidate flag, exact eligible role and trusted create-write
capability. Owner/backend/permission changes and stale asynchronous callbacks
cannot apply another context's data. Missing or foreign records do not grant
ownership. No new discard/delete/reset action is introduced.

Widgets continue through Riverpod controllers and repositories. Save draft
and discovery are local operations. Final project creation, activation and
document upload retain the existing server-authorized command paths and
confirmation rules. This slice adds no cloud draft API, SQL migration, RLS,
RPC shape, role/capability grant, backend deployment or server data migration.
Database gates are not claimed as newly run for this local change.

Key implementation boundaries:

- [Selected draft providers and legacy lease aliases](../../../lib/shared/providers/yorks_v1_project_creation_draft_provider.dart)
- [Fenced local draft controller](../../../lib/shared/controllers/yorks_v1_project_creation_draft_controller.dart)
- [Additive local catalogue](../../../lib/shared/repositories/yorks_v1_project_creation_draft_catalogue.dart)
- [Read-only saved setup projection](../../../lib/shared/repositories/yorks_v1_project_local_creation_draft_repository.dart)
- [Exact and explicit legacy recovery coordinators](../../../lib/shared/providers/yorks_v1_project_setup_coordinator_provider.dart)
- [Original journal and completed-project locators](../../../lib/shared/repositories/yorks_v1_project_setup_journal_store.dart)
- [New/Resume UI and context lifecycle](../../../lib/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart)
- [Deferred setup entry](../../../lib/features/projects/presentation/screens/yorks_v1_project_setup_entry_screen.dart)

## Verification recorded so far

Development logs under `/tmp/yorks-multiple-drafts-release` record:

- Dependency resolution succeeded; format checked **25 Dart files with zero changes** at that checkpoint.
- Full analyzer reported **no issues** at that checkpoint.
- Full Flutter suite reported **2,408 passed, four retained skips** before the final deferred-entry adjustment. The final source rerun is recorded below.
- CI web built with **10,064,153-byte** main bundle, gzip **2,898,497**, passing the existing startup budget at that checkpoint.
- CI Android built a **110.9 MB** release APK with a verified Android v2 **Yorks CI Ephemeral** signature. This is a CI artifact, not a publishable production Android artifact.

Focused regressions cover independent A/B identities and exact saved contents,
repeat-save deduplication, stable anchor/Resume writer identity, invalid IDs,
owner/backend isolation, competing writers, sequential partial catalogue and
journal failures, exact original recovery, malformed legacy/index data and
confirmed follow-up discoverability. Workspace tests cover fresh Create,
selected Resume, unfinished input, navigation acknowledgement and responsive
context changes. These tests do not replace live final server-command UAT.

### Startup budget correction

The first actual staging-shaped build failed its unchanged startup gate:
`main.dart.js` gzip **2,906,030 bytes**, above the **2,900,000-byte** limit.
This was a measured source/artifact failure; no candidate was published from
that failed build.

The setup wizard now loads through one deferred entry. The entry performs
asset loading only, keeps the loaded child at a stable position and exposes a
localized retry if loading fails. It does not create a draft or perform
ownership/server work. The subsequent staging-shaped build passed with main
**9,747,993 bytes**, gzip **2,808,127**. The budget was not raised. Final clean
artifact metrics are recorded in the release section.

## Browser evidence and limits

The local browser lane served `tool/project_setup_visual_fixture.dart` at
`http://127.0.0.1:43972` with synthetic identity and the real presentation,
workspace shell and local storage. It issued no remote project creation,
activation or document upload. Native JPEG captures show A saved, a distinct
empty B, both saved items, explicit Resume A and reload selection of A and B.
Desktop captures are **1438×809 image pixels**; the compact capture is
**403×1011 image pixels**. These image dimensions do not establish exact CSS
viewport or physical-device acceptance.

- [Saved A in the workspace](visual-evidence/multiple-drafts-2026-10-05/local-draft-a-desktop.jpg)
- [Fresh B with empty fields](visual-evidence/multiple-drafts-2026-10-05/local-new-b-empty-desktop.jpg)
- [A and B separately discoverable](visual-evidence/multiple-drafts-2026-10-05/local-two-saved-drafts-desktop.jpg)
- [Explicit Resume A](visual-evidence/multiple-drafts-2026-10-05/local-resumed-a-desktop.jpg)
- [Reloaded A](visual-evidence/multiple-drafts-2026-10-05/local-reloaded-a-desktop.jpg)
- [Reloaded B](visual-evidence/multiple-drafts-2026-10-05/local-reloaded-b-desktop.jpg)
- [Compact fresh setup](visual-evidence/multiple-drafts-2026-10-05/local-new-empty-phone.jpg)

These native captures are retained at the linked repository paths. The seeded
A fixture recreates its sample on reload, so that capture alone does not prove
unmodified persistence. B was entered independently and retained its own
reference/name after a real reload; the existing writer fence correctly kept
that refreshed view read-only. No takeover was performed. The phone capture
measured 359×900 CSS pixels with the site zoom retained; exact 360px and Arabic
responsive assertions are covered by the widget lane. Physical-device UAT is
not inferred from these captures.

## Final staging release

[Staging](https://yorks-r35-staging.vercel.app) now points to the READY
[immutable preview](https://yorks-r35-5pf4pvzsf-sajid-alis-projects-0ec775a2.vercel.app),
`dpl_96XXECXaD8CQqv7TzFvUdUs1Df4d`. The application commit was built from
unchanged application paths; subsequent documentation commits record this
evidence and do not change the deployed runtime.

| Final evidence | Status |
|---|---|
| Final application commit and remote identity | `5c9fa63be89b5448a768b3aac1ae3bd4f5db8b82`, pushed; local HEAD and remote ref matched. |
| Final format, analyzer, full Flutter and applicable browser tests | Four deferred-entry Dart files formatted with zero changes; analyzer clean; 2,410 passed / four retained skips. Final workspace 48 passed; earlier foundation/flow regression lane 233 passed and actual Chrome storage adapter lane seven passed. No golden images changed. |
| Final clean CI/staging web metrics and artifact hashes | CI main 9,721,662 bytes / gzip 2,799,982; final clean staging main 9,747,998 / gzip 2,808,129. Main SHA-256 `65b6e30f60989c64196e2cb9cd89014ed8919f281a995380f2689953a1224628`; existing 2,900,000-byte gzip ceiling passed. |
| Final Android CI signature/source relationship | Final runtime source built a 110.9 MB CI APK; verified Android v2 Yorks CI Ephemeral signature. This is not a production-signed publishable artifact. |
| Isolated upload contents and backend/credential marker scans | 60 files / 54,153,286 bytes; dry run matched. Staging markers present; production, CI placeholders, fixture entry, service-role/private-credential markers absent. Actual `lib/main.dart` entrypoint. |
| READY immutable staging deployment and stable-alias reassignment | READY preview above; stable staging alias verified against the same deployment ID and source metadata. No production promotion. |
| Published route/asset hashes and authenticated browser A/B checks | 24 routes/assets including all seven deferred parts plus two Create/Edit deep routes byte-matched on both preview and stable staging. Authenticated live browser opened two distinct new proposals, each with all eight DOM fields empty; Back returned to Projects without an empty draft card or exit dialog. |
| Production before/after identity and artifact preservation | Deployment `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy` unchanged; main 9,678,001 bytes and SHA-256 `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f` byte-identical. Project build/install/output/protection settings unchanged. |
| Native evidence copy and internal-link check | Native synthetic and published staging captures/accessibility records retained; internal links verified before commit. |

### Published browser boundary

The live browser used a 1280×720 CSS viewport at DPR 2. The original Projects
tab and the fresh staging tab showed no saved local cards at inspection time;
therefore original-user draft resume/preservation is not claimed as a live
assertion. Independent A/B saving, selected Resume and B reload are established
by the synthetic local browser and controlled storage/workspace regressions.
The original user tab was not reloaded, no saved draft was taken over, and no
project Create/activation/upload command was issued for verification. The
published browser capture reported no console errors in the inspected session.

- [Published empty Create Project](visual-evidence/multiple-drafts-2026-10-05/staging-new-empty-desktop.jpg)
- [Published browser acceptance](visual-evidence/multiple-drafts-2026-10-05/staging-browser-acceptance.json)

Production publication, final live Create/activation/upload UAT,
production-signed Android delivery and hosted Flutter CI remain separate
evidence/authorization boundaries.

## Rollback

The immediately preceding stable staging artifact is
`dpl_8ZUjQirCCg8EDBrNA9X1fZzjrrXW`,
[previous READY preview](https://yorks-r35-iijoaabzn-sajid-alis-projects-0ec775a2.vercel.app),
verified by the captured staging-before alias and
[preceding control-polish release report](SETUP_CONTROL_POLISH_2026-10-05.md).
Rollback reassigns only the
staging alias to that verified artifact. No backend rollback is required.

Preserve the original root, catalogue, per-ID records, quarantines, exact
journals and completed-project locators. Do not clear browser storage or
rewrite a new per-ID draft into the singleton for an older build. The older
artifact does not discover the new catalogue; those bytes must remain for a
forward release. Rollback may temporarily hide newer saved items from its UI,
and does not imply that their saved progress was deleted.

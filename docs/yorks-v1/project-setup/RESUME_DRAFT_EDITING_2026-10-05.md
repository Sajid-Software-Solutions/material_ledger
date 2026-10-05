# Resume saved project setup directly

Owner-authorized correction, 5 October 2026; verified on 6 October 2026.

## Report and cause

The owner selected Resume setup from a saved local proposal and received a read-only form with a Take over draft action. The controller retained a writer identity in the durable envelope. Initial restoration would refuse a different writer even when that identity came from a previous browser session. Providers also outlive a route, so a retained controller could remain fenced after leaving and selecting the same draft again.

The owner now explicitly authorizes Resume setup to open the selected draft ready to edit. This supersedes the separate takeover interaction in PRJ-DRF-009 and the Another local tab row of the interaction addendum. Resume itself is the deliberate ownership-transfer action. PRJ-DRF-010 fencing remains required, and multiple independent local proposals remain supported.

## Behavior and preservation

Resume acquires the exact selected owner/backend proposal once for that screen entry. The latest saved record is read under the existing local atomic lock before the form is hydrated or enabled. Ordinary rebuilds, URL anchoring and returning browser focus do not acquire a competing writer again. The Take over draft action is removed.

The previous writer still has an obsolete epoch. Its late save or command-journal write must fail without replacing the newly resumed record. Ordinary browser focus does not reclaim it. A stale view has actual read-only text fields and disabled mutation controls, including keyboard-driven date, checkbox and dropdown actions. Rejected debounce/manual saves retain any pending frontend input in that open view without adopting a new epoch. Guarded navigation cannot silently discard that unacknowledged buffer. Fresh Create continues to allocate an independent empty proposal.

Manual Save compares the acknowledged stored input with both its original snapshot and the current editor input. Focus or scroll checkpoints no longer produce an incorrect input-changed warning. Actual typing during a save still requires another save.

Unsupported, missing, foreign or retired envelopes remain guarded. Uncertain operation journals continue to freeze the original command intent. Acquiring a local editing lease does not confirm, replay or authorize a remote command. Saved fields, raw editor values, attachment metadata, unknown fields, stable identities and original command journals remain preserved. No SQL, RLS, role, backend deployment or data migration is introduced.

## Verification

The final source passed dependency resolution, formatting with zero changes, a clean full analyzer, **2,423 Flutter tests** with four retained skips, **168 focused setup tests**, and **seven actual Chrome storage tests**. No golden images changed. The full suite initially exposed the focused native-field read-only issue; the final rerun passes after correcting it. No unrelated failures remain.

The CI web build passed its unchanged startup budget. The Android CI build passed and its Yorks CI Ephemeral v2 signature was verified; this is not a production-signed publishable artifact. Exact sizes and hashes are recorded in [machine-readable evidence](RESUME_DRAFT_EDITING_2026-10-05.json).

The native browser lane served the real setup presentation, universal workspace shell and local storage through the synthetic fixture at port 43974. On the final source, desktop and compact phone checks typed into a resumed draft, saved it, returned to Projects without another save prompt, then selected Resume once and received the same saved value in an immediately editable field. No Take over action was present. No remote project creation, activation or document upload was issued.

- [Desktop Save acknowledgment](visual-evidence/resume-editing-2026-10-06/desktop-save-acknowledged.png)
- [Saved draft card](visual-evidence/resume-editing-2026-10-06/desktop-saved-card.png)
- [Desktop one-click Resume](visual-evidence/resume-editing-2026-10-06/desktop-return-resume-ready.png)
- [Phone Save acknowledgment](visual-evidence/resume-editing-2026-10-06/mobile-resume-save.png)
- [Phone one-click Resume](visual-evidence/resume-editing-2026-10-06/mobile-return-resume-ready.png)

Native captures retain the browser's existing zoom: desktop measured 1726×1150 CSS pixels and the compact view 359×899, both at DPR approximately 0.89. Exact 1536×1024 and 360×800 assertions are covered by the widget lane. The fixture recreates seeded data on reload; these captures establish same-session Save/return/Resume, not independent reload persistence or physical-device UAT. Existing independent persistence tests remain in the full and Chrome lanes.

## Staging release and boundaries

[Staging](https://yorks-r35-staging.vercel.app) points to the READY [immutable preview](https://yorks-r35-11nytgxp6-sajid-alis-projects-0ec775a2.vercel.app), `dpl_6TnKtqpocMPNjh4KvUB9oxrrFXuG`. Application source `c7605713945c7cf575822363a427527d0ec60bf8` was committed and pushed, and the remote branch matched that source before upload. Later documentation commits only record evidence.

The isolated `lib/main.dart` staging artifact contains 60 files / 54,162,200 bytes. The CLI dry run matched those exact contents. Its main bundle is 9,748,464 bytes / 2,807,976 gzip bytes, SHA-256 `e86f0846d250e4a494932b0d4e6ce97ea3571aded7046fab1653a5c84023e12a`. The existing 2,900,000-byte gzip ceiling passed. Staging markers are present; production, CI placeholders, fixture, private-key and service-role markers are absent. All 24 base routes/assets, including seven deferred parts, plus two Create/Edit deep routes byte-matched on both preview and stable staging.

The authenticated published browser opened a fresh empty setup inside the universal shell, with editable controls, and returned to Projects without a dialog or saved empty card. [Published integration capture](visual-evidence/resume-editing-2026-10-06/staging-integrated-setup.png) records that 1280×720 CSS view at DPR 2. This browser profile contained no saved local proposal cards, so the real saved-user Resume journey is established by the synthetic native, exact widget and Chrome adapter lanes; it is not claimed as a saved-user staging journey. The original user tab was not reloaded, and no remote mutation was issued.

Production deployment `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy` remained unchanged. Its main bundle is 9,678,001 bytes with SHA-256 `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f` and is byte-identical before/after. Project build, install, output, ignore-build and protection settings are unchanged. No database, RLS, RPC, role or backend function was deployed; database/server and physical-device acceptance were not newly run for this local-only slice.

## Rollback

Restore the previous verified staging deployment `dpl_96XXECXaD8CQqv7TzFvUdUs1Df4d`. Keep all local draft/catalogue/journal bytes. Reverting the client restores the previous extra takeover interaction; it must not remove independently saved proposals or operation history. Production is outside this release.

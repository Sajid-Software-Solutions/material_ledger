# Accounts Task 01 — engineering review evidence (2026-09-28)

Scope: the existing R39 building-stage progress journey. This supersedes the
partial checkpoint in `ACCOUNTS_TASK01_CHECKPOINT_2026-09-28.md`; it is **not**
production approval. Work was performed in the isolated
`accounts-evidence-review/material_ledger` checkout based on
`047b37b8ab5781d1f4a3db9429da1d550366709d`. No production, staging or
live YRA-322 records were changed.

## Implemented

- A project-scoped, server-bounded evidence search returns only current,
  finalized operational documents for which every active link is readable.
  Selected IDs are separately resolved so inaccessible prior evidence can be
  shown as unavailable without disclosing its title. Search returns at most 20
  matches; existing selections are separately bounded at 256 to avoid silently
  dropping historical links. No financial values are returned.
- Progress document validation now applies the same all-links access predicate
  and excludes archived Accounts documents. This changes only the eligibility
  of future commands; it does not alter or delete stored progress, links or
  documents.
- The raw UUID field was replaced with searchable names/references, current
  revision number, selected list and authorized PDF/image preview. Before a
  command, the picker rechecks current access and revision; a changed revision
  requires explicit reselection. Progress commands still store document IDs,
  **not pinned version IDs**. The UI says so instead of claiming immutable
  version retention. Pinning remains a separate reviewed contract change.
- The form shows project, building, stage, confirmed percentage, proposed
  action/percentage, selected evidence count and reason. Suggestions explicitly
  do not confirm progress or claimable value. Increased confirmations require
  a document; suggestions retain the original summary-or-reference rule.
- Single-flight UI and controller guards prevent duplicate intent. An unknown
  outcome retains the exact same-session intent and key for reconciliation.
  A confirmed write whose projection refresh fails cannot be submitted again
  from that sheet; it offers refresh instead. Success messaging follows a
  successful authoritative refresh. Active workbench filters are retained.
- Matching no-value Accounts projections preserve an engineer's permitted
  progress actions; a mismatched value downgrade still purges the combined
  command surface. Conflict preserves the entered proposal, displays the
  current record version and requires a conscious retry.

## Verification performed

- `flutter pub get`, changed-Dart `dart format --output=none
  --set-exit-if-changed`, `flutter analyze --no-pub`, `git diff --check`:
  passed.
- Focused controller/workbench/evidence widget tests: **32 passed**. Tests exercise
  phone 390×844 with 300px keyboard inset, desktop 1366×768, authorized
  selection, newly inaccessible evidence, changed revision, action-only/no-
  value state, active filter refresh, same-key recovery and concurrent clicks.
- Local PostgreSQL transaction: the new migration and the T02 pgTAP suite
  produced `1..73`, all `ok`. The transaction rolled back, leaving the shared
  local DB unchanged. Positive and negative cases cover Site, Project Engineer,
  Admin, Accountant and Procurement; project substitution, commercial evidence,
  an unfinalized document, archived evidence, a cross-linked unreadable
  document, bound enforcement, unchanged monetary
  response shape, idempotency, competing version and the T03/T04 no-write gate.
- Reviewed actual Flutter-rendered component captures (not a live route or
  physical-device session):
  [desktop](../../test/goldens/accounts_progress_evidence_desktop.png),
  [390×844 selection](../../test/goldens/accounts_progress_evidence_phone.png),
  [390×844 inaccessible-evidence recovery](../../test/goldens/accounts_progress_evidence_error_phone.png),
  [360px Arabic RTL with keyboard inset](../../test/goldens/accounts_progress_evidence_rtl_phone.png).
- Complete `flutter test --no-pub --reporter expanded`: **1,707 passed,
  273 failed, 4 skipped**. The earlier pre-change run had 1,691 passed,
  273 failed, 4 skipped. One unrelated project golden was reproduced in an
  untouched base archive. No baseline golden was overwritten. The remaining
  272 failures were not individually reproduced on base.
- R35 CI web build passed, including the startup budget. The R35 Android
  `assembleRelease` APK build passed with CI ephemeral signing (108.2 MB).
  This is a compilation gate, **not** a production-signed artifact.

## Acceptance boundary and remaining work

T01-01–03, 05–09, 10–14 and 16 have relevant component/controller/database
evidence, but not every end-to-end persona observation. T01-04 is proven for
unfinalized, archived, revoked and changed current evidence; this contract has
no general document-expiry policy. T01-09 preserves proposal and exposes the
current version in a widget conflict test, but a two-actor browser UAT is
outstanding. T01-14 has a 360px Arabic RTL/keyboard-inset render but still
needs a physical keyboard walkthrough. T01-15
requires an observed reviewer task; this work does not claim notification
delivery. A real signed-in route capture and engineer acceptance remain open.

Unknown-command recovery is same-session only. The key store persists the
fingerprint, not the full typed payload; after a process restart the exact
intent cannot be automatically reconstructed. No sensitive persistent cache
was added. Historic document-version pinning was not implemented because the
approved progress RPC stores document IDs. No live invoice/baseline, weighted
item billing, role defaults, unrelated module, deployment or production data
was changed.

## Data preservation and rollback

The SQL migration creates a read RPC and tightens a validator; it has no table
rewrite or destructive DML. Before deployment, reverting this isolated branch
removes the change. If deployed later, rollback needs a new migration restoring
the prior validator body and retiring the search RPC after clients no longer
call it. Existing progress evidence IDs and document versions remain intact.
Do not remove the hardening without a reviewed security decision.

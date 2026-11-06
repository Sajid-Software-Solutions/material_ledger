# Accounts Task 01 — partial checkpoint, not release acceptance

Base: `047b37b8ab5781d1f4a3db9429da1d550366709d` (remote main at inspection).
Isolated checkout: `accounts-evidence-review/material_ledger`. Existing dirty
workspaces were not changed. No production/staging deployment, database change,
role change, invoice import or live project mutation was performed.

## Implemented slice

- Accounts project commands reject concurrent entry before asynchronous key
  acquisition. Duplicate clicks cannot race two key leases in this controller.
- An uncertain command retains its exact typed invocation. Different input cannot
  replace that pending intent. Explicit reconciliation reuses the original key.
- Projection refresh does not imply that an uncertain command has succeeded.
- The progress sheet offers **Check original save** instead of an editable form
  while an outcome remains unresolved, including after closing/reopening it in
  the same provider session. Authority denial clears input and hides the opening
  snapshot. A recreated authority provider invalidates the open editor.
- The sheet accounts for keyboard height; suggestion guidance distinguishes it
  from confirmation. Evidence rejection has specific recovery guidance.
- New copy is centralized in English, Arabic, Urdu and Hindi.

The retained typed intent is in memory, not a new persistent business-data cache.
Existing persistent key fingerprints are preserved. **Restart recovery is not
completed:** after process/provider disposal, the original payload cannot be
reconstructed from the existing fingerprint-only key store. Do not claim T01-08
is fully accepted across restarts or authority changes.

## Evidence API findings — not implemented

The existing project document workspace is permission-filtered but unbounded.
The Accounts document endpoint supports search but is also unbounded and covers
Accounts metadata documents, not the complete operational evidence catalogue.
Neither is a compliant bounded evidence picker API as-is.

Progress commands currently accept document IDs, not pinned version IDs. The
T02 validator checks operational classification, a current version and a live
project link. It does not call the all-links `v1_document_readable` predicate.
The implications for a document with other inaccessible entity links need a
negative server test before asserting that arbitrary reference substitution is
safe. This is a source finding, not a demonstrated production exploit.

The raw document-ID field remains unchanged. No broad client-side document
download/filter, invented upload completion or fake immutable-version label was
introduced. The next evidence slice needs a bounded authorized search/read
contract, currentness semantics, protected preview and negative database tests.

## Verification

Before edits:

- `flutter test test/yorks_r39_accounts_billing_workbench_test.dart`: 2 passed.
  Dependency resolution completed successfully; no lockfile change.
- Current source explicitly tested that a changed payload replaced an uncertain
  key. That behavior was replaced by a regression test requiring rejection.

After edits:

- T02 controller, T03 controller, T04 controller and billing workbench focused
  run: 27 passed.
- Final T02 run: 14 passed, including recovery-button interaction at 390×844 and
  1366×768 with a simulated 300px keyboard inset; same-key retry, concurrent
  clicks, refresh and revocation checks.
- `flutter analyze --no-pub`: no issues.
- Changed-file format check and `git diff --check`: passed.
- Complete `flutter test --no-pub --reporter expanded`: **1,691 passed,
  273 failed, 4 skipped**. Log: `/tmp/yorks-accounts-evidence-review-tests.log`.
- One unrelated failure was reproduced from a separate untouched archive of the
  base commit: `test/yorks_mobile_project_batch2_test.dart`, exact test name
  `mobile Batch 2 project review 390x844`. Its golden pixel comparison fails
  without this patch. Log: `/tmp/yorks-task01-baseline-test.log`.

No golden was updated. Under the repository stop condition for unrelated test
failures, further implementation stopped at this checkpoint. The other 272
failures were not individually baseline-reproduced.

## Acceptance boundary

T01-07 and same-session portions of T01-08 have controller/widget evidence.
T01-10 has existing provider-purge and new pending-intent-purge evidence.
T01-12 has recovery-sheet reachability evidence only, not the complete entry
journey. Existing T03/T04 controller tests pass, but this is not complete T01-16
database regression proof.

Still not completed: readable evidence selection/preview (T01-02–04), full
suggestion persistence and reviewer observation (T01-05/15), confirmation-evidence
UI validation, current-version conflict recovery, complete retained-context proof,
action-only network-response checks, actual-build desktop/phone/failure screenshots,
physical keyboard/RTL verification and a witnessed engineer task. No live browser
or mobile-device acceptance is claimed from widget tests.

Web/APK release builds, database reset/pgTAP, staging personas and production
verification were not run. The existing shared local database was not reset.
This checkpoint is neither complete Task 01 nor production-approved.

Rollback: revert this isolated application/test/document patch. There is no
migration or business-data rollback, and no change to server financial semantics.

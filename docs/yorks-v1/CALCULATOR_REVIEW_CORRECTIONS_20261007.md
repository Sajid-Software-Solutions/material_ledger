# Calculator audit corrections — 7 October 2026

Status: **implemented and verified on staging; production unchanged**.
The owner's Astra audit gate remains in force. These changes extend the same
calculator interaction candidate in [draft PR #51](https://github.com/SajidAfridi/material_ledger/pull/51).
Machine evidence is in [CALCULATOR_REVIEW_CORRECTIONS_20261007.json](CALCULATOR_REVIEW_CORRECTIONS_20261007.json).

## Findings and corrections

### Rejected access changes display the confirmed grant

The finding reproduced against the preceding source: an Edit → View management
request returned a version conflict, the record retained its confirmed `edit`
grant and revision, but the dropdown still displayed **Can view**. Its text and
selection were internal widget state; rebuilding with the unchanged confirmed
value did not reset them.

The sharing dialog now recreates each grant picker, keyed by recipient identity
and completed request generation, after either success or failure. The current
server-confirmed record supplies its permission. Pending controls stay disabled;
errors remain visible and only confirmed changes show **Access updated**.
Successful retries use the existing controller, expected revision and command
idempotency behavior. No local permission is substituted for server authority.

Four widget cases cover rejected upgrades and downgrades at 1366px and 360px,
unchanged grants/revisions on rejection, pending controls and successful retries.
These tests simulate rejected management RPCs; live sharing permissions were
not changed to provoke a failure.

### Delete and Clear have independent Undo steps

The finding reproduced against the preceding source: two consecutive deletions
followed by Clear coalesced into the same 650ms group, and one Undo restored all
three original rows rather than only the cleared final row.

Managed ESP Delete/Clear now flush pending edits and start an atomic history
boundary before modifying rows, then record the resulting snapshot immediately.
Each command has its own Undo/Redo step. Add/Duplicate use the same boundary
helper; same-field typing retains its existing 650ms grouping. Read-only and
no-op deletion/clear actions do not create history steps. The retained unmanaged
editor still preserves its one-row deletion rule and reset behavior.

The widget regression checks all three Undo and Redo states, stable row IDs and
unknown imported fields. Live staging also verified Clear → Undo (3 → 0 → 3),
two consecutive deletions followed by separate Undo steps (3 → 2 → 1 → 2 → 3),
and Redo back to one row. Add row and Mac Add/Redo shortcuts worked. The review
calculation was unsaved and discarded through the shared top-bar Back guard;
no calculation or grant was saved by this browser check.

## Affected boundary

- `yorks_calculator_workspace.dart`: confirmed sharing-picker state and atomic
  editor history ownership.
- `yorks_v1_engineering_calculator_screens.dart`: the managed-session boundary
  callback, guarded Delete/Clear and their completed local action notification.
- `yorks_calculator_workspace_test.dart`: rejected management fixture and five
  regression cases. Desktop/360px rejection captures are additional goldens.

No repository, RPC/RLS, migration, role policy, formula, file format, telemetry
catalogue or production configuration changes belong to this correction.
The earlier Accountant-discovery and archived-project server guard remain in
this candidate, with their acceptance documented in
[CALCULATOR_ACCESS_HARDENING_20261007.md](CALCULATOR_ACCESS_HARDENING_20261007.md).

## Verification

| Gate | Result |
|---|---|
| Dependencies and formatting | Passed; changed Dart files already formatted |
| Analyzer | No issues |
| Complete Flutter suite | 2,503 passed; four retained skips |
| New regression cases | Five passed; both findings fail against the preceding source |
| Clean local database | Reset passed; 124 files / 3,625 assertions passed |
| CI web | Passed; 9,868,702-byte main / 2,843,363-byte budget gzip |
| CI APK | Passed; 111.8 MB with ephemeral CI signing, not a store artifact |
| Staging web | Passed; explicit Calculator/Project Setup flags and staging backend |
| Deployment checks | 26 immutable + 26 public staging routes/assets byte-matched |
| Browser | Existing Local Admin; refreshed route, unsaved ESP history and clean console |

Desktop and 360px rejection visuals:
[1366px](../../test/goldens/calculators/access_rejected_1366.png),
[360px](../../test/goldens/calculators/access_rejected_360.png).
The [live staging Undo capture](evidence/calculator-review-corrections-20261007/staging-undo.jpg)
shows two rows after the first Undo of two consecutive deletions.

## Published staging identity and rollback

- Application source: `00acb394fcb81a7621dd05033749c86e9db281d5` (clean source stamp).
- [Public staging](https://yorks-r35-staging.vercel.app/#/tools/calculators).
- [Immutable candidate](https://yorks-r35-koeb4s5mn-sajid-alis-projects-0ec775a2.vercel.app):
  `dpl_4qd6oXoyZcS5Lq4ejEvB9h6xWJQL`, READY preview.
- Main: 9,930,142 bytes; budget gzip 2,862,668 bytes.
- Main SHA-256: `009b31015410a610ab88345fa59139f3b43f5929972bbd7bbfa12d789d8f3b03`.
- Backend: existing dedicated staging `iqltcyimlqtcwyzlemwx`; no remote migration
  or server permission change was applied in this correction.
- Production alias before/after: unchanged `dpl_5N1eU8yvGGi9gGaRX4bBoa3ZW2yr`.

To roll back this client correction, point only the staging alias at its
[previous verified candidate](https://yorks-r35-6t7icvw3i-sajid-alis-projects-0ec775a2.vercel.app)
(`dpl_5js8CGhUHMrXPebNtX6yk9iUZZQk`). Preserve calculator records, grants,
history and the existing server archive guard. Production publication remains
subject to the owner's separate review. No production mutation or PR merge was
performed. Hosted permission-failure injection and physical-device/printer
acceptance are not claimed by the widget/browser evidence above.

## Subsequent authorized production release

The owner subsequently approved production publication. The verified merged
source, guarded production migration, artifact and live evidence are recorded in
[CALCULATOR_POLISH_PRODUCTION_RELEASE_20261007.md](CALCULATOR_POLISH_PRODUCTION_RELEASE_20261007.md).
The staging-only statements above describe the earlier candidate stage.

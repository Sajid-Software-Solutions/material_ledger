# Calculator interaction refinement — audit candidate

The product owner requested this refinement on 6 October 2026, with a separate
Astra audit before production publication. **Production publication is not
authorized for this candidate.** Staging evidence is added after acceptance.

## Scope

- Creation uses one compact dialog: calculator selection, name and a searchable
  General/project scope picker. A typed search is not treated as a selected
  project. The create action requires a name and a real selection.
- Duct uses a code-native airflow mark, independent of a cached icon font.
- Desktop Import and Export are explicit controls. Export groups JSON and
  Print/PDF; phones use the compact Files menu. An editor import can be undone.
- Previous-device import reports available, missing and invalid stored data
  separately. It explains the same-browser/device boundary, offers a JSON-file
  alternative and preserves every legacy key, including corrupt data.
- The record title replaces the local breadcrumb/Back row. Shared top-bar Back
  and Forward consult the edit guard before consuming workspace history. Native
  Back retains the calculator guard and does not issue a second shell Back.
- Access management shares the creation dialog's tokens, search and dropdowns.
  Owner, individual grants, view/edit meaning, successful updates and failures
  remain explicit. Typed person searches cannot grant the previous selection.
- Managed dropdowns share an anchored, keyboard-operable menu. Their storage
  keys are isolated from expansion-panel state. Retained calculator routes keep
  their prior controls; no legacy golden is replaced to hide a regression.

## Edit history and keyboard

Undo/redo cover title, numeric values, engineering settings, imports and ESP row
structure. History is local to the mounted editor, limited to 100 snapshots and
8 MiB, with same-field typing coalesced for 650ms. Unknown imported fields and
row identities survive undo/redo and duplication. A new edit removes the redo
branch. Saving an existing record keeps local history; opening another record
or reloading starts a new session. Undo is a local edit and never rewinds a
server revision; the user must explicitly save it as a new revision.

| Action | macOS | Windows/Linux |
|---|---|---|
| Save | Command-S | Ctrl-S |
| Undo | Command-Z | Ctrl-Z |
| Redo | Shift-Command-Z | Ctrl-Shift-Z; Ctrl-Y also supported |
| Add row | Shift-Command-Enter | Ctrl-Shift-Enter |
| Duplicate row | Option-Command-Enter | Ctrl-Alt-Enter |
| Print/PDF | Command-P | Ctrl-P |

Row shortcuts appear beside the desktop buttons. Add/duplicate insert below
the active row; the last row is used when no row is active. An empty duplicate
retains the established safe first-row fallback. Shortcut help is in the
secondary menu. Buttons and shortcuts use the same permission, busy and pending
command guards. Flutter's overridable text actions prevent double undo; picker
search text retains native undo rather than changing calculator inputs.

## Telemetry

The existing guarded, opt-in PostHog service is reused. Calculator events have
a finite property catalogue: calculator kind, General/project scope, controlled
action, button/keyboard/file/device source, outcome, access mode and bounded
counts. No title, value, reference, query, filename, person, project/record ID,
file contents or raw exception is sent. Capture does not block commands.

Creation intent is distinct from server-confirmed creation. Save and access
outcomes are emitted only after the trusted command returns. List/open/options,
save and management commands have fixed operation names for timing and safe
failure categories. Routes map to identifier-free calculator library/editor
screens. Session replay and autocapture remain disabled in the client.

## Preservation and review

No calculator formula, repository, RPC, RLS, migration, grant policy, feature
default or production configuration is changed. The three existing sharing
manager roles remain Admin, Senior Mechanical Engineer and Project Manager;
project scope still needs project access. Server revision checks, idempotent
pending recovery, historical grants/audit and old device data are preserved.

The audit should review the creation and access dialogs, long searchable lists,
Mac/Windows shortcuts, query-vs-input undo, read-only and pending states, imported
extension preservation, shared Back/Forward, mobile/RTL layout and the bounded
telemetry catalogue. Physical device and printer acceptance is a separate gate.
Staging publication does not approve a production release.

## Accepted staging evidence — 7 October 2026

Status: **staging ready for the owner's Astra audit**. Draft
[PR #51](https://github.com/SajidAfridi/material_ledger/pull/51) remains unmerged.
Machine-readable evidence is in
[CALCULATOR_INTERACTION_POLISH_20261007.json](CALCULATOR_INTERACTION_POLISH_20261007.json).

| Evidence | Result |
|---|---|
| Application source | `bc6859f3f23a48339f50ca9a6c9a8b2db7b06a2a` |
| Staging | [Calculator home](https://yorks-r35-staging.vercel.app/#/tools/calculators) |
| Immutable deployment | [Verified candidate](https://yorks-r35-8j19to7bn-sajid-alis-projects-0ec775a2.vercel.app), `dpl_AzbAYbSsNdXSQL85At33qc4faR4k` |
| Main bundle | 9,928,610 bytes; budget gzip 2,862,255 bytes |
| Main SHA-256 | `7a616a030ef4dd8003184d5fc9585640a0f1b1d92a23cf37ffe843edf89c17ea` |
| Analyzer | No issues |
| Complete Flutter suite | 2,493 passed; four retained skips |
| Clean local database | 123 files; 3,597 assertions passed |
| Builds | CI web and ephemeral-signed CI APK passed; APK is not a store artifact |
| Routes/assets | 26 checks passed against both immutable and public staging URLs |
| Visuals | 13 calculator goldens at 1366/768/360px, including creation/access; retained mobile goldens passed |

Hosted Local Admin acceptance verified an independent empty Duct and ESP,
Command-Z/Shift-Command-Z, keyboard save, active-row insertion/duplication,
structural undo/redo, real server revisions, library return and one shared Back
confirmation. Final selectors expose their labels and current values and open
normally. Desktop and 360px screenshots preserve the universal Yorks shell.
Access presentation was inspected without granting any real person additional
access; positive/negative permission evidence is the unchanged local RPC suite
and viewer/shortcut widget tests.

Actual JSON export downloaded both entered ESP rows. Imported future document
and row fields survived undo/redo, server save and another real export. The final
export SHA-256 was `1805d4b3564e99595fc8cc518a02973e38bf1487cc2f0bf2dd928075da71c36c`.
The browser download-event waiter timed out, but the file was independently
verified in Downloads. Previous-device import displayed the explanatory empty
panel instead of an invalid-file snackbar. Neither legacy key was changed.

PostHog project 600792 received synthetic staging events, filtered by exact
release and a recent two-hour UTC window. The initial functional candidate
recorded creation, confirmed creation/save and history interaction events.
The final candidate recorded opened/interaction/access-result and timed
operation events. The bounded final witness at 20:00 UTC contained 3 opens,
2 interactions, 1 access result and 4 operations; that hour was partial and
later cleanup adds more events. These are ingestion witnesses, not adoption,
conversion, failure-rate or production usage conclusions. No dashboard,
replay setting or production telemetry configuration was changed.

Two synthetic calculators were archived recoverably: Duct
`79d4974d-36d2-4b68-bb4d-ab594287f948` (revision 2) and ESP
`8644cf58-d84f-4d71-8344-d238254bbe87` (revision 3). No temporary grants remain.
Browser error capture returned no entries. Temporary viewport overrides were
reset. Physical device, physical printer and all-role interactive browser
acceptance are not claimed.

The final upload initially returned Not authorized with CLI 62.5.0. The same
artifact/account/team succeeded with the previously verified CLI 62.4.0;
authentication and project settings were not changed. This does not establish
whether the cause was transient or specific to that CLI version.

Production remains deployment `dpl_5N1eU8yvGGi9gGaRX4bBoa3ZW2yr` at
[the production site](https://yorks-r35.vercel.app). No production business
record was mutated. Roll back staging by re-aliasing the prior accepted
`dpl_3BsKDGQ1k9V1KxhpF9m86kmWNpGZ` artifact; retain calculations, grants,
revisions, audit and local data. Do not use a generic remote database push.

### Screenshots

- [Creation, desktop](evidence/calculator-interaction-polish-20261007/create-desktop.jpg)
- [Access, desktop](evidence/calculator-interaction-polish-20261007/access-desktop.jpg)
- [Device import, no prior data](evidence/calculator-interaction-polish-20261007/device-import-empty.jpg)
- [Home, desktop](evidence/calculator-interaction-polish-20261007/home-desktop.jpg)
- [Duct, desktop](evidence/calculator-interaction-polish-20261007/duct-desktop.jpg)
- [Duct, mobile](evidence/calculator-interaction-polish-20261007/duct-mobile.jpg)
- [ESP, desktop](evidence/calculator-interaction-polish-20261007/esp-desktop.jpg)
- [ESP, mobile](evidence/calculator-interaction-polish-20261007/esp-mobile.jpg)
- [Named sizing menu](evidence/calculator-interaction-polish-20261007/dropdown-desktop.jpg)

## Subsequent audit corrections

The owner-reported rejected access downgrade and coalesced Delete/Clear history
findings are corrected in [CALCULATOR_REVIEW_CORRECTIONS_20261007.md](CALCULATOR_REVIEW_CORRECTIONS_20261007.md).
That document identifies the latest staging artifact and full verification.
The accepted staging identity above remains historical evidence.

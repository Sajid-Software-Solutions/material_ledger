# Combined calculator workspace

## Approved scope — 6 October 2026

The product owner requested one home for Duct Sizer and ESP Calculator, named
saved calculations, general or project scope, explicit view/edit sharing,
existing import/export/print workflows, and a calm Codex-inspired interface
inside the existing Yorks shell. Admin, Senior Mechanical Engineer and Project
Manager are the approved sharing managers.

## Behavior and boundaries

- The home lists authorized records with search, calculator type, general/project
  and archived filters. Open a record or create a separate named calculation.
- Technical engineering users and Admin can create records. Existing device
  calculations are preserved and can be explicitly imported into a new record.
- General calculations require ownership, an explicit grant, or a manager role.
  Project calculations additionally require current project read access. A
  calculator grant never creates project membership or BOQ/MR/stock authority.
- Managers grant view/edit access and revoke grants. Viewers can export/print
  but cannot change values. Only managers archive/restore; history is retained.
- Project and calculator type are fixed after first save. A new calculation or
  explicit JSON import creates a separate identity, without moving shared data.
- Save uses server confirmation, an expected revision and an idempotency key.
  Concurrent stale writes conflict. An uncertain save retains its exact intent
  under a backend/account/record-specific recovery key and retries that intent.
- Unsaved edits have a navigation guard. Permission refresh never overwrites
  locally edited inputs or silently advances the loaded revision.
- JSON imports retain unknown fields and validate format, tool, size and numeric
  values. Existing duct and ESP formats remain supported. JSON export and print
  use the current inputs, including unsaved edits; the PDF identifies the saved
  revision or unsaved state.

## Implementation map

| Layer | Source |
|---|---|
| UI | `lib/features/engineering_tools/presentation/screens/yorks_calculator_workspace.dart` |
| Retained engineering editors | `lib/features/engineering_tools/presentation/screens/yorks_v1_engineering_calculator_screens.dart` |
| Models and localized workspace copy | `lib/shared/models/yorks_v1_calculator_{workspace,strings}.dart` |
| Controller/provider/repository | Corresponding `yorks_v1_calculator_*` files under `lib/shared/` |
| File download | `lib/shared/services/calculator_file_download*.dart` |
| Routes and existing shell | `lib/app/router.dart`, `lib/app/yorks_v1_workspace_shell.dart` |
| Database | `supabase/migrations/20261006092502_calculator_workspace.sql` |
| Tests | `test/yorks_calculator_workspace_test.dart`, `supabase/tests/database/yorks_calculator_workspace.test.sql` |

Widgets call the controller/repository. Private RLS tables have no ordinary
client table privileges. Trusted RPCs check live active identity, project access,
manager roles, grants and revisions; save/access/archive actions append audit.
The feature adds no stock, commercial or material-request mutation authority.

## Preservation and rollout

`YORKS_V1_CALCULATOR_WORKSPACE` defaults to false. With it off, existing tool
routes and device storage continue to work. With it on, both legacy tool entry
routes open the combined home within the universal Yorks shell. The two retained
calculators remain the calculation engines; no formula migration is performed.

The migration is additive and repeatable. Existing collections, local files and
legacy calculation keys are not deleted or overwritten. Disable the feature flag
to roll back the interface; retain new tables, grants and audit. Do not drop data
or run a generic remote database push across an unreconciled migration ledger.

Production enablement was separately authorized and completed; see
[CALCULATOR_PRODUCTION_RELEASE_20261006.md](CALCULATOR_PRODUCTION_RELEASE_20261006.md)
for the published artifact and live evidence.
Apply only this reviewed additive migration to an explicitly verified target,
then enable the feature in a tested artifact. Staging browser/persona acceptance
must precede production promotion.

## Acceptance and release preparation — 6 October 2026

The product owner authorized completing the work and publishing it to production
after the earlier release gate stopped. That authority includes investigating
and repairing the unrelated test fixture that had blocked acceptance.

The MR scope-filter test used two unordered `LIMIT 1` selections over a fixture
with both Common and physical scopes. It now selects the fixture's `main`
physical scope explicitly and checks that Common returns no matching requests.
The MR server implementation is unchanged. The focused register test passes
69 assertions.

Local acceptance:

- Dependencies resolved; complete Flutter suite: 2,469 passed, four retained
  skips. Latest focused calculator suite: 21 passed, including Unicode PDF,
  1,000-row ESP printing, Arabic RTL editing at 360px, input preservation and
  routed new/save/back library refresh.
- Clean local database reset and full suite: 123 files, 3,597 passed. Calculator
  permission/idempotency suite: 50 passed. Inactive/deleted users fail closed;
  explicit Accountant grants provide calculator access without role promotion.
- Real competing database sessions: one writer commits, the other conflicts,
  a replay adds no revision/audit duplicate. The local fixture is archived;
  audit and data remain recoverable.
- Home, Duct and ESP goldens at 1366, 768 and 360 pixels are under
  `test/goldens/calculators/`. Workspace and shared editor labels use the four
  existing languages. Stable material/fitting identifiers and units remain
  unchanged in saved/imported JSON.
- PDF inspection includes first/last pages of a 1,000-row ESP calculation.
  Four-digit row numbers remain intact; headers repeat, page numbers and record
  context remain visible, and totals include all rows. Technical report labels
  retain the existing English document convention; names support Unicode fonts.
- The earlier local browser witness covered Admin sign-in, the universal shell,
  Duct creation/edit/save/reopen, sharing, JSON values and PDF generation.
  Final staging/production witnesses and artifact identities are recorded in
  [CALCULATOR_PRODUCTION_RELEASE_20261006.md](CALCULATOR_PRODUCTION_RELEASE_20261006.md).

Both production schema and data backups were captured before DDL. This additive
migration creates only calculator relations/functions and its migration ledger
entry. Existing workflow/audit tables receive no migration DML. Remote ledger
versions may differ from the canonical file because MCP records its application
version; compare exact function bodies/ACLs and record that mapping. Do not use a
generic `db push` across the existing production ledger divergence.

The feature flag stays off in unconfigured/CI builds. The accepted staging and
production artifacts explicitly enable it alongside the existing project setup,
Accounts, Company Requests, Workforce and Analytics release flags. Native CI
APK validation is separate from this web publication and is not a store release.

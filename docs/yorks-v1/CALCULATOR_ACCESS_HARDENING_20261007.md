# Calculator sharing and archived-project protection

## Findings and changes

The owner reported two code-review findings, without claiming a reproduced
production incident. Both were reproduced in targeted regression tests:

1. The combined calculator route accepted Accountant, but the shared destination
   catalogue's Accountant filter removed its menu. The filter now admits the
   calculator home when its existing feature flag is enabled. Unauthorized
   records remain absent through server filtering. No project, BOQ, MR, stock,
   user-administration, create or sharing permission is added to Accountant.
2. The project picker excluded archived projects, while `v1_save_calculator`
   checked only readability. The additive migration
   `20261006204245_calculator_archived_project_guard.sql` checks the authoritative
   project state under `FOR SHARE` before a new write. This conflicts with the
   archive command's project-row update lock, closing both race orders.

Existing authorized project calculations remain readable and exportable, with
`can_edit=false` in list/detail responses. A successful idempotent replay still
acknowledges the original save, updates edit permission from current state, and
does not add a revision or audit. New save attempts to archived projects fail
with `CALCULATOR_PROJECT_ARCHIVED`. The client clears the definitively rejected
retry, keeps local editor inputs and loaded revision, switches to read-only,
and explains the restriction in English, Arabic, Urdu and Hindi.

## Verification

- Before the fix: four desktop/mobile Accountant navigation tests failed; the
  archive regression reproduced successful unauthorized creation/update and
  writable responses.
- After the fix: four flag-enabled Accountant discovery/route tests pass at
  1366px and 360px, with Accounts enabled and disabled. Technical and user-
  administration menus remain absent. Flag-disabled navigation stays covered
  by the complete suite.
- [Desktop navigation](../../test/goldens/calculators/accountant_navigation_1366.png)
  and [360px drawer](../../test/goldens/calculators/accountant_navigation_360.png)
  are isolated widget visual evidence, not a live Accountant browser session.
- Calculator database suites: 78 assertions, including all nine exact roles,
  explicit Accountant view/edit grants, nonarchived/general positives,
  unauthorized project access, archived create/update negatives, preserved
  payload/version/audit/idempotency and successful replay after archive.
- `python3 tool/test_calculator_project_archive_concurrency.py`: two independent
  real database sessions pass both archive-first and save-first ordering. The
  disposable committed fixtures were removed by the subsequent clean local
  reset. The harness accepts no remote database URL or credentials.
- Dependencies resolved; analyzer clean; complete Flutter suite 2,498 passed
  with four retained skips. A test-only theme change initially disturbed an
  existing shell assertion; scoping the visual theme to the new Accountant
  captures restored the full pass.
- Clean local reset and full database suite: 124 files / 3,625 assertions pass.
- CI web and 111.8 MB Android APK builds pass. Android used the required
  ephemeral CI signing lane; it is not a production-signed distribution.

## Staging server witness

Target was verified as healthy `yorks-r35-staging`, project
`iqltcyimlqtcwyzlemwx`. Only the reviewed additive migration was applied; no
generic remote database push was used. Remote ledger version is
`20261006205512`, name `calculator_archived_project_guard`.

`tool/calculator_access_archive_staging_witness.sql` passed against existing
active Admin and Accountant identities, with synthetic calculations/project/
grants/audits entirely rolled back. It verified Accountant view-only and edit
grants, unchanged create/sharing authority, picker exclusion, archived-project
creation/update rejection, preserved read output and successful replay.

Post-migration checks confirm the project lock and guard exist, anonymous save
execution remains denied, authenticated save execution remains allowed, and
the internal projection remains inaccessible directly to authenticated users.
Calculator count stayed at six. Security-advisor findings were identical before
and after (510 existing findings); no new finding was introduced. Intentional
RPC-only tables retain their deny-all table access.

## Release and rollback

This fix joins the pending calculator audit candidate in draft PR #51. The
previous Astra-before-production gate remains in force. Production received
read-only inspection: its save function lacked the archive guard. It was not
mutated by this task.

No data, grants or history are rewritten or deleted by the migration. To roll
back the interface, revert the menu/client patch or disable the calculator
workspace flag; keep the server protection. Do not restore the unsafe save
function. Production deployment and applying the reviewed migration to
production remain a later approved release action.

### Hosted client candidate

Application source: `90899fb4e9d4511af81983b6fba95491253d22c9`.
Final preview deployment: `dpl_5js8CGhUHMrXPebNtX6yk9iUZZQk`,
`https://yorks-r35-6t7icvw3i-sajid-alis-projects-0ec775a2.vercel.app`.
The staging alias is updated only after immutable artifact verification.
Main bundle: 9,929,668 bytes; SHA-256
`df8519049300510e6752dfa85121a4a1593f9dc0543fee1bf12b378345bb72fd`.
The isolated artifact contains the clean source revision once, the staging
backend, and no production backend, CI URL or service-role JWT. PostHog stays
opted in for staging with its existing privacy bounds.

The final build explicitly preserves the accepted calculator and project-setup
rollouts, in addition to the operator file's Accounts, Company Requests,
Workforce and Analytics flags:

```bash
YORKS_V1_CALCULATOR_WORKSPACE=true YORKS_V1_PROJECT_SETUP=true \
R35_CONFIG_FILE=/tmp/calculator-guard/staging.env ./tool/r35.sh build-web
```

Two deployment setup errors were caught and recovered during verification.
A command issued from the source checkout created an unused `material_ledger`
Vercel project; upload was rejected, no deployment existed, and that newly
created project was removed and its absence verified. Upload was then repeated
from the explicitly linked isolated web artifact. Browser verification caught
that the first artifact inherited default-off calculator/project-setup flags
from an older staging config. The previous known-good staging alias was restored
while the final artifact was rebuilt with both flags explicitly enabled. The
superseded preview `dpl_6xxYraDG2dXj5nWw5hjrUc1HnjEC` is not the accepted
candidate. Production was untouched throughout.

Final immutable preview and public staging each pass 26 route/asset byte checks.
The staging alias resolves to the final deployment above. The signed-in Admin
browser opened Calculators from the universal sidebar and confirmed both tools,
Import/New controls and a completed authorized library load. See the
[browser screenshot](evidence/calculator-access-hardening-20261007/staging-home.jpg)
and [machine-readable evidence](CALCULATOR_ACCESS_HARDENING_20261007.json).
This does not substitute for a live Accountant browser session; that role is
covered by the widget visual/route tests and the staging trusted-RPC witness.
Production still resolves to `dpl_5N1eU8yvGGi9gGaRX4bBoa3ZW2yr`, with unchanged
save-function hash `b2e6e5e4fd91acbfc804133afdccf706` and no archive guard yet.

## Subsequent authorized production release

The owner subsequently approved production publication. The verified merged
source, guarded production migration, artifact and live evidence are recorded in
[CALCULATOR_POLISH_PRODUCTION_RELEASE_20261007.md](CALCULATOR_POLISH_PRODUCTION_RELEASE_20261007.md).
The staging-only statements above describe the earlier candidate stage.

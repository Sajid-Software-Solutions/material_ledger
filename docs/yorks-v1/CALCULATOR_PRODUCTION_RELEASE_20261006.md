# Calculator production release — 6 October 2026

Status: **released and verified** at
[production Calculators](https://yorks-r35.vercel.app/#/tools/calculators).
The product owner explicitly authorized completing acceptance and updating
production after the earlier test-gate stop.

Machine-readable evidence is in
[CALCULATOR_PRODUCTION_RELEASE_20261006.json](CALCULATOR_PRODUCTION_RELEASE_20261006.json).
The behavior and source map are in [CALCULATOR_WORKSPACE.md](CALCULATOR_WORKSPACE.md).

## Released behavior

One home now combines Duct Sizer and ESP inside the universal Yorks sidebar and
header. Users create separate named records, reopen saved inputs, choose general
or project scope, search/filter, import existing/device JSON, export JSON,
print/PDF and archive/restore. Phone ESP uses one focused row editor. Workspace
and shared editor labels use the existing language catalogues; stable stored
material/fitting names and units retain their existing import identities.

Admin, Senior Mechanical Engineer and Project Manager manage explicit view/edit
sharing. Other users require ownership or a grant, and project calculators also
require project access. Grants confer no technical membership, stock,
procurement, commercial or user-administration authority. Inactive/deleted users,
stale roles, missing project access and ungranted records fail closed. Saved
revisions, competing writers and idempotent recovery protect input history.

Existing device calculations remain intact and are explicitly importable.
Project setup, Accounts, Company Requests, Workforce, Analytics, telemetry and the
complete R35 chain remain enabled in the production artifact. The calculator
flag stays off by default in unconfigured and CI builds.

## Source, artifact and deployment

| Evidence | Value |
|---|---|
| Merged implementation | [PR #47](https://github.com/SajidAfridi/material_ledger/pull/47) |
| Production application source | `53396252c9cb1a197656f8aa765effb3c51f7cd5` |
| Staging application source | `59122c6f4705548056a4ab9e4a5e14402db8f850` |
| Production deployment | `dpl_9rjHvheK76jH9z5kysbewH36oG8M`, READY |
| Immutable production artifact | [verified artifact](https://yorks-r35-ppd0aiybn-sajid-alis-projects-0ec775a2.vercel.app) |
| Production backend | `czykuksmlwswjsgotrpo` |
| Main JavaScript | 9,850,473 bytes; gzip 2,840,104 bytes |
| Main SHA-256 | `ab69fe1071d256ef6572855417ce03c66b143d52a561cb09d8c01211f74d7d94` |
| Static artifact | 60 files; 54,263,949 bytes |
| Release marker | Exact application source occurs once; no dirty marker |
| Client credential scan | No service-role JWT, staging backend or CI placeholder |

The main bundle and deferred JavaScript, shell routes, PWA files and workers
matched the isolated artifact before promotion and on the public production
alias afterward: **26 checks passed in each run**, including both calculator
deep routes. Staging passed 24 core checks plus the same two calculator routes.
The staging alias remains bound to its isolated staging backend. Vercel project
settings were not changed.

## Database publication and preservation

The canonical reviewed source is
[20261006092502_calculator_workspace.sql](../../supabase/migrations/20261006092502_calculator_workspace.sql).
MCP application recorded it as staging version **20261006122538** and production
version **20261006130951**, both named `calculator_workspace`. These versions
are deliberately recorded separately from the source filename. Ten function
body hashes match local, staging and production; their exact hashes and ACLs are
in the JSON record. Tables have RLS enabled and no anonymous/authenticated
ordinary table-read privileges. Internal helpers are not callable by those
roles; only the authorized calculator RPC surface is exposed.

The migration adds calculator relations/functions without business-table DML.
Production counts before/after DDL remained: **14 projects, 193 Material
Requests, 1,160 inventory movements, 27 profiles, 1,974 audit events**. The new
calculator relations were empty. Production browser verification issued no
calculator save or sharing command.

Private schema and data backups were captured before publication, with mode
0600, under `/tmp/yorks-calculator-workspace/`. Their sizes and hashes are in
JSON. The data dump reported the existing cyclic foreign keys; restore planning
must pair it with the schema and handle those constraints/triggers. Restore was
not performed.

Advisor categories remained the baseline RLS-without-policy information and
existing function-execute/auth-password-protection warnings. Calculator tables
intentionally deny ordinary APIs and expose audited RPCs; their explicit ACLs
and positive/negative tests are the acceptance evidence. No new advisor category
appeared. The retained production migration-ledger divergence is not repaired by
this publication; a generic `db push` remains inappropriate.

## Verification

- Analyzer: no issues. Dependencies, formatting and diff checks passed.
- Complete Flutter suite: **2,469 passed, four retained skips**; final calculator
  suite: **21 passed**.
- Clean local database reset and full pgTAP suite: **123 files, 3,597 passed**;
  calculator security/idempotency: **50 passed**.
- The former MR register failure was an unordered fixture scope selection. Both
  selections now target the physical `main` scope explicitly, with a negative
  Common-scope case: **69 passed**. MR server code was unchanged.
- Real competing local database sessions produced one commit and one conflict;
  replay produced no duplicate revision/audit. The fixture was archived safely.
- Home/Duct/ESP visual evidence passed at 1366, 768 and 360 pixels. Arabic RTL
  editor labels passed at 360px.
- Actual print generation passed Unicode metadata and 1,000 ESP rows. Rendered
  first/last pages were inspected; the 31-page report retains headers, record
  context, four-digit row numbers, page numbers and complete totals. Technical
  PDF labels retain the established English report convention.
- CI web and APK release builds passed. The APK uses ephemeral CI signing and
  is not an Android store publication. GitHub Flutter workflow/account exceptions
  remain distinct from local validation; Vercel PR statuses passed.

Staging browser acceptance covered General Duct creation, numeric edits,
server-confirmed save, library discovery, an independent fresh project ESP,
project-header prefill, row editing/totals, export and import. The real downloaded
ESP JSON contained the entered values. Imported future fields survived the
server save. Admin view/edit grants were exercised; recipient RPC checks proved
view denies writes, edit permits writes and revocation denies reads. Recipient
save proofs were rollback-only. The two synthetic calculators remain archived
and all temporary grants were removed; prior staging projects/requests remained.

Authenticated production **Owner/Admin** opened the combined home and a fresh,
empty calculation dialog, then cancelled it. The existing Yorks shell remained
present and no browser errors were recorded. Server read smoke assertions used
real active accounts for **all nine exact roles** and confirmed the expected
create/manage flags; this was an authenticated-claim SQL witness, not nine
interactive browser logins. The bounded Vercel error/fatal scan returned no
entries; static-host logs do not establish Supabase or all-day application health.

[Production screenshot](evidence/calculator-production-20261006/production-calculators.jpg)
shows the new home without finance values or other private business content.
Physical-device, physical-printer and longer operational observation are not
claimed by these automated/browser witnesses.

## Rollback

Promote the previous verified deployment
`dpl_GKcFd2A49YWDNHCiyL8Eh5Hnkqf3`,
[previous artifact](https://yorks-r35-gu8hyjnul-sajid-alis-projects-0ec775a2.vercel.app),
to roll back the web release. Retain calculator data, grants, revisions and audit;
disable the calculator feature in a replacement build if needed. Do not drop
relations or reverse unrelated project safeguards. Reconcile remote migration
versions explicitly before any later CLI migration operation.

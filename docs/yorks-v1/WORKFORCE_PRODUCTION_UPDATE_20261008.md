# Workforce production update — 8 October 2026

Published with the owner's explicit production authorization.

- Source: `83689eca9e155de2861b306ba2b9d498518817cc`. Includes Workforce
  commits through `1feafa6` and the existing production Material Request
  recovery source `abfb850ac8b836cf3736c53cbae9f8354bd55e72`.
- Public URL: https://yorks-r35.vercel.app/#/yorks/workforce
- Deployment: `dpl_6pvXKeX5Ujkzjuapb1cJUXW1qV3Q`.
- Immutable URL: https://yorks-r35-8jb5621z8-sajid-alis-projects-0ec775a2.vercel.app
- Existing production backend: `czykuksmlwswjsgotrpo`.
- Retained Accounts, Project Setup, Calculators, Company Requests, Workforce,
  Analytics and telemetry configuration; enabled `YORKS_WORKFORCE_TEAM_WORKERS`.

## Backend publication

Applied only `workforce_assigned_team_worker_creation` after staging application
and function/ACL verification. Production ledger version is `20261007201135`;
canonical source filename is `20261007193129_workforce_assigned_team_worker_creation.sql`.
No broad db push or business-record migration was performed. Function hashes
match staging: create `52de8d8e4e062d25a49cf8f06cb376b4`, read
`a92ac6ee961e18a493d0652a44bf973d`, private helper
`9118af945a3629a8985ae857627b910d`. Anonymous execution is denied; only the
two public endpoints are authenticated-callable. The helper is private.
A read smoke test with active Admin claims succeeded in a rollback transaction.
The first smoke attempt lacked the required actor claim context and failed closed.

## Verification

- Combined-source analyzer clean; 2,554 Flutter tests passed, four skipped.
- Prior new Workforce migration acceptance: 3,642 local DB tests passed.
- Production web build and startup budget passed; source marker is clean.
- All 26 public route/asset checks byte-match the isolated artifact, including
  main/deferred JavaScript, PWA files and existing calculator routes.
- No CI/staging backend or service-role credential in the client scan.
- Authenticated Owner/Admin browser rendered the updated Workforce overview
  with Workers, Attendance and Reports shortcuts, the universal shell and
  server-confirmed data; no browser errors were observed.
- No real worker or attendance record was created as a production smoke test.
  Worker creation/export/print rely on local tests until staff acceptance.
  Physical printer/device and human field UAT remain unclaimed.

## Rollback

Previous production: `dpl_H7NVZT2YFXoT4nSxwkyc9JpCsSmX`,
https://yorks-r35-hxr2tlfes-sajid-alis-projects-0ec775a2.vercel.app .
Promote that retained artifact if needed. Disable the new feature and revoke
its two RPC grants for a targeted backend rollback; preserve worker, assignment
and audit data. The remote migration version differs from its canonical source
filename, so reconcile explicitly before future migration operations.

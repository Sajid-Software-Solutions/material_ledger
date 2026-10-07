# Consolidated navigation production update — 8 October 2026

Owner explicitly requested deployment.

- Source: `bf9babd4c36d32f1a2aa509a2183ba68b7ee55dc`.
- Deployment: `dpl_CPLptRAoGiqczgKAdmGp9DsRpSkH`, Ready.
- Public application: https://yorks-r35.vercel.app
- Immutable artifact: https://yorks-r35-190ul5v56-sajid-alis-projects-0ec775a2.vercel.app
- Rollback deployment: `dpl_6pvXKeX5Ujkzjuapb1cJUXW1qV3Q`.

Preserved the current production source and all enabled modules, including
Project Setup, Accounts, Calculators, Company Requests, Workforce, assigned-team
worker creation, Analytics and telemetry. No database changes.

Production web build/startup budget passed. All 26 live route and asset checks
byte-matched the isolated artifact. Client scan found the correct production
backend and clean source marker, with no CI/staging backend or service-role JWT.
Prior local acceptance: 2,556 tests, four skips, clean analyzer, desktop/360px
visual checks, web build and ephemeral-signed verification APK.

Authenticated Owner/Admin browser confirmed the consolidated sidebar and
Workforce internal sections with server-confirmed overview data and no observed
browser errors. No attendance, worker or commercial record was modified.

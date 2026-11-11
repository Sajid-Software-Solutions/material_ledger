# Admin Overview and Analytics release — 8 October 2026

## Scope and authorization

The owner approved implementation of the [review plan](ADMIN_OVERVIEW_ANALYTICS_REVIEW_20261008.md)
and production deployment on 8 October. This release changes presentation,
route/filter continuity, read dependencies and bounded interaction telemetry.
No database migration, authorization expansion, business-record mutation,
financial definition change or new reporting timezone is included.

## Implemented

- Attention before compact KPI cards; up to four request previews and separately
  labelled domain counts. Recent project activity is a bounded register preview.
- Focused Analytics domain sections, URL-backed project/period/domain context,
  source navigation with Back restoration and mobile filter sheet.
- Confirmed-current values distinguished from monthly movement charts. Empty
  Rental portfolios have no occupancy percentage. Coverage is a neutral disclosure.
- Accessible data tables accompany charts. MR comparison uses the last two
  complete UTC calendar months, excluding the unfinished current month.
- A minimal RLS-protected project picker replaces whole-project hydration.
  Normal Admin Overview uses the combined protected summary before loading
  legacy dependencies. The established fallback remains available on failure.
- Refreshes coalesce; rejected refreshes do not retain unconfirmed values.
  Authority changes continue to invalidate protected providers.
- Shared domain/summary/chart widgets extracted from the monolithic screen.
- Fixed-category analytics interaction events and typed dashboard read outcomes;
  no project names, IDs, values or search text are sent.

## Metric dictionary and navigation

All counts include only the server-authorized effective scope. A missing or denied
domain is unavailable, never a confirmed zero. Confirmed zero is displayed only
from a successfully validated projection. All source destinations authorize again.
The [frozen source definitions](OPERATIONAL_ANALYTICS_AND_FOUNDER_OVERVIEW.md#4-frozen-company-view-kpis)
remain authoritative.

| Metric family | Unit / denominator | Time and scope | Source and destination |
|---|---|---|---|
| Projects and lifecycle | Projects; exact state counts / readable projects | Current snapshot; company or selected project | Protected project projection; Projects register / specific project |
| MR pipeline and attention | Requests; exact workflow states / readable requests | Current snapshot; company or selected project | Protected MR projection; scoped MR register / specific request |
| MR movement/comparison | Submitted and closed requests per bucket | Selected 3/6/12 UTC months; comparison last two complete buckets | Server monthly series; MR source register for investigation |
| Accounts position | Decimal monetary amounts, separately per ISO currency | Current protected commercial position; eligible projects | R39 protected Accounts projection; Accounts workspace |
| Accounts movement | Claimed, certified and received amounts per currency | Selected server UTC monthly buckets | R39 protected monthly projection; Accounts source workspace |
| Workforce | Workers, pending attendance/periods, regular and OT minutes | Organization scope only; latest approved monthly snapshots | Protected Workforce overview; Workforce workspace |
| Rentals | Properties, occupied properties / total properties, AED amounts | Organization scope only; current snapshot and monthly collections | Protected Rental projection; Rentals workspace |
| Request update | Record update timestamp and owner role | Latest readable record update, not time in workflow stage | Specific protected request |
| Recent project activity | Up to five records; not a global audit feed | Latest readable project/request update | Specific protected project |

Domain workspace links are investigation entry points; existing source routes do
not support every chart bucket as a prefiltered register. This release does not
claim exact bucket drill-down where that route contract is absent. Reporting
remains explicitly UTC; changing the business reporting day requires a separate
agreed server contract.

## Dependency and repeatable checks

Normal Admin entry: permission resolution → combined schema-v2 summary RPC →
strict model → Overview. Analytics adds only project id/reference/name options
through the repository. Widgets make no direct backend calls. Refresh invalidates
one query; Realtime remains an authorized re-fetch signal.

The repeatable fixture is `test/company_analytics_foundation_test.dart` with
confirmed, empty, denied, malformed, unavailable and competing refresh cases.
Golden fixtures cover desktop, tablet, 360px and RTL. These fixtures are functional
and visual evidence, not network performance benchmarks. The review's individual
live timing observations remain the baseline; no p95 improvement is asserted.

## Validation and rollout

Release gate results and deployed artifact identity are recorded below after
completion. Production rollback target identified before changes:
`dpl_CPLptRAoGiqczgKAdmGp9DsRpSkH`.

No schema or operational data rollback is necessary. Restore the prior Vercel
artifact to roll back the client. Unrelated main-checkout changes are excluded.

## Remaining acceptance work

The proposed 4–6-person management pilot, physical-device/screen-reader acceptance
and representative network/load p95 study require real participants and measured
post-release traffic. They have not been substituted with automated results.
Domain fault isolation/index changes were conditional on profiling and are not
introduced without a justified server contract. This release preserves atomic
summary failure behavior and its existing fallback. No AI/complex BI, forecasts,
payroll, P&L or dashboard-builder scope is introduced.

### Automated gate evidence

- Dependency resolution, changed-Dart format check, full analyzer: passed.
- Full Flutter suite: 2,559 passed, four retained skips. The final period-label
  clarification then passed 49 focused regression tests and refreshed four
  Analytics goldens; analyzer remained clean.
- Local Supabase reset and database suite: 125 files, 3,661 tests passed.
- CI web and ephemeral-signed APK builds passed. The APK is a CI gate artifact,
  not a distribution-signed Android release or physical-device acceptance.
- Desktop, tablet, 360px and RTL golden evidence is in `test/goldens/analytics/`
  and Admin Overview evidence in `test/goldens/r38_10/`.
- Internal documentation links and `git diff --check` passed.

### Deployed release

- Source commit: `fb6631fb26cb59f0ca99fc4c3fa0ce89bd41de76` (clean production build).
- Staging: `https://yorks-r35-staging.vercel.app`, candidate
  `https://yorks-r35-3etj7a37q-sajid-alis-projects-0ec775a2.vercel.app`.
  Dedicated staging backend; all 27 route/asset checks matched the build.
- Production: `https://yorks-r35.vercel.app`; deployment
  `dpl_5jsSC2katbrBQnFoXxyb4CUVTAgV`, immutable URL
  `https://yorks-r35-l86ndm73j-sajid-alis-projects-0ec775a2.vercel.app`.
- Candidate and public production each passed all 27 route/asset SHA-256 checks,
  including deferred libraries, PWA files and retained module routes.
- Production source stamp/backend separation verified; no CI or staging backend
  was present in the production artifact. Existing module flags retained.
- Authenticated staging Analytics checked at desktop and 360px; mobile period
  sheet changed to 12 months and the URL and confirmed result retained it.
- Authenticated production Overview and Analytics checked in the universal shell
  on desktop and mobile. These were read-only checks; no business records changed.
- Immediate Vercel 5xx query returned no matching logs. This narrow observation
  does not establish a longer reliability window or backend latency percentile.
- Previous production remained active until explicit promotion. Rollback uses
  the previously recorded deployment; database state remains unchanged.

Browser evidence: `/private/tmp/yorks-analytics-evidence-20261008/`. Build/test/
verification logs use `/tmp/yorks-analytics-*`. The production web build passed
the startup budget: main JS 9,973,574 bytes, gzip 2,877,093 bytes.

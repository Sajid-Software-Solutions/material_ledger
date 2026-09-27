# Company Use production release — 27 September 2026

Status: **publication authorized; staged staff policy verified; final artifact gates in progress**.
The live production alias still carries PR #30 until the verified candidate is promoted.

## Approved behavior and scope

The product owner authorized publishing Company Use and subsequently specified
company-wide requesting and six categories. [Product decision §30](PRODUCT_DECISIONS.md)
records the exact access scope. Every active canonical Yorks account may request,
be a beneficiary and receive in the six published Company Operations scopes:
Personal Use, Office Supplies, Warehouse Supplies, Worker Supplies, Safety & PPE
and Other. All six existing approver roles may approve. The existing **Submit
and Approve** fast path retains its independent beneficiary/receiver exclusion.
Accountant and Procurement inherit no Project MR, BOQ or stock mutation authority.

The implementation removes the production-only frontend pause while retaining
the default-off deployment flag, exposes the Company entry to Accountant in the
shared shell and both route guards, and adds protected, explicitly configured
staff policies. Per-person dated grants and immutable provenance are provisioned
for existing and future active Auth accounts. Live Auth role/ban/deletion and the
canonical profile mirror are rechecked. Revoked grants never reopen automatically;
inactive/expired staff policy removes its generated authority. Existing individual
Company scopes and business evidence remain intact.

Production base: `486fea7efbb06945e00b7e9c494f3e2e53b22da1` (PR #30).
Inspected previous public JavaScript SHA256:
`15e5cdf0d48eb9d6fa0bb21d73411ed43a199f7ef573c031ff4072ff10855929`.
Branch: `codex/yorks-company-use-production-20260927`; PR #32. The dirty primary
checkout is preserved; builds and commits use the isolated checkout.

## Database and configuration

Canonical additive migration: `20260927011706_company_material_request_staff_policy.sql`.
Install itself creates no catalog, authority or business records. Reviewed launch
configuration is the repeatable [operator SQL](../../tool/company-material-request-launch-policy.sql).
It uses generated catalog IDs and real live-role users, never technical personas
in production. Initial routing picks a real active Admin primary and Senior
Mechanical Engineer (or another eligible approver) alternate; selected approver
choices remain independent and server validated.

Production preflight found no Company catalog or requests and 25 active users,
including 17 approver-role accounts. Staging uses only its existing seven visibly
labelled technical personas; the historical demo policy remains separate.
Staging now has six real launch scopes, 150 generated grants/provenance records,
and six routes, alongside its existing demo data. The staged migration ledger
was reconciled to the canonical version only after exact statement MD5 matching.

## Verified gates and explicit limitations

- Changed Dart formatting, analyzer and diff checks passed.
- Complete PostgreSQL 17.6 migration reset and pgTAP suite passed: **112 files,
  3,191 assertions**, including 51 new staff-policy assertions. All nine exact
  roles, demotion/promotion, new Auth onboarding, inactive/banned/deleted users,
  mirror mismatch, unknown roles, revoked grants, policy disablement, direct API
  denials, and immutable provenance are covered.
- Local competing policy provisioning returned 4/0 grants with exactly four
  provenance events. Re-running launch configuration created no duplicate grants.
- Six Accountant routing/navigation tests passed, including flag-off behavior,
  shared-home/Company access and Project/Inventory/editor denials at desktop and
  360px. The combined-home tests also exercise Accountant.
- Dedicated staging Auth/REST: **35 new staff-policy checks** passed with seven
  technical personas. Six categories/all active participants, PE fast approval,
  concurrent duplicate retries, one recorded decision/number, non-approver and
  beneficiary/receiver self-approval denials, Accountant private draft/submission,
  Project write denial and cancellation preservation were checked. Median options
  round trip across seven reads was **861 ms**, including network, not an SQL-only
  performance benchmark. A connection reset before final cancellation commit was
  reconciled by read-back and resumed; all synthetic evidence was cancelled.
- The prior 30-check staging Company lifecycle was repeated successfully after
  this migration: supply revision/reapproval, dispatch, receiver confirmation,
  beneficiary handover, immutable issue evidence, closure and cancellation retry.
  These are technical smoke checks, not named-employee/manual UAT.
- Full Flutter suite: **1,674 passed / 270 existing failed**, with **no new failing
  names** versus the earlier 1,666/270 preparation run. The complete Flutter gate
  remains red; unrelated goldens/baselines were not rewritten. This release does
  not claim every legacy state or platform/manual check is certified.
- Supabase security advisors found no new warning on the internal provisioner or
  Auth trigger. The two service-only tables intentionally have RLS with no client
  policies. Existing unrelated advisor warnings remain outside this release.

CI web/APK, final hosted desktop/360px visuals, PostHog ingestion, production
policy preservation checks and candidate/public artifact hashes are recorded in
the external checksummed evidence package after completion. The CI APK uses the
separate ephemeral certificate and is not a production Android release.

## Rollback and preservation

Rollback uses the Company flag off and the previous compatible verified web
artifact. Disable the protected staff policy if participant access must be paused.
Keep all Company/Project IDs, private drafts, grants/revocations, approval/supply
snapshots, reservations, movements, dispatches, receipts, handovers, returns,
immutable issue evidence and audit/provenance history. Do not drop schema, reset
counters, copy staging users or delete business records.

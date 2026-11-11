# P2 production release — 16 October 2026

Status: **deployed and verified** at [Yorks production](https://yorks-r35.vercel.app).

The owner explicitly authorized this production release. This supersedes the
earlier local-only boundary in [the correction report](P2_REPAIR_CORRECTIONS_20261015.md).

## Source and release

- Compiled clean source: `f5aa76f464962ce6646ba32c66498894ab5684d8`.
- Application changes: `dd127acf1000c79a20a578a0c651644f15905f86`.
- Workspace entry-point containment: `125e98e258c8165b8fdf48c48a21bb466c85137f`.
- Deployment: `dpl_8jq9UDFU1QCwgFnwmVbacRzb3Mg9`, READY.
- [Immutable deployment](https://yorks-r35-pwhm71bae-sajid-alis-projects-0ec775a2.vercel.app).
- Main JavaScript SHA-256: `aa4f1a7b017ba190f076b081824e081f3d3d74783449385745a041ff6357aa6f`.
- Main JavaScript: 10,054,803 bytes; startup gzip 2,897,314 / 2,900,000 bytes.

This releases manual original-key status recovery, safe expired-upload renewal,
and receipt-first outcome reads with separate optional screen hydration.
It also includes removal of the identified hidden workspace loader and disguised
font asset. That containment is not a host-wide compromise assessment.

## Database deployment

Applied the exact reviewed SQL to dedicated staging, then production
`czykuksmlwswjsgotrpo`, before web promotion:

| Local migration | Production ledger |
|---|---|
| `20261015143625_renew_expired_document_upload_intents.sql` | `20261015204237` |
| `20261015143651_material_workflow_receipt_first_view_hydration.sql` | `20261015204240` |

Remote timestamps are assigned by the migration service. Both environments have
matching definitions for all three affected functions. Each retains SECURITY
DEFINER, empty search_path, authenticated execution and no anonymous execution.
The replaced outcome function was backed up privately before migration.
No business data, receipts, keys, object paths or history were replaced.

Security advisors report no ERROR-level findings. Existing advisory categories
remain: deny-by-default RLS tables without direct policies, intentionally exposed
authenticated SECURITY DEFINER RPCs, two anonymous RPC warnings and disabled
[leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
This release does not claim to resolve those unrelated advisory categories.

## Verification

The unchanged application code retains the full local acceptance evidence:
2,808 Flutter tests (four retained skips), clean analyzer, 4,638 database assertions
across 137 files, CI web build and ephemeral-signed APK. The APK is a verification
artifact, not an Android distribution release. See the correction report for
upload lock races, expiry/restart, slow-projection and manual-recovery tests.

Fresh production verification:

- Production web build passed startup budget.
- Compiled production backend and clean source stamp verified; staging and CI
  backend references absent; no embedded service-role JWT.
- Isolated artifact contains build/web only; source checkout was not uploaded.
- Candidate passed all 28 route/bootstrap/deferred-asset hash checks.
- Promoted that exact candidate; canonical production passed all 28 checks.
- Canonical deployment lookup resolves to the READY deployment above.
- Signed-in Admin Material Requests list and existing request detail rendered,
  including material table, quantity history and Procurement sections. No refresh
  retry was needed. This was read-only; no real approval, dispatch or upload was
  performed as a smoke test.
- Initial Vercel upload returned Not authorized. Account and project access were
  verified, retry succeeded, and candidate/canonical hashes established the final
  release independently of that failed attempt.

Evidence: [release metadata](evidence/p2-production-20261016/release.json),
[candidate checks](evidence/p2-production-20261016/candidate.jsonl),
[canonical checks](evidence/p2-production-20261016/canonical.jsonl).

Physical-device failure injection, extended soak and named-persona production
workflow execution were not performed. Existing historical UAT exceptions remain
unchanged. The prior transient MR-detail read incident is not asserted to be
permanently eliminated by a successful smoke check.

## Rollback and preservation

Retained prior deployment: `dpl_AYg9ywdQzdZSNCsyhZ6CXC6hJSKJ`,
[prior immutable site](https://yorks-r35-g924bznxr-sajid-alis-projects-0ec775a2.vercel.app).
Promote it to roll back the web client if required. Keep both additive RPCs and
the receipt-first outcome contract: the prior P0 client already accepts confirmed
receipts with null optional projections. Do not delete upload intents, receipts,
versions or audit records. Do not reintroduce the hidden workspace loader.

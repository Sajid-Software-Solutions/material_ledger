# Procurement production release — 9 October 2026

Owner authorization: “go ahead and update the production”. This supersedes the
earlier staging-only scope for the reviewed Procurement work.

## Scope and source

- Source: `7177d887ec270780cb7802cb1c46c8a2050f865b`, clean before build.
- Includes the [workspace and recovery implementation](PROCUREMENT_IMPLEMENTATION_20261008.md)
  and [quantity, sourcing, numbering and presentation refinements](PROCUREMENT_SIMPLIFICATION_20261009.md).
- Requested quantities prefill new arrangement rows; saved raw progress wins.
  Shelf/bin is visible, including an explicit missing-location state. Quantity
  states remain derived. Scheduled preparation, automatic Delivery Order numbers,
  private checkpoints and prepared-command recovery are included.
- No unrelated source edits or dependency upgrades were made during release.

## Production backend

Target: `czykuksmlwswjsgotrpo` (existing Yorks production).
Each migration's exact SQL matched the tested staging ledger before application.

| Migration | Production ledger version |
| --- | --- |
| procurement_dispatch_aggregate_stock_guard | 20261008205435 |
| procurement_private_progress | 20261008205440 |
| procurement_dispatch_readiness | 20261008205444 |
| procurement_automatic_delivery_numbers | 20261008205448 |
| procurement_shared_sourcing_progress | 20261008205452 |

Post-deployment checks found all 22 affected function definitions identical to
staging. All five new relations have RLS enabled and deny direct anon and
authenticated SELECT/INSERT/UPDATE/DELETE access. Public progress RPCs deny anon
execution; internal helpers and pre-wrapper functions deny ordinary execution.

`send-push` is active at version 15 with the informational
`arrangement_preparation_completed` event. Existing custom webhook authentication
and `verify_jwt=false` were preserved. Only its reviewed notification catalogue
differs from the previously released runtime source. Actual device delivery was
not exercised by this release.

Security advisers returned no ERROR findings. Existing RPC/security-definer
warnings, RPC-only/no-policy notices and leaked-password protection warning
remain; see [Supabase adviser guidance](https://supabase.com/docs/guides/database/database-linter).

## Client artifact and gates

- Production configuration was read from the existing ignored primary-checkout
  `.r35.env`; secrets were not copied into tracked files or printed.
- Fresh `flutter clean`, `flutter pub get` and production web build passed.
- Main bundle: 9,965,656 bytes; startup gzip: 2,871,266 bytes, below the unchanged
  2,900,000-byte budget. SHA-256:
  `cc3bb48e560363e2eeaee36abfc474ee0cb5832d013247ca5802185cb8bbd489`.
- Compiled client contains the production backend and source stamp, and excludes
  staging and CI backend references.
- Artifact: `/tmp/yorks-procurement-production-20261009`; 62 application files
  plus local Vercel project metadata. Project `yorks-r35`,
  `prj_5jbKMKUBHdccpOCifJCgSOB6snDj`, existing team scope.
- Candidate: <https://yorks-r35-lqyuwmf7e-sajid-alis-projects-0ec775a2.vercel.app>,
  deployment `dpl_CjwmNd7DKHTzSbrwJ4uYXRcLQPb3`, created with `--prod --skip-domain`.
- All 28 candidate route/asset hashes passed before promotion. The same 28 checks
  passed on <https://yorks-r35.vercel.app> afterwards; Vercel inspection confirms
  that the production domain resolves to this Ready deployment.
- Applicable unchanged-code gates passed in the immediately preceding staging
  slice: 2,690 Flutter tests (four retained skips), 3,853 database checks across
  132 files, full analyzer, formatting, desktop/mobile goldens, CI web and
  ephemeral-signed APK. They were not redundantly rerun for a configuration-only
  production build. APK evidence is not a signed native distribution release.

## Live browser verification

The existing Owner/Admin session loaded Material Request Centre and its
In Progress filter. Existing scheduled request `YRA322-MR035` opened in the
released deferred arrangement workspace: its scheduled date, preparation section,
Update team control and requested default of 3250 Meter were visible. Unmatched
lines selected External Supplier. No checkpoint, preparation update, final
arrangement, delivery, dispatch or stock command was submitted.

Browser error logs were empty. Screenshot:
`/tmp/yorks-procurement-production-evidence-20261009/desktop.png`.
The attempted temporary mobile viewport did not affect the inspected background
production tab, so it is not counted as live production mobile evidence. It was
reset. Mobile evidence remains the preceding staging browser and widget gates.
The temporary production tab was closed; the user's staging tab remains open.
This browser check did not exercise a Procurement login or actual push receipt.

## Rollback and preservation

Previous production client: `dpl_BzugN8M8Wawfa2rUU2zhdWLN9EC1`,
<https://yorks-r35-lcw7nigzf-sajid-alis-projects-0ec775a2.vercel.app>.
Restore that client if necessary; retain additive checkpoints, sourcing history,
number counters, audit and stock protection. Never renumber documents, remove
progress or reverse stock movements as a UI rollback. Reconcile any prepared
command before editing it in another client. Prior send-push runtime is the
retained source at `baa4f11`; the catalogue addition is backward compatible.

Release logs are local temporary evidence under `/tmp/procurement-production-*`.
Physical printing, real device push receipt, prolonged concurrent-user usage and
warehouse staff UAT remain outside this deployment smoke check.

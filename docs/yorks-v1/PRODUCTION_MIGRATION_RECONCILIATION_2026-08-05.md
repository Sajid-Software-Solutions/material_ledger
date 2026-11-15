# Production migration reconciliation — 2026-08-05

## Purpose

The linked Yorks production project contained the same R35 schema changes under
different historical migration timestamps. `supabase db push` therefore refused
to apply the project-edit command migration. This record preserves the
one-time reconciliation performed on 2026-08-05.

## Evidence and mapping

Remote migration scripts were fetched before changing history. The following
timestamp-shifted scripts matched the repository versions after normalizing
comments, whitespace and duplicate SQL terminators:

| Remote history | Repository history |
|---|---|
| `20260724034620`, `20260724034752`, `20260724035507` | `20260724090000`, `20260724091000`, `20260724092000` |
| `20260724044248`, `20260724044850`, `20260724050259` | `20260724044059`, `20260724044651`, `20260724050201` |
| `20260802125307` through `20260802125627` | `20260801000000` through `20260802060000` |
| `20260803215204`, `20260803215302`, `20260803215321`, `20260803215356` | `20260803010000`, `20260803192654`, `20260803193504`, `20260803211633` |
| `20260804085200` | `20260804084537` |

The earlier legacy remote chain was represented by the repository's additive
`20260724000000_legacy_collection_prerequisites.sql` baseline. Its purpose is
explicitly to record schema that production already had from the original
schema/manual setup.

Before marking later R35 entries applied, production was queried directly and
confirmed to contain their BOQ constraint, Material Request technical fields,
delivery-order/return functions, lifecycle columns and hardened draft function.
They were therefore history-only repairs, not replayed schema changes.

## Commands applied

1. Remote-only historical markers were marked `reverted`.
2. Their validated repository equivalents, plus the legacy baseline, were
   marked `applied`.
3. The missing `20260805101932_yorks_v1_project_edit_and_safe_archive.sql`
   migration was executed directly through the linked Supabase management API,
   then marked `applied`.
4. The additive/repeatable notification migration was reapplied and recorded
   as `20260805120000` after its former history marker was absent.

The final linked migration list contains a local and remote value for every
tracked migration through `20260805120000`.

## Verification

- `v1_update_project(jsonb, uuid)` and
  `v1_archive_project(jsonb, uuid)` exist in production.
- `authenticated` has execute permission for those two commands.
- `authenticated` has no execute permission for the private
  `v1_can_edit_project(uuid)` authorization helper.
- The project edit/archive migration passed a clean local reset and all local
  pgTAP suites before production application.

## Rollback and future operation

Do not reverse or replay historical schema migrations on production. If a
history marker must be corrected, first fetch and compare the remote script,
then use `supabase migration repair` with an explicit documented mapping. A
product rollback is a redeployment of the prior web build; the project RPCs
are additive and remain backward compatible with that build.

All future schema work must use the repository timestamps and be applied only
after `supabase migration list --linked` confirms the histories remain aligned.

## Later finding (15 November 2026)

Two of the history-only repairs above recorded function changes that never ran
on production. The legacy baseline `20260724000000` was marked applied without
running. Production kept its hand-applied July helpers and grants, and never
received the `app_legacy_*` helpers. `20260803224536` was marked applied after
an existence check of its functions, and its `v1_can_confirm_material_return`
change is missing. Production also holds compacted copies of four function
bodies from the timestamp-shifted scripts. See
[PRODUCTION_FUNCTION_DRIFT_2026-11-15.md](PRODUCTION_FUNCTION_DRIFT_2026-11-15.md)
for the full comparison and the prepared alignment bundle.

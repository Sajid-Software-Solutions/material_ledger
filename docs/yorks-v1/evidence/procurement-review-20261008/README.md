# Procurement audit evidence — 8 October 2026

Source: `2290cf5` (`codex/workforce-mobile-attendance`).

## Focused Flutter baseline

Command:

```bash
flutter test test/yorks_v1_arrangement_test.dart \
  test/yorks_v1_arrangement_layout_test.dart \
  test/yorks_v1_logistics_test.dart \
  test/yorks_v1_logistics_screen_test.dart \
  test/yorks_v1_critical_command_key_store_test.dart \
  test/yorks_v1_dispatch_centre_golden_test.dart \
  test/yorks_v1_delivery_order_action_golden_test.dart \
  test/yorks_v1_logistics_document_service_test.dart
```

Result: **64 passed**, exit 0. This is a focused current-source baseline, not
full-suite, release, production-persona or performance certification.

## Shared-stock dispatch reproduction

[Rollback fixture](shared_stock_repro.sql) uses current Project creation,
request submission/approval, arrangement, dispatch, receipt and replenishment
RPCs, with seeded local actor claims. It runs as the local test database owner,
so it verifies transaction logic, not independent external RLS enforcement.
There are no direct fixture updates to stock balances or reservations.

Executed only against the existing local Docker database:

```bash
docker exec -i supabase_db_material_ledger psql -U postgres -d postgres \
  < docs/yorks-v1/evidence/procurement-review-20261008/shared_stock_repro.sql
```

Local migration ledger: **191** rows through `20261008080029`.
The SHA-256 of the inspected effective `v1_dispatch_materials(jsonb,uuid)`
function definition was `8ddcd663a4a9d68635a988c2ac4a4138efe9deac8fbb4e8e8e77e28320687a15`.

Observed output:

```text
BEGIN
SET
CREATE FUNCTION
CREATE FUNCTION
NOTICE:  BEFORE: on_hand=6.0000, other_request_reserved=4.0000
NOTICE:  AFTER: rejected=f, on_hand=2.0000, other_request_reserved=4.0000
DO
ROLLBACK
```

`rejected=f` means the aggregate overspend was accepted. The expected corrected
behavior is a stock-cap rejection, with on-hand remaining 6 and the competing
reservation remaining 4. The committed effect shown above existed only inside
the test transaction; the final ROLLBACK removed the witness data.

Post-rollback verification:

```text
remaining_audit_projects|0
remaining_audit_items|0
```

This script records a current defect; it is not an automated passing regression
test. Convert it to assertions for the production fix. Also test same-item
Project/Company reservations, decimal quantities, ordinary authenticated callers,
idempotent retries and competing writers.

## Boundaries

- No production or staging transaction was executed by this fixture.
- No migrations, source fixes or deployment were performed in this audit.
- The user screenshot was the Procurement arrangement evidence; the existing
  staging browser session displayed Local Admin during inspection.
- No production prevalence, stock discrepancy or end-to-end Procurement UAT was
  established. The browser viewport override was reset after inspection.

See the [review and plan](../../PROCUREMENT_WORKSPACE_REVIEW_20261008.md).

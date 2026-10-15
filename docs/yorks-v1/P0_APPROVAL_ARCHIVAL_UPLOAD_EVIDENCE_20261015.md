# Approval recovery archival and upload outcome evidence — 15 October 2026

This is local implementation/verification evidence, not a production rollout.
The parent P0 repair owns release lineage, staging and complete acceptance gates.

## Approval cancellation

The incident evidence establishes `57014` inside synchronous private-recovery
archival during approval. It does not identify the production lock holder or
prove that PostgreSQL statement timeout caused that production cancellation.

Source inspection found that every progressed state update runs recovery
archival. Its exact `(draft_id, owner_auth_user_id)` predicate already has the
primary-key index. A concurrent owner recovery delete can lock the private row
while approval owns the normalized request row and waits for recovery cleanup.

The local two-session harness reproduces that mechanism with the original
trigger installed only inside a rolled-back approval transaction:

| Case | Observed result |
|---|---|
| Original trigger, owner delete holds private row for 1.5 seconds | Approval cancelled with `57014` after 772 ms under a 700 ms test statement timeout; `Lock / transactionid`, one blocking PID; no approval audit |
| New trigger, same competing owner delete | Approval confirmed in 89 ms; exactly one approval audit; same-key replay did not add an audit |
| New trigger, private row held for 1.5 seconds | Approval confirmed in 91 ms; contended cleanup worker returned in 72 ms |
| Private sync starts before normalized INSERT/progression | Progression completed in 64 ms; worker deferred while the owner advisory lock was held, then archived the exact input after sync committed |

Times include local Docker/psql overhead. They are not production latency claims.

The migration retains immediate archival when uncontended. The trigger only
tries the existing owner advisory lock, and uses `FOR UPDATE NOWAIT` on the
private row. On lock contention, the same transaction persists a server-only
archival job alongside the progressed request. The committed normalized MR is
the existing editing fence: private sync locks the request before its private
row and rejects normalized IDs, normalized Save rejects non-draft states, and
private recovery reads/list exclude progressed records.

The cron worker processes at most 50 jobs per call, checks its one-second budget
between jobs, uses `SKIP LOCKED` and nonblocking owner/private locks, rechecks the
owner and progressed request fence, and preserves failures as durable jobs with
bounded backoff. Payloads move verbatim into the existing archive. Missing or
wrong-owner fences cannot erase input. Employee roles cannot read the job table
or execute the worker. Duplicate jobs do not duplicate archive snapshots.

Repeatable local commands, with the seeded repair database running:

```bash
python3 tool/test_material_request_approval_recovery_concurrency.py \
  --container supabase_db_material_ledger
docker exec -i supabase_db_material_ledger psql -X -Atq -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < tool/profile_material_request_recovery_archival.sql
```

The race harness commits uniquely named synthetic fixtures. Reset the isolated
local database before aggregate-sensitive whole-suite tests. The query profiler
rolls back its 10,001 private rows. Its exact target used a primary-key index scan
(0.016 ms execution in the observed run), and a 900 KB unknown JSON field archived
in 0.899 ms, preserved exactly. This fixture does not support a missing-index or
large-payload explanation for the production incident.

Verification: focused archival pgTAP **21/21 passed**; local Supabase security
advisors at warning level reported no issues. No remote records were mutated.

## Upload truth and recovery

The existing repository validated the finalizer receipt, then awaited an
optional workspace read. That read could incorrectly make an acknowledged
document version appear failed. The repair retains the exact document/key/
revision receipt and reports `YorksV1CommittedViewUnavailable` when a later list
read or local journal cleanup fails. Upload analytics count that mutation as
successful and retain a separate refresh/cleanup diagnostic.

An ambiguous/malformed finalizer response gets one authorized readback using the
same prepare key and unchanged payload. It never starts another immutable upload
or version merely to check status. Reconciliation errors preserve the original
uncertainty. Finalizer 5xx failures are transport/backend uncertainty rather than
being mislabeled as a definitive version conflict.

General uploads now retain actor/backend-scoped recovery metadata through the
existing browser Web Locks/native serialized-storage boundary: file name, MIME,
size, content hash, key, entity/classification and an opaque payload fingerprint.
No file bytes, Storage path, notes or commercial payload are stored. Reselecting
the same file after reload uses the original key; changed contents cannot replace
an unresolved intent. Corrupt metadata is preserved and fails closed. Existing
project setup continues to own its original durable key/hash and bypasses the
generic journal rather than substituting that identity.

Project setup marks a file Ready after an authoritative receipt even if the
document list is unavailable. A failed local acknowledgement preserves Ready in
memory, records the local recovery issue, and repairs that exact journal receipt
before later cleanup without another upload. Rental, Supplier, Accounts and
legacy project upload consumers recognize the committed/degraded result.

The project Documents view shows the actual file name and byte size with truthful
indeterminate progress, and offers exact-file reselection for pending outcomes.
The status panel consumes layout space rather than covering the final document
row. Desktop 1366 px and phone 360 px goldens are in `test/goldens/p0_upload/`.

Focused upload/coordinator/supplier/UI checks: **99 tests passed**, scoped
analyzer clean. Tests cover lost/malformed receipts, automatic same-key readback,
post-commit view failure, journal acknowledgement failure, reload, mismatched
contents, owner/backend isolation, corrupt/unknown metadata, 10/20 MiB interrupted
synthetic transfers and original-key retry. The existing controlled-document cap
is **20 MiB**; a 50 MiB selection is explicitly tested as rejected. The cap was not
raised. These are synthetic transport/widget tests, not real throttled browser
transfers or physical Windows/Android/iOS network tests. The native storage
adapter serializes within one app process; independent native processes were not
tested or claimed to have browser Web Locks guarantees.

## Ordering, rollback and observation

Apply the archival migration before the client candidate. Existing recovery RPC
signatures and old-client terminal guards remain compatible. All new metadata
stays device-local, scoped to the original owner/backend.

Rollback must retain the archival queue, worker, existing archive and editing
fences until jobs have drained; never delete pending obligations or resurrect
private snapshots. A client rollback must preserve its recovery storage keys.

Routine low-cost server verification uses the indexed queue and cron run status,
not raw-log polling:

```sql
select count(*) as pending,
       count(*) filter (where attempt_count > 0) as retrying,
       min(enqueued_at) as oldest_pending,
       max(attempt_count) as largest_attempt_count
from public.v1_material_request_recovery_archival_jobs;
select status, start_time, end_time
from cron.job_run_details
where jobid = (select jobid from cron.job
  where jobname='yorks-v1-mr-recovery-archival')
order by start_time desc limit 3;
```

Correlate new command outcome diagnostics with server audit/receipts; retain
historical failure events. A successful local reproduction/fix does not establish
the original production lock holder or guarantee that every future cancellation
has the same cause.

-- pg_cron keeps a row in cron.job_run_details for every run and never purges
-- it. Two jobs run every minute (push outbox, MR recovery archival), so this
-- history had grown to about 29 MB, the largest object in a 150 MB database
-- whose server has roughly 400 MB of RAM.
--
-- Keep seven days of run history for diagnosis; delete older rows once a day.
-- This is operational scheduler metadata only: no application record, audit
-- event or idempotency key is touched. Additive and repeatable (named
-- schedule). Rollback: select cron.unschedule('yorks-cron-run-history-retention').

create or replace function public.v1_purge_cron_run_history()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from cron.job_run_details
  where end_time < now() - interval '7 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.v1_purge_cron_run_history()
from public, anon, authenticated;
grant execute on function public.v1_purge_cron_run_history() to service_role;

do $$
begin
  -- Named schedule is idempotent. 03:17 UTC avoids the top of the hour, when
  -- the hourly rental notifications job runs.
  perform cron.schedule(
    'yorks-cron-run-history-retention', '17 3 * * *',
    'select public.v1_purge_cron_run_history();');
end;
$$;

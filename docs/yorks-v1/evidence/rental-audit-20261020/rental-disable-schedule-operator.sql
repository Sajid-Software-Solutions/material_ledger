-- OPERATOR ONLY. Verify the explicitly approved project/host first.
-- Stops new rental generation and suppresses queued rental delivery without
-- changing shared push controls or deleting business/inbox/outbox/ledger rows.
-- A provider send already in flight may finish; inspect health after drain.
begin;
update public.v1_rental_notification_control set enabled=false,external_push_enabled=false where id;
do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='yorks-rental-notifications';
  if v_job is not null then perform cron.alter_job(v_job,active:=false); end if;
end; $$;
commit;
select * from public.v1_rental_notification_control;
select jobname,schedule,active from cron.job where jobname='yorks-rental-notifications';
select public.v1_push_backend_health();

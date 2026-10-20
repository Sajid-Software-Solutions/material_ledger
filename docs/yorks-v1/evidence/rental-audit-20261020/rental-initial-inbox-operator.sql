-- OPERATOR ONLY. Executed once by the coordinating production release on
-- 2026-10-20 after the authorized 52-row source import; do not rerun as setup.
-- First verify the explicitly approved project/host and reviewed migration
-- ledger/artifact. Run only after migrations, source import and staging pass.
-- First evaluation retains milestones in-app, with only the legitimate daily
-- completeness digest eligible for external delivery (one per active Admin).
-- Verify the imported source cohort fits the 100-event run; if it does not,
-- stop before activation and arrange separately reviewed inbox-only catchup.
select public.v1_push_backend_health();
select * from public.v1_rental_notification_control;
select jobid,jobname,schedule,active from cron.job where jobname='yorks-rental-notifications';
begin;
do $$ begin
  perform 1 from public.v1_rental_notification_control where id for update;
  if not exists(select 1 from public.v1_rental_notification_control
      where id and not enabled and not external_push_enabled and last_success_at is null)
    or (select count(*) from cron.job where jobname='yorks-rental-notifications' and not active)<>1 then
    raise exception 'RENTAL_INITIAL_REQUIRES_DISABLED_CONTROLS';
  end if;
  if exists(select 1 from public.v1_push_transport_control
      where id and (operator_paused or circuit_open_until is not null)) then
    raise exception 'RENTAL_INITIAL_REQUIRES_HEALTHY_SHARED_PUSH';
  end if;
  if (select count(*) from public.v1_rental_notification_candidates() c cross join public.v1_profiles p
      where public.v1_permission_exact_role(p.auth_user_id)='admin')>100 then
    raise exception 'RENTAL_INITIAL_COHORT_REQUIRES_REVIEWED_INBOX_ONLY_CATCHUP';
  end if;
end; $$;
update public.v1_rental_notification_control set enabled=true,external_push_enabled=true where id;
select public.v1_run_rental_notifications();
-- Keep external delivery enabled for the fresh digest while cron remains off.
update public.v1_rental_notification_control set enabled=false where id;
commit;
-- Counts only. No tenant, contact, bank or rent amount output.
select e.event_code,count(*) as retained_inbox_only from public.v1_rental_notification_events e
  where not e.external_push_eligible group by e.event_code order by e.event_code;
select count(*) as remaining_current_recipient_milestones
from public.v1_rental_notification_candidates() c cross join public.v1_profiles p
where public.v1_permission_exact_role(p.auth_user_id)='admin'
and not exists(select 1 from public.v1_rental_notification_events e
  where e.recipient_auth_user_id=p.auth_user_id and e.event_code=c.event_code
    and e.obligation_id=c.obligation_id and e.milestone=c.milestone);

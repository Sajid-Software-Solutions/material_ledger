-- OPERATOR ONLY. Not executed in production by this audit.
-- Run as a separate, reviewed release action after initial inbox acceptance.
-- Verify approved project/host, candidate artifact, migration ledger, actual
-- Admin inbox count/routes and current shared-push health before executing.
select public.v1_push_backend_health();
select * from public.v1_rental_notification_control;
select jobid,jobname,schedule,active from cron.job where jobname='yorks-rental-notifications';
begin;
do $$ begin
  perform 1 from public.v1_rental_notification_control where id for update;
  if not exists(select 1 from public.v1_rental_notification_control
      where id and not enabled and external_push_enabled and last_success_at is not null)
    or (select count(*) from cron.job where jobname='yorks-rental-notifications' and not active)<>1 then
    raise exception 'RENTAL_ACTIVATION_REQUIRES_DISABLED_CONTROLS';
  end if;
  if exists(select 1 from public.v1_push_transport_control
      where id and (operator_paused or circuit_open_until is not null)) then
    raise exception 'RENTAL_ACTIVATION_REQUIRES_HEALTHY_SHARED_PUSH';
  end if;
  if exists(select 1 from public.v1_rental_notification_candidates() c cross join public.v1_profiles p
    where public.v1_permission_exact_role(p.auth_user_id)='admin'
    and not exists(select 1 from public.v1_rental_notification_events e
      where e.recipient_auth_user_id=p.auth_user_id and e.event_code=c.event_code
        and e.obligation_id=c.obligation_id and e.milestone=c.milestone)) then
    raise exception 'RENTAL_INITIAL_CURRENT_COHORT_NOT_DRAINED';
  end if;
  update public.v1_rental_notification_control set enabled=true,external_push_enabled=true where id;
  perform cron.alter_job((select jobid from cron.job where jobname='yorks-rental-notifications'),active:=true);
end; $$;
commit;
-- Only newly generated future milestones inherit external_push_eligible=true.
-- Initial ledger rows stay false. No historical inbox/outbox is requeued.
select * from public.v1_rental_notification_control;
select jobname,schedule,active from cron.job where jobname='yorks-rental-notifications';
select public.v1_push_backend_health();

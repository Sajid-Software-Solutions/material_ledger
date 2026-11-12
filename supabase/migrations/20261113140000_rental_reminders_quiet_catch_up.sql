-- Rental reminders: a new recipient catches up quietly.
--
-- When someone newly receives rental reminders (PR on 12 November 2026, or
-- any future Admin), the hourly job used to deliver every reminder that was
-- already open, as separate push alerts in one burst. The first rollout
-- already avoided that for the original Admins (initial_evaluation_complete);
-- this applies the same rule per recipient:
--
--   * until a recipient is caught up, their existing reminders are written to
--     the inbox already marked as seen and are never pushed;
--   * a recipient is caught up once every current reminder is recorded for
--     them (the 100-row batch cap can take more than one run);
--   * after that, only genuinely new reminders alert them, as before.
--
-- Recipients who already hold rental reminders are caught up now, so nothing
-- changes for current Admins or PR. No existing notification is changed.
--
-- Data preservation: one additive table; the job function is replaced with
-- the live definition plus the catch-up rule. Rollback: re-create
-- v1_run_rental_notifications from 20261020115421 with the Admin-or-PR
-- recipient test from 20261112130000; the table may stay.

begin;

create table if not exists public.v1_rental_notification_recipients (
  recipient_auth_user_id uuid primary key
    references public.v1_profiles (auth_user_id) on delete restrict,
  first_seen_at timestamptz not null default clock_timestamp(),
  caught_up_at timestamptz
);
alter table public.v1_rental_notification_recipients enable row level security;
revoke all on table public.v1_rental_notification_recipients
  from public, anon, authenticated;
grant select on table public.v1_rental_notification_recipients to service_role;

-- Everyone who already receives rental reminders is caught up: past
-- recipients in the ledger and every current Admin or PR.
insert into public.v1_rental_notification_recipients (
  recipient_auth_user_id, first_seen_at, caught_up_at
)
select e.recipient_auth_user_id, min(e.created_at), clock_timestamp()
from public.v1_rental_notification_events e
group by e.recipient_auth_user_id
on conflict (recipient_auth_user_id) do nothing;
insert into public.v1_rental_notification_recipients (
  recipient_auth_user_id, caught_up_at
)
select p.auth_user_id, clock_timestamp()
from public.v1_profiles p
where public.v1_permission_exact_role(p.auth_user_id) in ('admin', 'pr')
on conflict (recipient_auth_user_id) do nothing;

create or replace function public.v1_run_rental_notifications()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_enabled boolean; v_external boolean; v_initial_complete boolean; v_row record; v_id uuid;
  v_count integer:=0; v_external_count integer:=0; v_quiet_count integer:=0; v_event text;
  v_eligible boolean; v_quiet boolean;
  v_date date:=public.v1_rental_business_date(); v_now timestamptz:=statement_timestamp();
begin
  select enabled,external_push_enabled,initial_evaluation_complete into v_enabled,v_external,v_initial_complete
    from public.v1_rental_notification_control where id for update;
  if not coalesce(v_enabled,false) then return jsonb_build_object('enabled',false,'emitted',0); end if;

  -- Register anyone who now receives rental reminders. The very first
  -- recipients of a new installation are not "joining late".
  insert into public.v1_rental_notification_recipients(recipient_auth_user_id,first_seen_at,caught_up_at)
  select p.auth_user_id,v_now,
    case when not exists(select 1 from public.v1_rental_notification_recipients) then v_now end
  from public.v1_profiles p
  where public.v1_permission_exact_role(p.auth_user_id) in ('admin','pr')
  on conflict (recipient_auth_user_id) do nothing;

  for v_row in
    select c.*,p.auth_user_id recipient,r.caught_up_at
      from public.v1_rental_notification_candidates() c
      cross join public.v1_profiles p
      join public.v1_rental_notification_recipients r on r.recipient_auth_user_id=p.auth_user_id
      where public.v1_permission_exact_role(p.auth_user_id) in ('admin','pr')
      and not exists(select 1 from public.v1_rental_notification_events e
        where e.recipient_auth_user_id=p.auth_user_id and e.event_code=c.event_code
          and e.obligation_id=c.obligation_id and e.milestone=c.milestone)
      order by case c.event_code when 'rental_cheque_returned' then 0
        when 'rental_rent_overdue' then 1 when 'rental_lease_expired' then 2
        when 'rental_cheque_due' then 3 when 'rental_lease_notice_due' then 4 else 5 end,
        c.obligation_id,p.auth_user_id limit 100
  loop
    v_event:=case v_row.event_code
      when 'rental_completeness_review' then 'rental_completeness_review'
      when 'rental_lease_notice_due' then 'rental_lease_notice_due'
      when 'rental_lease_expired' then 'rental_lease_expired'
      when 'rental_cheque_due' then 'rental_cheque_due'
      when 'rental_cheque_returned' then 'rental_cheque_returned'
      when 'rental_rent_due' then 'rental_rent_due'
      when 'rental_rent_overdue' then 'rental_rent_overdue' end;
    v_id:=gen_random_uuid();
    -- A recipient joining after the first rollout catches up quietly: their
    -- existing reminders are already seen in the inbox and never pushed.
    v_quiet:=v_initial_complete and v_row.caught_up_at is null;
    -- First source evaluation can notify each Admin once about completeness,
    -- while retained current lease/cheque/debt milestones remain inbox-only.
    v_eligible:=v_external and not v_quiet
      and (v_initial_complete or v_event='rental_completeness_review');
    insert into public.v1_rental_notification_events(notification_id,recipient_auth_user_id,event_code,
      obligation_id,property_id,milestone,business_date,item_count,external_push_eligible,created_at)
      values(v_id,v_row.recipient,v_row.event_code,v_row.obligation_id,v_row.property_id,
        v_row.milestone,v_date,v_row.item_count,v_eligible,v_now) on conflict do nothing;
    if found then
      insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id,created_at,seen_at)
      values(v_id,v_row.recipient,v_event,
        case when v_row.property_id is null then 'rental_portfolio' else 'rental_property' end,
        coalesce(v_row.property_id,v_row.recipient),v_now,
        case when v_quiet then v_now end);
      v_count:=v_count+1;
      if v_eligible then v_external_count:=v_external_count+1; end if;
      if v_quiet then v_quiet_count:=v_quiet_count+1; end if;
    end if;
  end loop;

  -- A recipient is caught up once every current reminder is recorded for them.
  update public.v1_rental_notification_recipients r set caught_up_at=v_now
  where r.caught_up_at is null
    and not exists(
      select 1 from public.v1_rental_notification_candidates() c
      where not exists(select 1 from public.v1_rental_notification_events e
        where e.recipient_auth_user_id=r.recipient_auth_user_id and e.event_code=c.event_code
          and e.obligation_id=c.obligation_id and e.milestone=c.milestone));

  -- A successful 100-row batch can leave old obligations unprocessed. Remain
  -- in initial suppression until the current cohort is completely represented
  -- in the durable ledger. Fresh obligations only gain normal eligibility after
  -- that boundary; no old inbox-only row is modified or replayed.
  if not v_initial_complete then
    v_initial_complete:=not exists(
      select 1 from public.v1_rental_notification_candidates() c cross join public.v1_profiles p
      where public.v1_permission_exact_role(p.auth_user_id) in ('admin','pr')
      and not exists(select 1 from public.v1_rental_notification_events e
        where e.recipient_auth_user_id=p.auth_user_id and e.event_code=c.event_code
          and e.obligation_id=c.obligation_id and e.milestone=c.milestone));
  end if;
  update public.v1_rental_notification_control set last_success_at=v_now,last_business_date=v_date,
    last_emitted_count=v_count,initial_evaluation_complete=v_initial_complete where id;
  return jsonb_build_object('enabled',true,'external_push_enabled',v_external,'external_push_candidates',v_external_count,
    'quiet_catch_up',v_quiet_count,
    'initial_evaluation_complete',v_initial_complete,'business_date',v_date,'timezone','Asia/Dubai','emitted',v_count);
end; $$;
revoke all on function public.v1_run_rental_notifications() from public,anon,authenticated;
grant execute on function public.v1_run_rental_notifications() to service_role;

commit;

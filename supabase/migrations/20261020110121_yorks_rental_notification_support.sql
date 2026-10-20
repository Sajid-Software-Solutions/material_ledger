-- Additive rental attention, exact active-Admin recipients, bounded stable
-- milestone identities and the existing fenced push outbox. No tenant messages.
-- Existing business rows/history are retained. Rollback: disable this producer
-- and its cron job; retain notification/deduplication evidence. Defaults OFF.
begin;

create table if not exists public.v1_rental_notification_control (
  id boolean primary key default true check(id),
  enabled boolean not null default false,
  external_push_enabled boolean not null default false,
  last_success_at timestamptz,
  last_business_date date,
  last_emitted_count integer not null default 0 check(last_emitted_count between 0 and 100)
);
insert into public.v1_rental_notification_control(id) values(true) on conflict do nothing;
create table if not exists public.v1_rental_notification_events (
  notification_id uuid primary key references public.v1_notifications(id) on delete restrict,
  recipient_auth_user_id uuid not null references public.v1_profiles(auth_user_id) on delete restrict,
  event_code text not null check(event_code in ('rental_completeness_review',
    'rental_lease_notice_due','rental_lease_expired','rental_cheque_due',
    'rental_cheque_returned','rental_rent_due','rental_rent_overdue')),
  obligation_id uuid not null,
  property_id uuid references public.v1_rental_properties(id) on delete restrict,
  milestone text not null check(length(milestone) between 1 and 80),
  business_date date not null,
  item_count integer not null default 1 check(item_count > 0),
  external_push_eligible boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  unique(recipient_auth_user_id,event_code,obligation_id,milestone)
);
alter table public.v1_rental_notification_control add column if not exists external_push_enabled boolean not null default false;
alter table public.v1_rental_notification_events add column if not exists external_push_eligible boolean not null default false;
alter table public.v1_rental_notification_events drop constraint if exists v1_rental_notification_events_event_code_check;
alter table public.v1_rental_notification_events add constraint v1_rental_notification_events_event_code_check
  check(event_code in('rental_completeness_review','rental_lease_notice_due','rental_lease_expired',
    'rental_cheque_due','rental_cheque_returned','rental_rent_due','rental_rent_overdue'));
alter table public.v1_rental_notification_control enable row level security;
alter table public.v1_rental_notification_events enable row level security;
revoke all on public.v1_rental_notification_control,public.v1_rental_notification_events from public,anon,authenticated;
grant select,update on public.v1_rental_notification_control to service_role;
grant select on public.v1_rental_notification_events to service_role;

create or replace function public.v1_rental_notification_candidates()
returns table(event_code text,obligation_id uuid,property_id uuid,milestone text,item_count integer)
language sql stable security definer set search_path='' as $$
  with day as(select public.v1_rental_business_date() today), incomplete as(
    select count(*)::integer n from public.v1_rental_properties p
    where not p.is_archived and cardinality(public.v1_rental_missing_fields_internal(p.id))>0
  )
  select 'rental_completeness_review'::text,'00000000-0000-4000-8000-000000000000'::uuid,
    null::uuid,day.today::text,incomplete.n from day cross join incomplete where incomplete.n>0
  union all
  select 'rental_lease_notice_due',l.id,p.id,(l.lease_end-l.renewal_notice_days)::text,1
    from public.v1_rental_leases l join public.v1_rental_properties p on p.id=l.property_id cross join day
    where not p.is_archived and l.is_current and l.contract_status in('active','notice_due','expired')
      and day.today between l.lease_end-l.renewal_notice_days and l.lease_end
  union all
  select 'rental_lease_expired',l.id,p.id,l.lease_end::text,1
    from public.v1_rental_leases l join public.v1_rental_properties p on p.id=l.property_id cross join day
    where not p.is_archived and l.is_current and l.contract_status in('active','notice_due','expired')
      and day.today>l.lease_end
  union all
  select 'rental_cheque_due',c.id,p.id,c.cheque_date::text,1
    from public.v1_rental_cheques c join public.v1_rental_properties p on p.id=c.property_id cross join day
    where not p.is_archived and c.status in('scheduled','received','deposited') and c.cheque_date<=day.today
  union all
  select 'rental_cheque_returned',c.id,p.id,coalesce((
      select a.id::text from public.v1_audit_events a where a.entity_type='rental_cheque'
        and a.entity_id=c.id and a.event_type='rental_cheque_status_changed'
        and a.after_data->>'status'='returned' order by a.occurred_at desc,a.id desc limit 1
    ),'initial_returned'),1
    from public.v1_rental_cheques c join public.v1_rental_properties p on p.id=c.property_id
    where not p.is_archived and c.status='returned'
  union all
  select 'rental_rent_due',r.id,p.id,r.due_date::text,1
    from public.v1_rental_periods r join public.v1_rental_leases l on l.id=r.lease_id
    join public.v1_rental_properties p on p.id=l.property_id cross join day
    where not p.is_archived and l.billing_start is not null
      and r.due_date>=l.billing_start and day.today between r.due_date and r.due_date+l.grace_period_days
      and r.amount_due>coalesce((select sum(x.amount_received) from public.v1_rental_receipts x where x.period_id=r.id),0)
  union all
  select 'rental_rent_overdue',r.id,p.id,(r.due_date+l.grace_period_days)::text,1
    from public.v1_rental_periods r join public.v1_rental_leases l on l.id=r.lease_id
    join public.v1_rental_properties p on p.id=l.property_id cross join day
    where not p.is_archived and l.billing_start is not null
      and r.due_date>=l.billing_start and day.today>r.due_date+l.grace_period_days
      and r.amount_due>coalesce((select sum(x.amount_received) from public.v1_rental_receipts x where x.period_id=r.id),0)
$$;
revoke all on function public.v1_rental_notification_candidates() from public,anon,authenticated,service_role;

-- Ledger first, then inbox, in one transaction: the inbox trigger can safely
-- resolve its protected obligation immediately. The FK is deferred for this.
alter table public.v1_rental_notification_events drop constraint if exists v1_rental_notification_events_notification_id_fkey;
alter table public.v1_rental_notification_events add constraint v1_rental_notification_events_notification_id_fkey
  foreign key(notification_id) references public.v1_notifications(id) on delete restrict deferrable initially deferred;
create or replace function public.v1_run_rental_notifications()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_enabled boolean; v_external boolean; v_has_run boolean; v_row record; v_id uuid;
  v_count integer:=0; v_external_count integer:=0; v_event text; v_eligible boolean;
  v_date date:=public.v1_rental_business_date(); v_now timestamptz:=statement_timestamp();
begin
  select enabled,external_push_enabled,last_success_at is not null into v_enabled,v_external,v_has_run
    from public.v1_rental_notification_control where id for update;
  if not coalesce(v_enabled,false) then return jsonb_build_object('enabled',false,'emitted',0); end if;
  for v_row in
    select c.*,p.auth_user_id recipient from public.v1_rental_notification_candidates() c
      cross join public.v1_profiles p
      where public.v1_permission_exact_role(p.auth_user_id)='admin'
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
    -- First source evaluation can notify each Admin once about completeness,
    -- while retained current lease/cheque/debt milestones remain inbox-only.
    v_eligible:=v_external and (v_has_run or v_event='rental_completeness_review');
    insert into public.v1_rental_notification_events(notification_id,recipient_auth_user_id,event_code,
      obligation_id,property_id,milestone,business_date,item_count,external_push_eligible,created_at)
      values(v_id,v_row.recipient,v_row.event_code,v_row.obligation_id,v_row.property_id,
        v_row.milestone,v_date,v_row.item_count,v_eligible,v_now) on conflict do nothing;
    if found then
      insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id,created_at)
      values(v_id,v_row.recipient,v_event,
        case when v_row.property_id is null then 'rental_portfolio' else 'rental_property' end,
        coalesce(v_row.property_id,v_row.recipient),v_now);
      v_count:=v_count+1;
      if v_eligible then v_external_count:=v_external_count+1; end if;
    end if;
  end loop;
  update public.v1_rental_notification_control set last_success_at=v_now,last_business_date=v_date,last_emitted_count=v_count where id;
  return jsonb_build_object('enabled',true,'external_push_enabled',v_external,'external_push_candidates',v_external_count,
    'business_date',v_date,'timezone','Asia/Dubai','emitted',v_count);
end; $$;
revoke all on function public.v1_run_rental_notifications() from public,anon,authenticated;
grant execute on function public.v1_run_rental_notifications() to service_role;

-- The initial cohort is durable inbox-only. Snapshot the decision in each
-- immutable-by-grants ledger row, so later enablement cannot replay it. A
-- BEFORE trigger returning null is a successful suppressed INSERT, including
-- the existing global enqueue's INSERT ... ON CONFLICT path. Other modules
-- and user preferences retain their existing behavior. The ledger itself is
-- the explicit suppression evidence; no retryable outbox job is manufactured.
create or replace function public.v1_rental_gate_push_outbox()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from public.v1_rental_notification_events e
    where e.notification_id=new.notification_id and not e.external_push_eligible) then return null; end if;
  return new;
end; $$;
revoke all on function public.v1_rental_gate_push_outbox() from public,anon,authenticated,service_role;
drop trigger if exists v1_rental_push_outbox_gate on public.v1_notification_push_outbox;
create trigger v1_rental_push_outbox_gate before insert on public.v1_notification_push_outbox
  for each row execute function public.v1_rental_gate_push_outbox();

-- Preserve all existing module behavior through narrowly scoped wrappers.
do $$ begin
  if to_regprocedure('public.v1_push_notification_entity_allowed_before_rental(public.v1_notifications)') is null then
    alter function public.v1_push_notification_entity_allowed(public.v1_notifications) rename to v1_push_notification_entity_allowed_before_rental;
    alter function public.v1_notification_module_route(public.v1_notifications) rename to v1_notification_module_route_before_rental;
    alter function public.v1_notification_record_label(public.v1_notifications) rename to v1_notification_record_label_before_rental;
  end if;
end; $$;
revoke all on function public.v1_push_notification_entity_allowed_before_rental(public.v1_notifications),
  public.v1_notification_module_route_before_rental(public.v1_notifications),
  public.v1_notification_record_label_before_rental(public.v1_notifications) from public,anon,authenticated,service_role;

create or replace function public.v1_rental_notification_matches(n public.v1_notifications)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(public.v1_permission_exact_role(n.recipient_auth_user_id)='admin',false)
    and exists(select 1 from public.v1_rental_notification_events e
      where e.notification_id=n.id and e.recipient_auth_user_id=n.recipient_auth_user_id
      and e.event_code=n.event_code and n.project_id is null
      and ((e.property_id is null and n.entity_type='rental_portfolio' and n.entity_id=e.recipient_auth_user_id)
        or(e.property_id=n.entity_id and n.entity_type='rental_property')))
$$;
create or replace function public.v1_push_notification_entity_allowed(n public.v1_notifications)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if n.event_code like 'rental_%' or n.entity_type in('rental_property','rental_portfolio') then
    return public.v1_rental_notification_matches(n)
      and exists(select 1 from public.v1_rental_notification_control where id and external_push_enabled)
      and exists(
      select 1 from public.v1_rental_notification_events e
      join public.v1_rental_notification_candidates() c on c.event_code=e.event_code
        and c.obligation_id=e.obligation_id and c.milestone=e.milestone
        and c.property_id is not distinct from e.property_id
      where e.notification_id=n.id and e.external_push_eligible);
  end if;
  return public.v1_push_notification_entity_allowed_before_rental(n);
end; $$;
create or replace function public.v1_notification_module_route(n public.v1_notifications)
returns text language plpgsql stable security definer set search_path='' as $$
begin
  if n.event_code like 'rental_%' or n.entity_type in('rental_property','rental_portfolio') then
    if not public.v1_rental_notification_matches(n) then return null; end if;
    return case when n.entity_type='rental_portfolio' then '/rentals' else '/rentals/'||n.entity_id::text end;
  end if;
  return public.v1_notification_module_route_before_rental(n);
end; $$;
create or replace function public.v1_notification_record_label(n public.v1_notifications)
returns text language plpgsql stable security definer set search_path='' as $$
declare v_label text;
begin
  if n.event_code like 'rental_%' or n.entity_type in('rental_property','rental_portfolio') then
    if auth.uid() is distinct from n.recipient_auth_user_id or not public.v1_rental_notification_matches(n) then return null; end if;
    if n.entity_type='rental_portfolio' then
      select e.item_count::text into v_label from public.v1_rental_notification_events e where e.notification_id=n.id;
    else
      select p.unit_code into v_label from public.v1_rental_properties p where p.id=n.entity_id;
    end if;
    return nullif(left(btrim(regexp_replace(v_label,'[[:cntrl:]]',' ','g')),180),'');
  end if;
  return public.v1_notification_record_label_before_rental(n);
end; $$;
revoke all on function public.v1_rental_notification_matches(public.v1_notifications),
  public.v1_push_notification_entity_allowed(public.v1_notifications),
  public.v1_notification_module_route(public.v1_notifications),
  public.v1_notification_record_label(public.v1_notifications) from public,anon,authenticated,service_role;

-- Registration is present but inactive. Release owners must separately enable
-- both controls only after staging acceptance. Polling does not repeat keys.
do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='yorks-rental-notifications' limit 1;
  if v_job is null then
    v_job:=cron.schedule('yorks-rental-notifications','0 * * * *','select public.v1_run_rental_notifications();');
    perform cron.alter_job(v_job,active:=false);
  end if;
end; $$;
commit;

-- Review correction: keep the entire bounded initial cohort inbox-only,
-- and align the protected Urgent inbox filter with rental overdue semantics.
-- Additive and idempotent: existing business/inbox/ledger/outbox history and
-- external eligibility are preserved. A completed live cohort stays completed.
-- Rollback: disable the rental producer/external control/cron, retain this
-- column and all notification evidence; never replay earlier suppressed rows.
begin;

do $initial_evaluation$
begin
  if not exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='v1_rental_notification_control' and column_name='initial_evaluation_complete') then
    alter table public.v1_rental_notification_control
      add column initial_evaluation_complete boolean not null default false;
    -- Prior successful runs below the cap already drained their initial cohort.
    -- A cap-sized last batch is conservatively rechecked while suppressing any
    -- remaining initial obligations, rather than guessing it finished the cohort.
    update public.v1_rental_notification_control
      set initial_evaluation_complete=last_success_at is not null and last_emitted_count<100
      where id;
  end if;
end;
$initial_evaluation$;

create or replace function public.v1_run_rental_notifications()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_enabled boolean; v_external boolean; v_initial_complete boolean; v_row record; v_id uuid;
  v_count integer:=0; v_external_count integer:=0; v_event text; v_eligible boolean;
  v_date date:=public.v1_rental_business_date(); v_now timestamptz:=statement_timestamp();
begin
  select enabled,external_push_enabled,initial_evaluation_complete into v_enabled,v_external,v_initial_complete
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
    v_eligible:=v_external and (v_initial_complete or v_event='rental_completeness_review');
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
  -- A successful 100-row batch can leave old obligations unprocessed. Remain
  -- in initial suppression until the current cohort is completely represented
  -- in the durable ledger. Fresh obligations only gain normal eligibility after
  -- that boundary; no old inbox-only row is modified or replayed.
  if not v_initial_complete then
    v_initial_complete:=not exists(
      select 1 from public.v1_rental_notification_candidates() c cross join public.v1_profiles p
      where public.v1_permission_exact_role(p.auth_user_id)='admin'
      and not exists(select 1 from public.v1_rental_notification_events e
        where e.recipient_auth_user_id=p.auth_user_id and e.event_code=c.event_code
          and e.obligation_id=c.obligation_id and e.milestone=c.milestone));
  end if;
  update public.v1_rental_notification_control set last_success_at=v_now,last_business_date=v_date,
    last_emitted_count=v_count,initial_evaluation_complete=v_initial_complete where id;
  return jsonb_build_object('enabled',true,'external_push_enabled',v_external,'external_push_candidates',v_external_count,
    'initial_evaluation_complete',v_initial_complete,'business_date',v_date,'timezone','Asia/Dubai','emitted',v_count);
end; $$;
revoke all on function public.v1_run_rental_notifications() from public,anon,authenticated;
grant execute on function public.v1_run_rental_notifications() to service_role;


create or replace function public.v1_notification_page(
  p_limit integer default 100, p_before_created_at timestamptz default null,
  p_before_id uuid default null, p_unread_only boolean default false,
  p_urgent_only boolean default false, p_search text default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_rows jsonb; v_chat jsonb; v_unread bigint;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_NOTIFICATION_LIST_DENIED' using errcode = '42501';
  end if;
  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'V1_NOTIFICATION_CURSOR_INVALID' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_rows from (
    select n.id notification_id, n.event_code, n.entity_type, n.entity_id,
      public.v1_resolve_notification_request_id(n.entity_type,n.entity_id) request_id,
      n.project_id,
      public.v1_resolve_notification_chat_conversation_id(n.entity_type,n.entity_id) chat_conversation_id,
      n.created_at, n.seen_at, public.v1_notification_module_route(n) module_route,
      public.v1_notification_record_label(n) record_label
    from public.v1_notifications n
    where n.recipient_auth_user_id = v_actor
      and not public.v1_notification_is_chat_transport(n.event_code,n.entity_type)
      and (p_search is null or btrim(p_search)='' or (
        replace(n.event_code,'_',' ') ilike '%'||left(btrim(p_search),120)||'%'
        or public.v1_notification_record_label(n) ilike '%'||left(btrim(p_search),120)||'%'))
      and (not p_unread_only or n.seen_at is null)
      and (not p_urgent_only or n.event_code in ('accounts_invoice_overdue','accounts_pdc_overdue','rental_rent_overdue'))
      and (p_before_created_at is null or (n.created_at,n.id) < (p_before_created_at,p_before_id))
    order by n.created_at desc,n.id desc
    limit greatest(1,least(coalesce(p_limit,100),200)) + 1
  ) r;
  -- Chat stays out of history and its unread total. This recipient-only feed
  -- gives foreground attention the same durable source as background push.
  -- Include fresh workflow events too so inbox filters never hide attention.
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_chat from (
    select n.id notification_id,n.event_code,n.entity_type,n.entity_id,
      public.v1_resolve_notification_request_id(n.entity_type,n.entity_id) request_id,n.project_id,
      public.v1_resolve_notification_chat_conversation_id(n.entity_type,n.entity_id) chat_conversation_id,
      n.created_at,n.seen_at, public.v1_notification_module_route(n) module_route,
      public.v1_notification_record_label(n) record_label
    from public.v1_notifications n
    where n.recipient_auth_user_id = v_actor and n.seen_at is null
      and n.created_at > now() - interval '5 minutes'
      and public.v1_push_notification_entity_allowed(n)
    order by n.created_at desc,n.id desc limit 100
  ) r;
  select count(*) into v_unread from public.v1_notifications n
    where n.recipient_auth_user_id = v_actor and n.seen_at is null
      and not public.v1_notification_is_chat_transport(n.event_code,n.entity_type);
  return jsonb_build_object('records',v_rows,'attention',v_chat,'unreadCount',v_unread, 'servicePaused', (select operator_paused or circuit_open_until is not null from public.v1_push_transport_control where id));
end; $$;
revoke all on function public.v1_notification_page(integer,timestamptz,uuid,boolean,boolean,text) from public,anon;
grant execute on function public.v1_notification_page(integer,timestamptz,uuid,boolean,boolean,text) to authenticated;

commit;

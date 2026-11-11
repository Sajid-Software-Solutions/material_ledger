-- Exact-command readback with a minimal receipt independent of optional views.
-- Existing intents are the only retry ledger; no workflow/stock/audit is changed.
-- Apply before the client. Old clients retain the existing locked readback and
-- abandon endpoints. Rollback: deploy the prior client and retain these columns
-- and function; never delete unresolved intents or historical effects.
begin;
alter table public.v1_procurement_command_intents
  add column if not exists automatic_check_count smallint not null default 0
    check (automatic_check_count between 0 and 4),
  add column if not exists automatic_check_after timestamptz;
create index if not exists v1_audit_actor_command_effect_idx
  on public.v1_audit_events(actor_auth_user_id,idempotency_key,event_type)
  where idempotency_key is not null;

-- New clients hydrate the server budget before resuming. The old endpoint's
-- strict JSON contract remains byte-shape compatible for released clients.
create or replace function public.v1_get_procurement_progress_recovery(
  p_request_id uuid,p_editor_kind text,p_arrangement_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; i public.v1_procurement_command_intents%rowtype;
begin
  result:=public.v1_get_procurement_progress(p_request_id,p_editor_kind,p_arrangement_id);
  if result is null or result->'pending_command' is null then return result; end if;
  select * into i from public.v1_procurement_command_intents
    where owner_auth_user_id=auth.uid() and request_id=p_request_id
      and command_name=result#>>'{pending_command,command_name}'
      and command_key=(result#>>'{pending_command,command_key}')::uuid;
  if found then
    result:=jsonb_set(result,'{pending_command}',result->'pending_command'||
      jsonb_build_object('automatic_checks',i.automatic_check_count,
        'automatic_check_after',i.automatic_check_after));
  end if;
  return result;
end;
$$;
revoke all on function public.v1_get_procurement_progress_recovery(uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function public.v1_get_procurement_progress_recovery(uuid,text,uuid)
  to authenticated;

create or replace function public.v1_reconcile_procurement_command_outcome(
  p_request_id uuid,p_command_name text,p_idempotency_key uuid,
  p_automatic boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  i public.v1_procurement_command_intents%rowtype;
  k public.v1_idempotency_keys%rowtype;
  a public.v1_audit_events%rowtype;
  kind text; stored_name text; audit_key uuid; result jsonb;
  now_at timestamptz := clock_timestamp(); wait_ms integer;
  effect_ref text; committed_version integer;
begin
  kind:=case p_command_name when 'v1_save_arrangement' then 'arrangement'
    when 'v1_dispatch_materials' then 'dispatch' end;
  if p_request_id is null or p_idempotency_key is null or kind is null then
    raise exception 'V1_PROCUREMENT_COMMAND_PAYLOAD_INVALID' using errcode='22023';
  end if;
  if not public.v1_procurement_progress_authorized(p_request_id,kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  result:=jsonb_build_object('request_id',p_request_id,'command_name',p_command_name,
    'idempotency_key',p_idempotency_key);
  select * into i from public.v1_procurement_command_intents
    where owner_auth_user_id=auth.uid() and request_id=p_request_id
      and command_name=p_command_name and command_key=p_idempotency_key;
  if p_automatic then
    -- One atomic claim across browsers/tabs. This row is not locked by the
    -- final transaction, so polling does not queue behind the MR stock lock.
    update public.v1_procurement_command_intents
      set automatic_check_count=automatic_check_count+1,
        automatic_check_after=now_at+make_interval(secs=>power(2,automatic_check_count)::integer)
      where id=i.id and automatic_check_count<4
        and (automatic_check_after is null or automatic_check_after<=now_at)
      returning * into i;
    if not found then
      select * into i from public.v1_procurement_command_intents
        where owner_auth_user_id=auth.uid() and request_id=p_request_id
          and command_name=p_command_name and command_key=p_idempotency_key;
      wait_ms:=greatest(0,ceil(extract(epoch from(i.automatic_check_after-now_at))*1000))::integer;
      return result||jsonb_build_object('status','pending','check_deferred',true,
        'automatic_checks_remaining',greatest(0,4-coalesce(i.automatic_check_count,4)),
        'retry_after_ms',coalesce(wait_ms,0));
    end if;
  end if;
  result:=result||jsonb_build_object('automatic_checks_remaining',
    greatest(0,4-coalesce(i.automatic_check_count,4)),
    'retry_after_ms',case when i.automatic_check_count<4 then
      greatest(0,ceil(extract(epoch from(i.automatic_check_after-now_at))*1000))::integer
      else 0 end);
  stored_name:=case when kind='arrangement' then 'v1_save_arrangement_phase3'
    else p_command_name end;
  select * into k from public.v1_idempotency_keys
    where actor_auth_user_id=auth.uid() and command_name=stored_name
      and idempotency_key=p_idempotency_key;
  if k.completed_at is not null then
    if coalesce(k.response_json->>'request_id','')<>p_request_id::text then
      raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
    end if;
    audit_key:=case when kind='arrangement'
      then public.v1_phase3_nested_idempotency_key(p_idempotency_key)
      else p_idempotency_key end;
    select * into a from public.v1_audit_events
      where actor_auth_user_id=auth.uid() and idempotency_key=audit_key
        and event_type=case when kind='arrangement' then 'arrangement_saved'
          else 'materials_dispatched' end
      order by occurred_at limit 1;
    -- The receipt identifies this exact effect, never "the latest dispatch".
    if a.id is null then
      return result||jsonb_build_object('status','pending','attempt_id',i.id);
    end if;
    if kind='dispatch' then
      select dispatch_number into effect_ref from public.v1_material_dispatches
        where id=a.entity_id and request_id=p_request_id;
      if not found then raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501'; end if;
    else
      if not exists(select 1 from public.v1_procurement_arrangements
        where id=a.entity_id and request_id=p_request_id) then
        raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
      end if;
      effect_ref:=null;
    end if;
    committed_version:=nullif(k.response_json->>'request_record_version','')::integer;
    return result||jsonb_build_object('status','confirmed','attempt_id',i.id,
      'receipt',jsonb_build_object('effect_id',a.entity_id,'effect_reference',effect_ref,
        'committed_version',committed_version,'committed_at',k.completed_at));
  end if;
  -- A lookup miss never releases or rejects a potentially in-flight command.
  -- Explicit abandonment continues through the existing MR-row-locked RPC.
  if i.id is null then return result||jsonb_build_object('status','not_found'); end if;
  if i.abandoned_at is not null then
    return result||jsonb_build_object('status','abandoned','attempt_id',i.id);
  end if;
  if i.contains_commercial and (not public.v1_has_capability('view_commercials')
    or not public.v1_has_capability('manage_commercials')) then
    return result||jsonb_build_object('status','access_changed','attempt_id',i.id);
  end if;
  return result||jsonb_build_object('status',case when k.idempotency_key is null
      then 'prepared' else 'pending' end,'attempt_id',i.id,'command_payload',i.command_payload);
end;
$$;
revoke all on function public.v1_reconcile_procurement_command_outcome(uuid,text,uuid,boolean)
  from public,anon,authenticated;
grant execute on function public.v1_reconcile_procurement_command_outcome(uuid,text,uuid,boolean)
  to authenticated;
commit;

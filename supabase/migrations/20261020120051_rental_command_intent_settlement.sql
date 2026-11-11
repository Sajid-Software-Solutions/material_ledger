-- Explicit recovery for an active Admin's locally retained uncertain intent.
-- This never declares a committed command abandoned. The same advisory lock
-- as v1_idempotency_get_or_claim linearizes settlement with any old request.
-- Existing business, idempotency and audit history are retained. A new fence
-- uses a non-hash sentinel so delayed ordinary payloads cannot match its key.
-- Rollback: hide/revoke settlement while retaining all fences and audit rows;
-- never remove a fence or reuse its key for a new command attempt.
begin;

create or replace function public.v1_settle_rental_command_intent(
  p_command_name text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=public.v1_rental_assert_admin();
  v_existing public.v1_idempotency_keys%rowtype;
  v_fence text:='rental-abandoned:'||p_idempotency_key::text;
  v_before jsonb;
begin
  if p_idempotency_key is null or p_command_name is null or p_command_name not in (
    'v1_save_rental_property','v1_record_rent_payment','v1_save_rental_cheque',
    'v1_transition_rental_cheque','v1_archive_rental_property','v1_import_rental_workbook'
  ) then
    raise exception 'V1_RENTAL_COMMAND_INVALID' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_actor::text||'|'||p_command_name||'|'||p_idempotency_key::text,0));
  select * into v_existing from public.v1_idempotency_keys k
  where k.actor_auth_user_id=v_actor and k.command_name=p_command_name
    and k.idempotency_key=p_idempotency_key for update;

  if found and v_existing.response_json is not null then
    return jsonb_build_object('state',case
      when v_existing.request_hash=v_fence and v_existing.response_json->>'state'='abandoned'
        then 'abandoned' else 'confirmed' end);
  end if;

  v_before:=jsonb_build_object('state',case when found then 'unconfirmed' else 'not_started' end,
    'command_name',p_command_name,'request_hash',v_existing.request_hash,'created_at',v_existing.created_at);

  insert into public.v1_idempotency_keys(actor_auth_user_id,command_name,idempotency_key,
    request_hash,response_json,completed_at)
  values(v_actor,p_command_name,p_idempotency_key,v_fence,'{"state":"abandoned"}'::jsonb,clock_timestamp())
  on conflict(actor_auth_user_id,command_name,idempotency_key) do update
    set request_hash=excluded.request_hash,response_json=excluded.response_json,
      completed_at=excluded.completed_at;
  perform public.v1_write_audit_event('rental_command_intent_abandoned','rental_command_intent',
    p_idempotency_key,null,v_before,
    jsonb_build_object('state','abandoned','command_name',p_command_name),
    'Unconfirmed rental command fenced before a new attempt.',
    public.v1_rental_import_child_key(p_idempotency_key,'settle-'||p_command_name,1));
  return jsonb_build_object('state','abandoned');
end;
$$;
revoke all on function public.v1_settle_rental_command_intent(text,uuid) from public,anon;
grant execute on function public.v1_settle_rental_command_intent(text,uuid) to authenticated;

-- A fence is a settled non-execution outcome, never a successful payment/save.
-- This read remains actor-scoped and does not return the original payload.
create or replace function public.v1_get_rental_command_outcome(
  p_command_name text,p_idempotency_key uuid
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_actor uuid:=public.v1_rental_assert_admin();
  v_existing public.v1_idempotency_keys%rowtype;
begin
  if p_idempotency_key is null or p_command_name is null or p_command_name not in (
    'v1_save_rental_property','v1_record_rent_payment','v1_save_rental_cheque',
    'v1_transition_rental_cheque','v1_archive_rental_property','v1_import_rental_workbook'
  ) then
    raise exception 'V1_RENTAL_COMMAND_INVALID' using errcode='22023';
  end if;
  select * into v_existing from public.v1_idempotency_keys k
  where k.actor_auth_user_id=v_actor and k.command_name=p_command_name
    and k.idempotency_key=p_idempotency_key;
  return jsonb_build_object('state',case
    when v_existing.response_json is null then 'unconfirmed'
    when v_existing.request_hash='rental-abandoned:'||p_idempotency_key::text
      and v_existing.response_json->>'state'='abandoned' then 'abandoned'
    else 'confirmed' end);
end;
$$;
revoke all on function public.v1_get_rental_command_outcome(text,uuid) from public,anon;
grant execute on function public.v1_get_rental_command_outcome(text,uuid) to authenticated;

commit;

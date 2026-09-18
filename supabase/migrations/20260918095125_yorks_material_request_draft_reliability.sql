begin;

-- Additive save receipt contract. The legacy one-argument draft save remains
-- available for already-deployed clients; new clients use this wrapper so a
-- lost HTTP response can be reconciled without repeating the business effect.
create or replace function public.v1_save_material_request_draft_idempotent(
  p_payload jsonb,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_request_id uuid := nullif(btrim(coalesce(p_payload ->> 'request_id', '')), '')::uuid;
  v_project_id uuid := nullif(btrim(coalesce(p_payload ->> 'project_id', '')), '')::uuid;
  v_existing jsonb;
  v_saved jsonb;
  v_response jsonb;
begin
  if v_actor is null or not public.v1_current_actor_is_active()
    or v_request_id is null or v_project_id is null
    or not public.v1_can_create_material_request(v_project_id) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_SAVE_DENIED'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.v1_material_requests request_record
    where request_record.id = v_request_id
      and (
        request_record.project_id <> v_project_id
        or request_record.created_by_auth_user_id <> v_actor
      )
  ) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_SAVE_DENIED'
      using errcode = '42501';
  end if;

  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_material_request_draft_idempotent',
    p_idempotency_key,
    p_payload
  );
  if v_existing is not null then return v_existing; end if;

  v_saved := public.v1_save_material_request_draft(p_payload);
  v_response := jsonb_build_object(
    'request_id', v_request_id,
    'record_version', (v_saved ->> 'record_version')::integer,
    'operation_id', p_idempotency_key,
    'payload_hash', public.v1_hash_json(p_payload),
    'committed_at', v_saved ->> 'updated_at'
  );
  perform public.v1_complete_idempotency(
    'v1_save_material_request_draft_idempotent',
    p_idempotency_key,
    v_response
  );
  return v_response;
end;
$$;

-- Read-only lookup for an uncertain save. Absence is intentionally returned
-- as null and is not interpreted as rollback; the caller may later replay the
-- same key and byte-equivalent JSON payload.
create or replace function public.v1_get_material_request_draft_save_result(
  p_payload jsonb,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_request_id uuid := nullif(btrim(coalesce(p_payload ->> 'request_id', '')), '')::uuid;
  v_project_id uuid := nullif(btrim(coalesce(p_payload ->> 'project_id', '')), '')::uuid;
  v_key public.v1_idempotency_keys%rowtype;
begin
  if v_actor is null or not public.v1_current_actor_is_active()
    or v_request_id is null or v_project_id is null
    or p_idempotency_key is null
    or not public.v1_can_create_material_request(v_project_id) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_SAVE_RESULT_DENIED'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.v1_material_requests request_record
    where request_record.id = v_request_id
      and (
        request_record.project_id <> v_project_id
        or request_record.created_by_auth_user_id <> v_actor
      )
  ) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_SAVE_RESULT_DENIED'
      using errcode = '42501';
  end if;

  select * into v_key
  from public.v1_idempotency_keys key_record
  where key_record.actor_auth_user_id = v_actor
    and key_record.command_name = 'v1_save_material_request_draft_idempotent'
    and key_record.idempotency_key = p_idempotency_key;
  if not found then return null; end if;
  if v_key.request_hash <> public.v1_hash_json(p_payload) then
    raise exception 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD'
      using errcode = '22023';
  end if;
  if v_key.response_json is null then return null; end if;
  if v_key.response_json ->> 'request_id' is distinct from v_request_id::text
    or not exists (
      select 1 from public.v1_material_requests request_record
      where request_record.id = v_request_id
        and request_record.project_id = v_project_id
        and request_record.created_by_auth_user_id = v_actor
    ) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_SAVE_RESULT_DENIED'
      using errcode = '42501';
  end if;
  return v_key.response_json;
end;
$$;

revoke all on function public.v1_save_material_request_draft_idempotent(jsonb,uuid)
  from public, anon, authenticated;
grant execute on function public.v1_save_material_request_draft_idempotent(jsonb,uuid)
  to authenticated;
revoke all on function public.v1_get_material_request_draft_save_result(jsonb,uuid)
  from public, anon, authenticated;
grant execute on function public.v1_get_material_request_draft_save_result(jsonb,uuid)
  to authenticated;

-- Rollback is client-first: old clients continue using the retained legacy
-- function. Leave completed receipts in place for audit/reconciliation; these
-- additive functions may be removed only after no compatible client depends
-- on them. No Material Request data is deleted or reinterpreted.
commit;

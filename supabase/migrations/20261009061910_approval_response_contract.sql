-- Preserve the existing approval authority, locking, audit and idempotency path.
-- Normalize its clarification response for the Material Request client contract,
-- including previously committed commands whose stored response used the old shape.
do $$
begin
  if to_regprocedure('public.v1_decide_material_request_before_response_contract(jsonb,uuid)') is null then
    alter function public.v1_decide_material_request(jsonb, uuid)
      rename to v1_decide_material_request_before_response_contract;
  end if;
end;
$$;

create or replace function public.v1_decide_material_request(
  p_payload jsonb,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_response jsonb;
  v_request_id uuid;
begin
  v_response := public.v1_decide_material_request_before_response_contract(
    p_payload, p_idempotency_key
  );
  if v_response ? 'request_id' and not (v_response ? 'id') then
    v_request_id := (p_payload ->> 'request_id')::uuid;
    if v_response ->> 'request_id' is distinct from v_request_id::text then
      raise exception 'V1_MATERIAL_REQUEST_RESPONSE_MISMATCH' using errcode = '22023';
    end if;
    -- This projection rechecks current read authority and commercial visibility.
    v_response := public.v1_material_request_projection(v_request_id);
    update public.v1_idempotency_keys
      set response_json = v_response
      where actor_auth_user_id = auth.uid()
        and command_name = 'v1_decide_material_request'
        and idempotency_key = p_idempotency_key;
  end if;
  return v_response;
end;
$$;

revoke all on function public.v1_decide_material_request_before_response_contract(jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_decide_material_request(jsonb, uuid)
  from public, anon;
grant execute on function public.v1_decide_material_request(jsonb, uuid)
  to authenticated;
-- Rollback: restore the prior function body if needed; retain command responses,
-- decisions and audit history. No business records or stock are rewritten.

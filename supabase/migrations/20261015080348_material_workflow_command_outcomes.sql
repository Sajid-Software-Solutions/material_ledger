-- Read-only witness of an actor's exact consequential Material Request command.
-- A lookup miss is UNKNOWN, never proof that an in-flight transaction cannot commit.
create or replace function public.v1_get_material_workflow_command_outcome(
  p_command_name text, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare k public.v1_idempotency_keys%rowtype; r uuid; response jsonb;
  result jsonb; stored_name text;
begin
  if auth.uid() is null or public.v1_current_role() = '' then
    raise exception 'V1_AUTHENTICATED_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_command_name not in ('v1_decide_material_request','v1_submit_material_request',
      'v1_save_submit_and_approve_material_request','v1_begin_arrangement',
      'v1_save_arrangement','v1_decide_arrangement','v1_dispatch_materials',
      'v1_confirm_receipt','v1_cancel_material_request','v1_close_material_request',
      'v1_generate_delivery_order') or p_idempotency_key is null then
    raise exception 'V1_COMMAND_OUTCOME_INVALID' using errcode='22023';
  end if;
  stored_name := case when p_command_name='v1_save_arrangement'
    then 'v1_save_arrangement_phase3' else p_command_name end;
  select * into k from public.v1_idempotency_keys where actor_auth_user_id=auth.uid()
    and command_name=stored_name and idempotency_key=p_idempotency_key;
  result := jsonb_build_object('command_name',p_command_name,'command_key',p_idempotency_key);
  if k.completed_at is null then return result||jsonb_build_object('status','unknown'); end if;
  r := nullif(coalesce(k.response_json->>'request_id', k.response_json->>'id'),'')::uuid;
  if r is null or not public.v1_material_request_readable(r) then
    raise exception 'V1_MATERIAL_REQUEST_NOT_READABLE' using errcode='42501';
  end if;
  result := result||jsonb_build_object('status','confirmed','entity_id',r,
    'record_version',coalesce(k.response_json->'record_version',k.response_json->'request_record_version'));
  -- Never replay a historical commercial payload after authority has changed.
  -- A receipt remains authoritative when optional view hydration is unavailable.
  begin
    response := case
      when p_command_name in ('v1_decide_material_request','v1_submit_material_request',
        'v1_save_submit_and_approve_material_request','v1_cancel_material_request','v1_close_material_request')
        then public.v1_material_request_projection(r)
      when p_command_name in ('v1_begin_arrangement','v1_save_arrangement','v1_decide_arrangement')
        then public.v1_arrangement_projection(r)
      when p_command_name='v1_generate_delivery_order'
        then public.v1_returns_documents_workspace_projection(r)
      else public.v1_logistics_workspace_projection(r) end;
  exception when query_canceled or lock_not_available then response := null;
    when others then response := null;
  end;
  return result||jsonb_build_object('response',response);
end $$;
revoke all on function public.v1_get_material_workflow_command_outcome(text,uuid) from public,anon;
grant execute on function public.v1_get_material_workflow_command_outcome(text,uuid) to authenticated;
-- Additive/read-only. Rollback may revoke the new RPC and disable its client.
-- Preserve existing idempotency receipts, audit history and all business records.

-- Read-only acknowledgement lookup. No command replay, mutation, lock or cleanup.
-- An absent witness means unknown, never proof of rollback. History is retained.
-- Rollback: revoke this RPC and disable automatic lookup in the coordinator.
create or replace function public.v1_get_project_setup_command_outcome(
  p_command_name text, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare receipt public.v1_idempotency_keys%rowtype; project_id uuid;
  result jsonb;
begin
  if auth.uid() is null or public.v1_current_role() = ''
    or not public.v1_current_actor_is_active() then
    raise exception 'V1_AUTHENTICATED_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_command_name is null or p_command_name not in
    ('v1_create_project','v1_update_project','v1_set_project_state')
    or p_idempotency_key is null then
    raise exception 'V1_PROJECT_COMMAND_OUTCOME_INVALID' using errcode='22023';
  end if;
  result := jsonb_build_object('command_name',p_command_name,'command_key',p_idempotency_key);
  select * into receipt from public.v1_idempotency_keys
  where actor_auth_user_id=auth.uid() and command_name=p_command_name
    and idempotency_key=p_idempotency_key;
  if receipt.completed_at is null then
    return result||jsonb_build_object('status','unknown');
  end if;
  project_id := nullif(coalesce(receipt.response_json->>'project_id',
    receipt.response_json->'project'->>'id'),'')::uuid;
  if project_id is null or not public.v1_project_readable(project_id) then
    raise exception 'V1_PROJECT_NOT_READABLE' using errcode='42501';
  end if;
  -- Re-read the existing current-authority projection. Never return historical
  -- party, membership, attachment or protected data from the stored response.
  return result||jsonb_build_object('status','confirmed','entity_id',project_id,
    'record_version',coalesce(receipt.response_json->'record_version',
      receipt.response_json->'project'->'record_version'),
    'response',jsonb_build_object('project',public.v1_project_projection(project_id)));
end $$;
revoke all on function public.v1_get_project_setup_command_outcome(text,uuid)
  from public,anon,authenticated;
grant execute on function public.v1_get_project_setup_command_outcome(text,uuid)
  to authenticated,service_role;

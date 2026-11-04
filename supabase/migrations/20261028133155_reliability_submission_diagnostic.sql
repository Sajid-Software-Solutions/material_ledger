-- Optional, read-only context explanation after a definitive submission denial.
-- This is not command acknowledgement or a replacement for version/line/quantity
-- validation. Unknown/denied projects return the same coarse shape. No business,
-- permission, membership, audit or recovery data is changed.
-- Compatibility: old clients ignore this RPC; new clients must safely retain
-- denial state when this additive RPC is absent. Rollback revokes the RPC only
-- after clients can handle its absence; never relax any trusted command check.
create or replace function public.v1_material_request_submission_diagnostic(
  p_project_id uuid,p_scope_id uuid,p_request_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_actor uuid:=auth.uid();v_revision bigint;v_membership boolean:=false;
  v_scope_consistent boolean:=false;v_project_state text;v_reason text:='ready';
  v_request public.v1_material_requests%rowtype;v_request_exists boolean:=false;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_AUTHENTICATED_ROLE_REQUIRED' using errcode='42501';
  end if;
  select coalesce(max(revision),0) into v_revision from public.v1_permission_revisions where auth_user_id=v_actor;
  if p_project_id is null or not coalesce(public.v1_project_readable(p_project_id),false) then
    return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
      'active_membership',null,'project_scope_consistent',null,'can_submit',false);
  end if;
  select state into v_project_state from public.v1_projects where id=p_project_id;
  select exists(select 1 from public.v1_project_members m join public.v1_profiles p
    on p.auth_user_id=m.member_auth_user_id and p.is_active
    where m.project_id=p_project_id and m.member_auth_user_id=v_actor
      and m.effective_from<=clock_timestamp() and (m.effective_to is null or m.effective_to>clock_timestamp())) into v_membership;
  select exists(select 1 from public.v1_project_scopes s where s.id=p_scope_id
    and s.project_id=p_project_id and s.is_active) into v_scope_consistent;
  if p_request_id is not null then
    select * into v_request from public.v1_material_requests where id=p_request_id;
    v_request_exists:=found;
    if not v_request_exists then
      if exists(select 1 from public.v1_material_request_private_draft_retirements
        where draft_id=p_request_id and owner_auth_user_id=v_actor) then
        return jsonb_build_object('reason_code','draft_retired','permission_revision',v_revision,
          'active_membership',v_membership,'project_scope_consistent',v_scope_consistent,'can_submit',false);
      end if;
      -- An unknown ID and another creator's private ID have the same shape.
      -- New/local-only drafts call with p_request_id=null for context review.
      return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
        'active_membership',null,'project_scope_consistent',null,'can_submit',false);
    end if;
    if v_request_exists and (v_request.created_by_auth_user_id<>v_actor
        or not public.v1_material_request_readable(p_request_id)) then
      -- Do not reveal another creator's private draft/state or a revoked request.
      return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
        'active_membership',null,'project_scope_consistent',null,'can_submit',false);
    end if;
  end if;
  if v_project_state<>'active' then v_reason:='project_not_active';
  elsif not v_scope_consistent then v_reason:='scope_unavailable';
  elsif v_request_exists and v_request.project_id<>p_project_id then v_reason:='request_context_changed';
  elsif v_request_exists and v_request.state<>'draft' then v_reason:='request_progressed';
  elsif not public.v1_can_create_material_request(p_project_id) then v_reason:='creation_not_allowed';
  elsif v_request_exists and not public.v1_current_user_has_capability('material_requests.edit',p_project_id)
    then v_reason:='editing_not_allowed';
  elsif not public.v1_current_user_has_capability('material_requests.submit',p_project_id)
    then v_reason:='submission_not_allowed';
  end if;
  return jsonb_build_object('reason_code',v_reason,'permission_revision',v_revision,
    'active_membership',v_membership,'project_scope_consistent',v_scope_consistent,'can_submit',v_reason='ready');
end;
$$;
revoke all on function public.v1_material_request_submission_diagnostic(uuid,uuid,uuid) from public,anon;
grant execute on function public.v1_material_request_submission_diagnostic(uuid,uuid,uuid) to authenticated;

-- A Site Engineer with dated Project Engineer membership and the explicit
-- approval capability is an approver under the existing MR decision policy.
-- Align the optional edit grant with that same server-authorized set.
-- Additive function replacement; no records or grants are removed.
create or replace function public.v1_can_manage_material_request_post_approval_edit(
  p_request_id uuid
) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_request public.v1_material_requests%rowtype;
  v_role text := public.v1_current_exact_role();
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or v_role not in (
      'project_engineer', 'senior_mechanical_engineer', 'project_manager',
      'workshop_in_charge', 'document_controller', 'site_engineer', 'admin'
    ) then return false; end if;
  select * into v_request from public.v1_material_requests
  where id = p_request_id;
  if not found or (
    v_request.state <> 'approved_for_arrangement'
    and not (v_request.post_approval_amendment_pending
      and v_request.state in ('awaiting_request_approval', 'changes_requested'))
  ) or exists (
    select 1 from public.v1_procurement_arrangements
    where request_id = p_request_id
  ) then return false; end if;
  return public.v1_can_decide_material_request(p_request_id)
    and (v_role = 'admin' or v_role in (
    'senior_mechanical_engineer', 'project_manager',
    'workshop_in_charge', 'document_controller'
  ) or (v_role in ('project_engineer', 'site_engineer') and
    public.v1_has_active_project_membership(
      v_request.project_id, auth.uid(), 'project_engineer'
    ))) and public.v1_current_user_has_capability(
      'material_requests.approve', v_request.project_id
    );
end;
$$;

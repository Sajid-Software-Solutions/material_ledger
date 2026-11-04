-- Bound dashboard action scoring to projects rather than retained requests.
-- Reuses the deployed permission graph resolver without changing any helper,
-- RLS, command, role, membership, idempotency or commercial response shape.
-- Data-preserving function-only migration. Rollback restores the body from
-- 20260902163200_optimize_startup_material_request_overview.sql; keep graph helper.
create or replace function public.v1_material_request_overview(
  p_limit integer default 6
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 15);
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_result jsonb;
  v_role text := public.v1_current_role();
  v_global boolean := v_exact_role in ('senior_mechanical_engineer','project_manager','workshop_in_charge','document_controller');
  v_allow_self boolean := public.v1_material_request_published_policy_boolean('requests.allow_authorized_creator_self_approval',true);
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_MATERIAL_REQUEST_OVERVIEW_DENIED'
      using errcode = '42501';
  end if;

  with active_memberships as materialized (
    select member.project_id,true as has_membership,
      bool_or(member.project_role='project_engineer') as is_project_engineer,
      bool_or(member.project_role='site_engineer') as is_site_engineer
    from public.v1_project_members member
    where member.member_auth_user_id=v_actor
      and member.effective_from<=clock_timestamp()
      and (member.effective_to is null or member.effective_to>clock_timestamp())
    group by member.project_id
  ), project_maps as materialized (
    -- Reuse the already-parity-tested statement-local dependency resolver.
    -- No authority result survives this call or changes command authorization.
    select project.id as project_id,project.state as project_state,
      coalesce(m.has_membership,false) as has_active_membership,
      coalesce(m.is_project_engineer,false) as is_project_engineer,
      coalesce(m.is_site_engineer,false) as is_site_engineer,
      public.v1_material_register_permission_map(v_actor,project.id,
        array['material_requests.view','material_requests.edit',
          'material_requests.approve','material_requests.return_for_changes',
          'procurement.arrange','dispatch.create','receipts.confirm','material_requests.close']) as permissions
    from public.v1_projects project
    left join active_memberships m on m.project_id=project.id
    where exists(select 1 from public.v1_material_requests r where r.project_id=project.id)
  ), project_access as materialized (
    select project_maps.*,
      coalesce((permissions->>'material_requests.view')::boolean,false) as can_view
    from project_maps
  ), has_arrangement as materialized (
    select distinct request_id from public.v1_procurement_arrangements
  ), readable as materialized (
    -- This case expression is the set-based equivalent of
    -- v1_material_request_participant(request.id, v_actor). Keep its ordering:
    -- Admin can read drafts; every other role can read a draft only when it is
    -- their own; global engineers then receive organization-wide submitted
    -- work; project roles require dated membership; Procurement receives only
    -- the established procurement lifecycle states.
    select request.*, access.project_state,access.permissions,
      access.has_active_membership,access.is_project_engineer,access.is_site_engineer,
      arrangement.request_id is not null as has_arrangement,
      project.project_ref,
      project.name as project_name, project.job_contract_reference,
      scope.name as scope_name
    from public.v1_material_requests request
    join project_access access on access.project_id = request.project_id
    join public.v1_projects project on project.id = request.project_id
    join public.v1_project_scopes scope on scope.id = request.scope_id
    left join has_arrangement arrangement on arrangement.request_id=request.id
    where access.can_view
      and case
        when v_exact_role = 'admin' then true
        when request.state = 'draft'
          then request.created_by_auth_user_id = v_actor
        when v_exact_role in (
          'senior_mechanical_engineer', 'project_manager',
          'workshop_in_charge', 'document_controller'
        ) then true
        when v_exact_role in ('project_engineer', 'site_engineer')
          then access.has_active_membership
        when v_exact_role = 'procurement' then request.state in (
          'submitted', 'approved_for_arrangement', 'arranging',
          'awaiting_approval', 'approved', 'partially_dispatched',
          'dispatched', 'partially_received', 'received', 'closed',
          'cancelled'
        )
        else false
      end
  ), scored as materialized (
    -- Set-based equivalent of the unchanged actor_has_current_action helper.
    -- Keep its branch order, ownership, exact roles, state gates and policies.
    select readable.*,
      case
        when state in ('closed','cancelled') then false
        when state='draft' then created_by_auth_user_id=v_actor
        when state in ('submitted','awaiting_request_approval') then
          (v_exact_role='admin' or v_global or (v_exact_role='project_engineer' and is_project_engineer))
          and (v_allow_self or created_by_auth_user_id<>v_actor)
          and (coalesce((permissions->>'material_requests.approve')::boolean,false)
            or coalesce((permissions->>'material_requests.return_for_changes')::boolean,false))
        when state='changes_requested' and post_approval_amendment_pending then
          public.v1_can_edit_material_request_before_approval(id)
        when state='changes_requested' then not has_arrangement
          and (created_by_auth_user_id=v_actor or v_exact_role='admin' or v_global
            or (v_exact_role='project_engineer' and is_project_engineer))
          and coalesce((permissions->>'material_requests.edit')::boolean,false)
        when state in ('approved_for_arrangement','arranging') then
          v_exact_role in ('procurement','admin') and project_state in ('active','on_hold')
          and coalesce((permissions->>'procurement.arrange')::boolean,false)
        when state='awaiting_approval' then
          v_role in ('project_engineer','admin')
          and (v_exact_role='admin' or v_global or is_project_engineer)
        when current_action_code='receipt_review_required' or state='dispatched' then
          project_state in ('active','on_hold','completed')
          and (v_exact_role='admin' or v_global
            or (v_exact_role in ('project_engineer','site_engineer') and has_active_membership))
          and coalesce((permissions->>'receipts.confirm')::boolean,false)
        when current_action_code='material_request_close_review' or state='received' then
          (v_exact_role='admin' or v_global
            or (v_exact_role='project_engineer' and is_project_engineer)
            or (v_exact_role='site_engineer' and is_site_engineer))
          and coalesce((permissions->>'material_requests.close')::boolean,false)
        when state in ('approved','partially_dispatched','partially_received') then
          v_exact_role in ('procurement','admin') and project_state='active'
          and coalesce((permissions->>'dispatch.create')::boolean,false)
        else false
      end as actor_can_act
    from readable
  ), bounded as materialized (
    select * from scored
    order by updated_at desc, id
    limit v_limit
  )
  select jsonb_build_object(
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', bounded.id,
        'project_id', bounded.project_id,
        'project_ref', bounded.project_ref,
        'project_name', bounded.project_name,
        'job_contract_reference', bounded.job_contract_reference,
        'scope_id', bounded.scope_id,
        'scope_name', bounded.scope_name,
        'state', bounded.state,
        'record_version', bounded.record_version,
        'request_number', bounded.request_number,
        'title', bounded.title,
        'timing', bounded.timing,
        'scheduled_date', bounded.scheduled_date,
        'delivery_note', bounded.delivery_note,
        'requester_display_name', bounded.requester_display_name,
        'requester_project_role', bounded.requester_project_role,
        'requester_exact_role', bounded.requester_exact_role,
        'current_action_owner_role', bounded.current_action_owner_role,
        'current_action_code', bounded.current_action_code,
        'current_action_started_at', bounded.updated_at,
        'current_action_age_hours', greatest(
          extract(epoch from (clock_timestamp() - bounded.updated_at)) / 3600,
          0
        ),
        'required_on_site_overdue', bounded.timing = 'scheduled'
          and bounded.scheduled_date < current_date
          and bounded.state not in ('received', 'closed', 'cancelled'),
        'actor_can_act', bounded.actor_can_act,
        -- Exception, assignment and revision enrichment belong to the detail
        -- and register RPCs. Startup cards need identity/state only.
        'exception_codes', to_jsonb(array[]::text[]),
        'item_count', (
          select count(*)::integer
          from public.v1_material_request_lines line
          where line.request_id = bounded.id
        ),
        'work_assignment', jsonb_build_object(
          'request_id', bounded.id,
          'assignment_version', 0,
          'assignee_auth_user_id', null,
          'assignee_display_name', null,
          'assignee_exact_role', null,
          'assigned_at', null,
          'can_manage', false
        ),
        'change_summary', null,
        'submitted_at', bounded.submitted_at,
        'created_at', bounded.created_at,
        'updated_at', bounded.updated_at
      ) order by bounded.updated_at desc, bounded.id), '[]'::jsonb)
      from bounded
    ),
    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'open', count(*) filter (where state not in (
          'draft', 'received', 'closed', 'cancelled'
        )),
        'needs_action', count(*) filter (where actor_can_act),
        'approvals', count(*) filter (where state in (
          'awaiting_request_approval', 'awaiting_approval'
        )),
        'delivery_exceptions', count(*) filter (where state in (
          'changes_requested', 'partially_dispatched', 'partially_received'
        )),
        'receipt_pending', count(*) filter (where state in (
          'dispatched', 'partially_received'
        )),
        'drafts_and_changes', count(*) filter (where state in (
          'draft', 'changes_requested'
        )),
        'received', count(*) filter (where state = 'received'),
        'closed', count(*) filter (where state = 'closed'),
        'dispatch_ready', count(*) filter (where state in (
          'approved', 'partially_dispatched'
        )),
        'new_to_arrange', count(*) filter (where state in (
          'approved_for_arrangement', 'arranging'
        ))
      )
      from scored
    )
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.v1_material_request_overview(integer)
  from public, anon, authenticated;
grant execute on function public.v1_material_request_overview(integer)
  to authenticated, service_role;
comment on function public.v1_material_request_overview(integer)
is 'Set-based bounded non-commercial launch cards with exact authorized counts.';

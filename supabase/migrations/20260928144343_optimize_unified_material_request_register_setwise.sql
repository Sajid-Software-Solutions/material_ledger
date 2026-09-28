-- Replace the unified Material Request register's per-request authorization,
-- action and exception helper calls with set-based actor/project/request facts.
--
-- Data preservation: function-only replacement. No Material Request, line,
-- assignment, arrangement, receipt, return, audit or permission row changes.
-- Response compatibility: the signature, JSON keys, sort tie-breakers, metric
-- meanings, privacy rules and 100-row server limit are unchanged.
-- Rollback: restore the prior function body in a corrective migration. Never
-- remove workflow data to roll back this read-path optimization.
begin;

create or replace function public.v1_list_unified_material_request_summaries(
  p_project_id uuid default null,
  p_search text default null,
  p_states text[] default null,
  p_scope_id uuid default null,
  p_requester text default null,
  p_updated_after timestamptz default null,
  p_attention_only boolean default false,
  p_metric text default 'all',
  p_sort text default 'updated_desc',
  p_limit integer default 15,
  p_offset integer default 0,
  p_register_view text default 'total',
  p_request_kind text default 'all'
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_role text := public.v1_current_role();
  v_actor_active boolean := public.v1_current_actor_is_active();
  v_allow_self_approval boolean := public.v1_material_request_published_policy_boolean(
    'requests.allow_authorized_creator_self_approval', true
  );
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
begin
  if v_actor is null or not v_actor_active
    or p_request_kind is null or p_request_kind not in ('all','project','company')
    or p_sort is null or p_metric is null or p_register_view is null
    or char_length(coalesce(p_search,'')) > 300
    or p_sort not in ('updated_desc', 'updated_asc')
    or p_metric not in (
      'all', 'open', 'in_progress', 'dispatched', 'received', 'closed'
    )
    or p_register_view not in (
      'total', 'mine', 'assigned', 'my_work', 'exceptions'
    ) then
    raise exception 'V1_MATERIAL_REQUEST_SUMMARY_LIST_DENIED'
      using errcode = '42501';
  end if;
  if p_project_id is not null
    and not public.v1_project_readable(p_project_id) then
    raise exception 'V1_MATERIAL_REQUEST_PROJECT_NOT_READABLE'
      using errcode = '42501';
  end if;

  with
  active_memberships as materialized (
    select member.project_id,
      bool_or(member.project_role = 'project_engineer') as is_project_engineer,
      bool_or(member.project_role = 'site_engineer') as is_site_engineer,
      true as has_membership
    from public.v1_project_members member
    where member.member_auth_user_id = v_actor
      and member.effective_from <= v_now
      and (member.effective_to is null or member.effective_to > v_now)
    group by member.project_id
  ),
  project_candidates as materialized (
    select distinct request_record.project_id
    from public.v1_material_requests request_record
    where p_request_kind in ('all', 'project')
      and (p_project_id is null or request_record.project_id = p_project_id)
  ),
  project_permissions as materialized (
    select candidate.project_id,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'material_requests.view', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_view,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'material_requests.edit', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_edit,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'material_requests.approve', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_approve,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'material_requests.return_for_changes', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_return,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'procurement.arrange', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_arrange,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'dispatch.create', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_dispatch,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'receipts.confirm', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_confirm_receipt,
      coalesce((public.v1_permission_authoritative_resolution(
        v_actor, 'material_requests.close', candidate.project_id
      ) ->> 'effective')::boolean, false) as can_close
    from project_candidates candidate
  ),
  project_has_arrangement as materialized (
    select arrangement.request_id, true as has_arrangement
    from public.v1_procurement_arrangements arrangement
    join public.v1_material_requests request_record
      on request_record.id = arrangement.request_id
    where p_request_kind in ('all', 'project')
      and (p_project_id is null or request_record.project_id = p_project_id)
    group by arrangement.request_id
  ),
  project_request_seed as materialized (
    select request_record.*,
      project.project_ref,
      project.name as project_name,
      project.job_contract_reference,
      project.state as project_state,
      scope.name as scope_name,
      permission.can_view,
      permission.can_edit,
      permission.can_approve,
      permission.can_return,
      permission.can_arrange,
      permission.can_dispatch,
      permission.can_confirm_receipt,
      permission.can_close,
      coalesce(membership.has_membership, false) as has_membership,
      coalesce(membership.is_project_engineer, false) as is_project_engineer,
      coalesce(membership.is_site_engineer, false) as is_site_engineer,
      coalesce(arrangement.has_arrangement, false) as has_arrangement
    from public.v1_material_requests request_record
    join public.v1_projects project on project.id = request_record.project_id
    join public.v1_project_scopes scope on scope.id = request_record.scope_id
    join project_permissions permission
      on permission.project_id = request_record.project_id
    left join active_memberships membership
      on membership.project_id = request_record.project_id
    left join project_has_arrangement arrangement
      on arrangement.request_id = request_record.id
    where p_request_kind in ('all', 'project')
      and (p_project_id is null or request_record.project_id = p_project_id)
  ),
  project_participants as materialized (
    select seed.*,
      exists (
        select 1
        from public.v1_material_request_work_assignments assignment
        where assignment.request_id = seed.id
          and assignment.assignee_auth_user_id = v_actor
      ) as assigned_to_actor,
      (
        v_exact_role in (
          'project_engineer', 'senior_mechanical_engineer', 'project_manager',
          'workshop_in_charge', 'document_controller', 'admin'
        )
        and (v_allow_self_approval
          or seed.created_by_auth_user_id <> v_actor)
        and (
          v_exact_role = 'admin'
          or v_exact_role in (
            'senior_mechanical_engineer', 'project_manager',
            'workshop_in_charge', 'document_controller'
          )
          or (v_exact_role = 'project_engineer'
            and seed.is_project_engineer)
        )
        and (seed.can_approve or seed.can_return)
      ) as can_decide_request,
      (
        not seed.has_arrangement
        and (
          seed.created_by_auth_user_id = v_actor
          or v_exact_role = 'admin'
          or v_exact_role in (
            'senior_mechanical_engineer', 'project_manager',
            'workshop_in_charge', 'document_controller'
          )
          or (v_exact_role = 'project_engineer'
            and seed.is_project_engineer)
        )
        and seed.can_edit
      ) as can_edit_standard,
      (
        seed.post_approval_edit_enabled
        and seed.post_approval_amendment_pending
        and not seed.has_arrangement
        and (
          (
            v_exact_role in (
              'project_engineer', 'senior_mechanical_engineer',
              'project_manager', 'workshop_in_charge',
              'document_controller', 'admin'
            )
            and (v_allow_self_approval
              or seed.created_by_auth_user_id <> v_actor)
            and (
              v_exact_role = 'admin'
              or v_exact_role in (
                'senior_mechanical_engineer', 'project_manager',
                'workshop_in_charge', 'document_controller'
              )
              or (v_exact_role = 'project_engineer'
                and seed.is_project_engineer)
            )
            and seed.can_approve
          )
          or (
            v_exact_role = 'procurement'
            and (seed.procurement_role_edit_enabled
              or seed.procurement_editor_auth_user_id = v_actor)
            and seed.can_arrange
          )
        )
      ) as can_edit_post_approval
    from project_request_seed seed
    where seed.can_view and (
      v_exact_role = 'admin'
      or (seed.state = 'draft'
        and seed.created_by_auth_user_id = v_actor)
      or (seed.state <> 'draft' and v_exact_role in (
        'senior_mechanical_engineer', 'project_manager',
        'workshop_in_charge', 'document_controller'
      ))
      or (seed.state <> 'draft'
        and v_exact_role in ('project_engineer', 'site_engineer')
        and seed.has_membership)
      or (v_exact_role = 'procurement' and (
        seed.state in (
          'submitted', 'approved_for_arrangement', 'arranging',
          'awaiting_approval', 'approved', 'partially_dispatched',
          'dispatched', 'partially_received', 'received', 'closed',
          'cancelled'
        )
        or (
          seed.post_approval_amendment_pending
          and seed.post_approval_edit_enabled
          and (seed.procurement_role_edit_enabled
            or seed.procurement_editor_auth_user_id = v_actor)
          and seed.state in (
            'awaiting_request_approval', 'changes_requested'
          )
          and not seed.has_arrangement
        )
      ))
    )
  ),
  project_arrangement_exceptions as materialized (
    select participant.id as request_id,
      bool_or(line.decision = 'unavailable') as has_unavailable,
      bool_or(line.decision = 'partial') as has_partial,
      bool_or(line.source_kind = 'external_supplier'
        and line.external_source_ready is false
        and line.external_expected_date < current_date) as has_late_external
    from project_participants participant
    join public.v1_procurement_arrangements arrangement
      on arrangement.request_id = participant.id and arrangement.is_current
    join public.v1_procurement_arrangement_lines line
      on line.arrangement_id = arrangement.id
    where participant.state not in ('closed', 'cancelled')
    group by participant.id
  ),
  project_receipts_by_line as materialized (
    select dispatch_line.request_line_id,
      coalesce(sum(review_line.good_qty), 0::numeric) as good_qty,
      coalesce(sum(review_line.missing_qty), 0::numeric) as missing_qty,
      coalesce(sum(review_line.damaged_qty), 0::numeric) as damaged_qty
    from public.v1_receipt_review_lines review_line
    join public.v1_receipt_reviews review
      on review.id = review_line.receipt_review_id
      and review.state = 'confirmed'
    join public.v1_material_dispatch_lines dispatch_line
      on dispatch_line.id = review_line.dispatch_line_id
    join public.v1_material_request_lines request_line
      on request_line.id = dispatch_line.request_line_id
    join project_participants participant
      on participant.id = request_line.request_id
      and participant.state not in ('closed', 'cancelled')
    group by dispatch_line.request_line_id
  ),
  project_receipt_exceptions as materialized (
    select participant.id as request_id,
      bool_or(coalesce(receipt.missing_qty, 0::numeric) > 0
        and coalesce(approval.approved_qty, 0::numeric)
          - coalesce(receipt.good_qty, 0::numeric) > 0) as has_missing,
      bool_or(coalesce(receipt.damaged_qty, 0::numeric) > 0
        and coalesce(approval.approved_qty, 0::numeric)
          - coalesce(receipt.good_qty, 0::numeric) > 0) as has_damaged,
      bool_or(least(
        coalesce(receipt.missing_qty, 0::numeric)
          + coalesce(receipt.damaged_qty, 0::numeric),
        greatest(coalesce(approval.approved_qty, 0::numeric)
          - coalesce(receipt.good_qty, 0::numeric), 0::numeric)
      ) > 0) as has_replacement
    from project_participants participant
    join public.v1_material_request_lines request_line
      on request_line.request_id = participant.id
    left join public.v1_material_request_line_approvals approval
      on approval.request_line_id = request_line.id
    left join project_receipts_by_line receipt
      on receipt.request_line_id = request_line.id
    where participant.state not in ('closed', 'cancelled')
    group by participant.id
  ),
  project_return_exceptions as materialized (
    select participant.id as request_id, true as has_overdue_return
    from project_participants participant
    join public.v1_material_returns material_return
      on material_return.request_id = participant.id
      and material_return.requested_return_date < current_date
      and material_return.state not in ('confirmed', 'rejected', 'cancelled')
    group by participant.id
  ),
  project_readable as materialized (
    select participant.id, participant.project_id, participant.scope_id,
      participant.state, participant.record_version,
      participant.request_number, participant.title, participant.timing,
      participant.scheduled_date, participant.delivery_note,
      participant.requester_display_name, participant.requester_project_role,
      participant.requester_exact_role,
      participant.current_action_owner_role,
      participant.current_action_code, participant.submitted_at,
      participant.created_at, participant.updated_at,
      participant.created_by_auth_user_id, participant.project_ref,
      participant.project_name, participant.job_contract_reference,
      participant.scope_name, 'project'::text as request_kind,
      null::text as category_name, null::text as responsible_unit_name,
      participant.assigned_to_actor,
      case
        when participant.state = 'draft'
          then participant.created_by_auth_user_id = v_actor
        when participant.state in ('submitted', 'awaiting_request_approval')
          then participant.can_decide_request
        when participant.state = 'changes_requested'
          then participant.can_edit_standard
            or participant.can_edit_post_approval
        when participant.state in ('approved_for_arrangement', 'arranging')
          then v_exact_role in ('procurement', 'admin')
            and participant.project_state in ('active', 'on_hold')
            and participant.can_arrange
        when participant.state = 'awaiting_approval'
          then v_role = 'admin'
            or (v_role = 'project_engineer'
              and participant.is_project_engineer)
        when participant.current_action_code = 'receipt_review_required'
          or participant.state = 'dispatched'
          then participant.project_state in ('active', 'on_hold', 'completed')
            and (
              v_exact_role = 'admin'
              or v_exact_role in (
                'senior_mechanical_engineer', 'project_manager',
                'workshop_in_charge', 'document_controller'
              )
              or (v_exact_role in ('project_engineer', 'site_engineer')
                and participant.has_membership)
            )
            and participant.can_confirm_receipt
        when participant.current_action_code = 'material_request_close_review'
          or participant.state = 'received'
          then (
            v_exact_role = 'admin'
            or v_exact_role in (
              'senior_mechanical_engineer', 'project_manager',
              'workshop_in_charge', 'document_controller'
            )
            or (v_exact_role = 'project_engineer'
              and participant.is_project_engineer)
            or (v_exact_role = 'site_engineer'
              and participant.is_site_engineer)
          ) and participant.can_close
        when participant.state in (
          'approved', 'partially_dispatched', 'partially_received'
        ) then v_role in ('procurement', 'admin')
          and participant.project_state = 'active'
          and participant.can_dispatch
        else false
      end as actor_can_act,
      array_remove(array[
          case when coalesce(arrangement.has_unavailable, false)
            then 'unavailable_supply' end,
          case when coalesce(arrangement.has_partial, false)
            then 'partial_arrangement' end,
          case when coalesce(arrangement.has_late_external, false)
            then 'late_external_supply' end,
          case when coalesce(receipt.has_missing, false)
            then 'missing_receipt' end,
          case when coalesce(receipt.has_damaged, false)
            then 'damaged_receipt' end,
          case when coalesce(receipt.has_replacement, false)
            then 'replacement_required' end,
          case when coalesce(material_return.has_overdue_return, false)
            then 'overdue_return' end
        ], null) as exception_codes
    from project_participants participant
    left join project_arrangement_exceptions arrangement
      on arrangement.request_id = participant.id
    left join project_receipt_exceptions receipt
      on receipt.request_id = participant.id
    left join project_return_exceptions material_return
      on material_return.request_id = participant.id
  ),
  company_approved_requests as materialized (
    select decision.request_id
    from public.v1_company_material_request_decisions decision
    where decision.decision = 'approved'
    group by decision.request_id
  ),
  company_submitted_returns as materialized (
    select material_return.request_id
    from public.v1_company_material_returns material_return
    where material_return.state = 'submitted'
    group by material_return.request_id
  ),
  company_approver_authorizations as materialized (
    select authorization_record.category_id,
      authorization_record.responsible_unit_id
    from public.v1_company_material_request_authorizations authorization_record
    join public.v1_profiles profile
      on profile.auth_user_id = authorization_record.auth_user_id
      and profile.is_active
    join auth.users auth_user
      on auth_user.id = profile.auth_user_id
      and auth_user.deleted_at is null
      and (auth_user.banned_until is null
        or auth_user.banned_until <= statement_timestamp())
    join public.v1_company_material_request_categories category
      on category.id = authorization_record.category_id and category.is_active
    join public.v1_company_material_request_units unit_record
      on unit_record.id = authorization_record.responsible_unit_id
      and unit_record.is_active
    left join public.v1_company_material_request_staff_policy_events event
      on event.authorization_id = authorization_record.id
    left join public.v1_company_material_request_staff_policies policy
      on policy.id = event.policy_id
    where authorization_record.auth_user_id = v_actor
      and authorization_record.authority = 'approver'
      and authorization_record.effective_from <= current_date
      and (authorization_record.effective_to is null
        or authorization_record.effective_to >= current_date)
      and v_exact_role in (
        'project_engineer', 'senior_mechanical_engineer', 'project_manager',
        'workshop_in_charge', 'document_controller', 'admin'
      )
      and profile.canonical_role_snapshot = v_role
      and (event.id is null or (
        policy.is_active and policy.effective_from <= current_date
        and (policy.effective_to is null
          or policy.effective_to >= current_date)
      ))
    group by authorization_record.category_id,
      authorization_record.responsible_unit_id
  ),
  company_request_seed as materialized (
    select request_record.*, category.display_name as category_name,
      unit_record.display_name as responsible_unit_name,
      approved.request_id is not null as has_approved_decision,
      submitted_return.request_id is not null as has_submitted_return,
      approver_auth.category_id is not null as actor_has_approver_authorization
    from public.v1_company_material_requests request_record
    join public.v1_company_material_request_categories category
      on category.id = request_record.category_id
    join public.v1_company_material_request_units unit_record
      on unit_record.id = request_record.responsible_unit_id
    left join company_approved_requests approved
      on approved.request_id = request_record.id
    left join company_submitted_returns submitted_return
      on submitted_return.request_id = request_record.id
    left join company_approver_authorizations approver_auth
      on approver_auth.category_id = request_record.category_id
      and approver_auth.responsible_unit_id = request_record.responsible_unit_id
    where p_project_id is null and p_request_kind in ('all', 'company')
  ),
  company_participants as materialized (
    select seed.*
    from company_request_seed seed
    where seed.created_by_auth_user_id = v_actor
      or (seed.submitted_at is not null and (
        v_exact_role = 'admin'
        or v_actor in (
          seed.beneficiary_auth_user_id,
          seed.authorized_receiver_auth_user_id,
          seed.approver_auth_user_id
        )
      ))
      or (v_role = 'procurement' and (
        seed.state in (
          'approved_for_procurement', 'arranging', 'ready_for_delivery',
          'partially_dispatched', 'receipt_pending', 'partially_received',
          'awaiting_beneficiary_handover', 'fulfilled', 'closed'
        )
        or seed.has_approved_decision
      ))
  ),
  company_supply_exceptions as materialized (
    select participant.id as request_id,
      bool_or(line.decision = 'unavailable') as has_unavailable,
      bool_or(line.decision = 'partial') as has_partial
    from company_participants participant
    join public.v1_company_material_supply_plans plan
      on plan.request_id = participant.id and plan.is_current
    join public.v1_company_material_supply_lines line
      on line.plan_id = plan.id
    where participant.state not in ('draft', 'closed', 'cancelled', 'rejected')
    group by participant.id
  ),
  company_readable as materialized (
    select participant.id, null::uuid as project_id, null::uuid as scope_id,
      participant.state, participant.record_version,
      participant.request_number, participant.purpose as title,
      participant.timing, participant.scheduled_date,
      null::text as delivery_note, participant.requester_display_name,
      null::text as requester_project_role, participant.requester_exact_role,
      case
        when participant.state in (
          'awaiting_company_approval', 'submitted_pending_approval'
        ) then 'company_approver'
        when participant.state in (
          'approved_for_procurement', 'arranging', 'ready_for_delivery',
          'partially_dispatched', 'partially_received'
        ) then 'procurement'
        when participant.state = 'receipt_pending'
          then 'authorized_receiver'
        when participant.state = 'awaiting_beneficiary_handover'
          then 'beneficiary'
        when participant.state in ('closed', 'cancelled', 'rejected')
          then null
        else 'requester'
      end as current_action_owner_role,
      case
        when participant.state in (
          'awaiting_company_approval', 'submitted_pending_approval'
        ) then 'approve'
        when participant.state in (
          'approved_for_procurement', 'arranging', 'partially_received'
        ) then 'arrange'
        when participant.state in ('ready_for_delivery', 'partially_dispatched')
          then 'dispatch'
        when participant.state = 'receipt_pending' then 'receive'
        when participant.state = 'awaiting_beneficiary_handover'
          then 'handover'
        when participant.state = 'fulfilled' then 'close'
        when participant.state = 'returned_for_changes' then 'revise'
        else null
      end as current_action_code,
      participant.submitted_at, participant.created_at,
      participant.updated_at, participant.created_by_auth_user_id,
      null::text as project_ref, null::text as project_name,
      null::text as job_contract_reference, null::text as scope_name,
      'company'::text as request_kind, participant.category_name,
      participant.responsible_unit_name,
      participant.approver_auth_user_id = v_actor as assigned_to_actor,
      (
        (participant.state = 'awaiting_company_approval'
          and participant.approver_auth_user_id = v_actor
          and participant.beneficiary_auth_user_id <> v_actor
          and participant.authorized_receiver_auth_user_id <> v_actor
          and participant.actor_has_approver_authorization)
        or (participant.state = 'returned_for_changes'
          and participant.created_by_auth_user_id = v_actor)
        or (v_role = 'procurement' and (
          participant.state in (
            'approved_for_procurement', 'arranging', 'ready_for_delivery',
            'partially_dispatched', 'partially_received'
          ) or participant.has_submitted_return
        ))
        or (participant.state = 'receipt_pending'
          and participant.authorized_receiver_auth_user_id = v_actor)
        or (participant.state = 'awaiting_beneficiary_handover'
          and v_actor in (
            participant.authorized_receiver_auth_user_id,
            participant.beneficiary_auth_user_id
          ))
        or (participant.state = 'fulfilled'
          and v_role <> 'procurement'
          and v_actor in (
            participant.created_by_auth_user_id,
            participant.authorized_receiver_auth_user_id,
            participant.approver_auth_user_id
          ))
      ) as actor_can_act,
      case when participant.state in (
        'draft', 'closed', 'cancelled', 'rejected'
      ) then '{}'::text[] else array_remove(array[
        case when coalesce(supply.has_unavailable, false)
          then 'unavailable_supply' end,
        case when coalesce(supply.has_partial, false)
          then 'partial_arrangement' end
      ], null) end as exception_codes
    from company_participants participant
    left join company_supply_exceptions supply
      on supply.request_id = participant.id
  ),
  readable as materialized (
    select * from project_readable
    union all
    select * from company_readable
  ),
  authorized as materialized (
    select * from readable request
    where p_register_view = 'total'
      or (p_register_view = 'mine'
        and request.created_by_auth_user_id = v_actor)
      or (p_register_view = 'assigned' and request.assigned_to_actor)
      or (p_register_view = 'my_work' and request.actor_can_act)
      or (p_register_view = 'exceptions'
        and cardinality(request.exception_codes) > 0)
  ),
  project_search_matches as materialized (
    select line.request_id
    from public.v1_material_request_lines line
    join project_participants participant on participant.id = line.request_id
    where v_search is not null
      and line.item_description ilike '%' || v_search || '%'
    group by line.request_id
  ),
  company_search_matches as materialized (
    select line.request_id
    from public.v1_company_material_request_lines line
    join company_participants participant on participant.id = line.request_id
    where v_search is not null
      and line.item_description ilike '%' || v_search || '%'
    group by line.request_id
  ),
  filtered as materialized (
    select * from authorized request
    where (p_states is null or request.state = any(p_states))
      and (p_scope_id is null or request.scope_id = p_scope_id)
      and (p_requester is null
        or request.requester_display_name = p_requester)
      and (p_updated_after is null or request.updated_at >= p_updated_after)
      and (not p_attention_only or (
        request.state not in ('draft', 'closed', 'cancelled', 'rejected') and (
          coalesce(request.current_action_code, '') <> ''
          or request.state in (
            'awaiting_request_approval', 'changes_requested',
            'submitted_pending_approval', 'awaiting_company_approval',
            'returned_for_changes', 'arranging', 'dispatched',
            'partially_dispatched', 'partially_received', 'received'
          )
        )
      ))
      and (p_metric = 'all'
        or (p_metric = 'open' and request.state in (
          'draft', 'submitted', 'awaiting_request_approval',
          'changes_requested', 'submitted_pending_approval',
          'awaiting_company_approval', 'returned_for_changes'
        ))
        or (p_metric = 'in_progress' and request.state not in (
          'draft', 'submitted', 'awaiting_request_approval',
          'changes_requested', 'submitted_pending_approval',
          'awaiting_company_approval', 'returned_for_changes',
          'partially_dispatched', 'dispatched', 'receipt_pending',
          'partially_received', 'received',
          'awaiting_beneficiary_handover', 'fulfilled', 'closed',
          'cancelled', 'rejected'
        ))
        or (p_metric = 'dispatched' and request.state in (
          'partially_dispatched', 'dispatched', 'receipt_pending'
        ))
        or (p_metric = 'received' and request.state in (
          'partially_received', 'received',
          'awaiting_beneficiary_handover', 'fulfilled'
        ))
        or (p_metric = 'closed'
          and request.state in ('closed', 'cancelled', 'rejected'))
      )
      and (v_search is null
        or request.request_number ilike '%' || v_search || '%'
        or coalesce(request.title, '') ilike '%' || v_search || '%'
        or request.project_ref ilike '%' || v_search || '%'
        or request.project_name ilike '%' || v_search || '%'
        or request.scope_name ilike '%' || v_search || '%'
        or request.category_name ilike '%' || v_search || '%'
        or request.responsible_unit_name ilike '%' || v_search || '%'
        or coalesce(request.requester_display_name, '')
          ilike '%' || v_search || '%'
        or (request.request_kind = 'project' and exists (
          select 1 from project_search_matches matched
          where matched.request_id = request.id
        ))
        or (request.request_kind = 'company' and exists (
          select 1 from company_search_matches matched
          where matched.request_id = request.id
        ))
      )
  ),
  page as materialized (
    select * from filtered request
    order by
      case when p_sort = 'updated_desc' then request.updated_at end desc,
      case when p_sort = 'updated_asc' then request.updated_at end asc,
      request.id, request.request_kind
    limit v_limit offset v_offset
  ),
  page_project_ids as materialized (
    select page.id from page where page.request_kind = 'project'
  ),
  page_company_ids as materialized (
    select page.id from page where page.request_kind = 'company'
  ),
  project_item_counts as materialized (
    select line.request_id, count(*)::integer as item_count
    from public.v1_material_request_lines line
    join page_project_ids page_id on page_id.id = line.request_id
    group by line.request_id
  ),
  company_item_counts as materialized (
    select line.request_id, count(*)::integer as item_count
    from public.v1_company_material_request_lines line
    join page_company_ids page_id on page_id.id = line.request_id
    group by line.request_id
  ),
  returned_decisions as materialized (
    select distinct on (decision.request_id)
      decision.request_id, decision.request_record_version
    from public.v1_material_request_decisions decision
    join page_project_ids page_id on page_id.id = decision.request_id
    where decision.decision = 'returned'
    order by decision.request_id, decision.created_at desc, decision.id desc
  ),
  after_revisions as materialized (
    select distinct on (revision.request_id)
      revision.request_id, revision.request_record_version,
      revision.title, revision.timing, revision.scheduled_date,
      revision.delivery_note, revision.lines
    from public.v1_material_request_revision_snapshots revision
    join returned_decisions returned
      on returned.request_id = revision.request_id
      and revision.request_record_version > returned.request_record_version
    order by revision.request_id, revision.request_record_version desc
  ),
  before_revisions as materialized (
    select distinct on (revision.request_id)
      revision.request_id, revision.request_record_version,
      revision.title, revision.timing, revision.scheduled_date,
      revision.delivery_note, revision.lines
    from public.v1_material_request_revision_snapshots revision
    join returned_decisions returned
      on returned.request_id = revision.request_id
      and revision.request_record_version <= returned.request_record_version
    join after_revisions after_revision
      on after_revision.request_id = revision.request_id
    order by revision.request_id, revision.request_record_version desc
  ),
  before_revision_lines as materialized (
    select revision.request_id, line ->> 'id' as line_id, line
    from before_revisions revision
    cross join lateral jsonb_array_elements(revision.lines) line
  ),
  after_revision_lines as materialized (
    select revision.request_id, line ->> 'id' as line_id, line
    from after_revisions revision
    cross join lateral jsonb_array_elements(revision.lines) line
  ),
  change_line_stats as materialized (
    select coalesce(before_line.request_id, after_line.request_id) as request_id,
      count(*) filter (where before_line.line_id is null)::integer
        as items_added,
      count(*) filter (where after_line.line_id is null)::integer
        as items_removed,
      count(*) filter (where before_line.line_id is not null
        and after_line.line_id is not null and (
          (before_line.line ->> 'requested_qty')::numeric
            is distinct from (after_line.line ->> 'requested_qty')::numeric
          or before_line.line ->> 'unit'
            is distinct from after_line.line ->> 'unit'
        ))::integer as quantity_or_unit_changed,
      count(*) filter (where before_line.line_id is not null
        and after_line.line_id is not null and (
          before_line.line ->> 'item_description'
            is distinct from after_line.line ->> 'item_description'
          or before_line.line ->> 'brand_origin'
            is distinct from after_line.line ->> 'brand_origin'
          or before_line.line -> 'technical_attributes'
            is distinct from after_line.line -> 'technical_attributes'
        ))::integer as description_changed
    from before_revision_lines before_line
    full join after_revision_lines after_line
      on after_line.request_id = before_line.request_id
      and after_line.line_id = before_line.line_id
    group by coalesce(before_line.request_id, after_line.request_id)
  ),
  change_summaries as materialized (
    select before_revision.request_id,
      jsonb_build_object(
        'from_request_version', before_revision.request_record_version,
        'to_request_version', after_revision.request_record_version,
        'items_added', coalesce(stats.items_added, 0),
        'items_removed', coalesce(stats.items_removed, 0),
        'quantity_or_unit_changed',
          coalesce(stats.quantity_or_unit_changed, 0),
        'description_changed', coalesce(stats.description_changed, 0),
        'title_changed', before_revision.title
          is distinct from after_revision.title,
        'timing_changed', before_revision.timing
          is distinct from after_revision.timing
          or before_revision.scheduled_date
            is distinct from after_revision.scheduled_date,
        'delivery_note_changed', before_revision.delivery_note
          is distinct from after_revision.delivery_note
      ) as change_summary
    from before_revisions before_revision
    join after_revisions after_revision
      on after_revision.request_id = before_revision.request_id
    left join change_line_stats stats
      on stats.request_id = before_revision.request_id
  ),
  decorated_page as materialized (
    select page.*,
      case when page.request_kind = 'project'
        then coalesce(project_count.item_count, 0)
        else coalesce(company_count.item_count, 0)
      end as item_count,
      case when page.request_kind = 'project' then jsonb_build_object(
        'request_id', page.id,
        'assignment_version', coalesce(assignment.assignment_version, 0),
        'assignee_auth_user_id', assignment.assignee_auth_user_id,
        'assignee_display_name', assignment.assignee_display_name_snapshot,
        'assignee_exact_role', assignment.assignee_exact_role,
        'assigned_at', assignment.assigned_at,
        'can_manage', page.state not in ('draft', 'closed', 'cancelled')
          and (
            v_role = 'admin'
            or (page.current_action_owner_role = 'project_engineer'
              and v_role = 'project_engineer')
            or (page.current_action_owner_role = 'site_engineer'
              and v_role in ('site_engineer', 'project_engineer'))
            or (page.current_action_owner_role = 'procurement'
              and v_role = 'procurement')
          )
      ) else null end as work_assignment,
      case when page.request_kind = 'project'
        then change.change_summary else null end as change_summary
    from page
    left join project_item_counts project_count
      on page.request_kind = 'project' and project_count.request_id = page.id
    left join company_item_counts company_count
      on page.request_kind = 'company' and company_count.request_id = page.id
    left join public.v1_material_request_work_assignments assignment
      on page.request_kind = 'project' and assignment.request_id = page.id
    left join change_summaries change
      on page.request_kind = 'project' and change.request_id = page.id
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'request_kind', page.request_kind,
        'category_name', page.category_name,
        'responsible_unit_name', page.responsible_unit_name,
        'project_id', page.project_id,
        'project_ref', page.project_ref,
        'project_name', page.project_name,
        'job_contract_reference', page.job_contract_reference,
        'scope_id', page.scope_id,
        'scope_name', page.scope_name,
        'state', page.state,
        'record_version', page.record_version,
        'request_number', page.request_number,
        'title', page.title,
        'timing', page.timing,
        'scheduled_date', page.scheduled_date,
        'delivery_note', page.delivery_note,
        'requester_display_name', page.requester_display_name,
        'requester_project_role', page.requester_project_role,
        'requester_exact_role', page.requester_exact_role,
        'current_action_owner_role', page.current_action_owner_role,
        'current_action_code', page.current_action_code,
        'current_action_started_at', page.updated_at,
        'current_action_age_hours', greatest(
          extract(epoch from (v_now - page.updated_at)) / 3600, 0
        ),
        'required_on_site_overdue', page.timing = 'scheduled'
          and page.scheduled_date < current_date
          and page.state not in (
            'received', 'fulfilled', 'closed', 'cancelled', 'rejected'
          ),
        'actor_can_act', page.actor_can_act,
        'exception_codes', to_jsonb(page.exception_codes),
        'item_count', page.item_count,
        'work_assignment', page.work_assignment,
        'change_summary', page.change_summary,
        'submitted_at', page.submitted_at,
        'created_at', page.created_at,
        'updated_at', page.updated_at
      ) order by
        case when p_sort = 'updated_desc' then page.updated_at end desc,
        case when p_sort = 'updated_asc' then page.updated_at end asc,
        page.id, page.request_kind)
      from decorated_page page
    ), '[]'::jsonb),
    'total_count', (select count(*) from filtered),
    'limit', v_limit,
    'offset', v_offset,
    'has_more', v_offset + (select count(*) from page)
      < (select count(*) from filtered),
    'metrics', (select jsonb_build_object(
      'total', count(*),
      'open', count(*) filter (where state in (
        'draft', 'submitted', 'awaiting_request_approval',
        'changes_requested', 'submitted_pending_approval',
        'awaiting_company_approval', 'returned_for_changes'
      )),
      'in_progress', count(*) filter (where state not in (
        'draft', 'submitted', 'awaiting_request_approval',
        'changes_requested', 'submitted_pending_approval',
        'awaiting_company_approval', 'returned_for_changes',
        'partially_dispatched', 'dispatched', 'receipt_pending',
        'partially_received', 'received',
        'awaiting_beneficiary_handover', 'fulfilled', 'closed',
        'cancelled', 'rejected'
      )),
      'dispatched', count(*) filter (where state in (
        'partially_dispatched', 'dispatched', 'receipt_pending'
      )),
      'received', count(*) filter (where state in (
        'partially_received', 'received',
        'awaiting_beneficiary_handover', 'fulfilled'
      )),
      'closed', count(*) filter (
        where state in ('closed', 'cancelled', 'rejected')
      ),
      'my_work', count(*) filter (where actor_can_act),
      'exceptions', count(*) filter (
        where cardinality(exception_codes) > 0
      ),
      'required_date_overdue', count(*) filter (
        where timing = 'scheduled'
          and scheduled_date < current_date
          and state not in (
            'received', 'fulfilled', 'closed', 'cancelled', 'rejected'
          )
      )
    ) from readable)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.v1_list_unified_material_request_summaries(
  uuid, text, text[], uuid, text, timestamptz, boolean, text, text, integer,
  integer, text, text
) from public, anon, authenticated;
grant execute on function public.v1_list_unified_material_request_summaries(
  uuid, text, text[], uuid, text, timestamptz, boolean, text, text, integer,
  integer, text, text
) to authenticated, service_role;

comment on function public.v1_list_unified_material_request_summaries(
  uuid, text, text[], uuid, text, timestamptz, boolean, text, text, integer,
  integer, text, text
) is 'Set-based authorized Project and Company MR union; stable combined paging/counts, native states, no commercial fields or Company Project identities.';

notify pgrst, 'reload schema';

commit;

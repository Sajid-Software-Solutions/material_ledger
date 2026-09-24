-- Yorks V1: explicit, revocable editing window after Engineering approval.
-- Existing grants are off by default. No historical line, commercial, decision,
-- arrangement, stock, document or audit row is migrated or discarded.
-- Rollback is forward-only: revoke grants with the audited RPC and deploy a
-- corrective migration; never remove committed amendment/decision history.
begin;

alter table public.v1_material_requests
  add column if not exists post_approval_edit_enabled boolean not null default false,
  add column if not exists procurement_editor_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  add column if not exists post_approval_amendment_pending boolean not null default false;

alter table public.v1_material_requests
  drop constraint if exists v1_material_requests_post_approval_edit_grant_check;
alter table public.v1_material_requests
  add constraint v1_material_requests_post_approval_edit_grant_check check (
    post_approval_edit_enabled or procurement_editor_auth_user_id is null
  );

alter table public.v1_material_request_revision_snapshots
  drop constraint if exists
    v1_material_request_revision_snapshots_snapshot_reason_check;
alter table public.v1_material_request_revision_snapshots
  add constraint v1_material_request_revision_snapshots_snapshot_reason_check
  check (snapshot_reason in (
    'submitted_for_approval', 'legacy_baseline', 'post_approval_amendment'
  ));

create or replace function public.v1_material_request_capture_revision()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text;
begin
  if new.state <> 'awaiting_request_approval'
    or (tg_op = 'UPDATE'
      and old.record_version = new.record_version
      and old.state = new.state) then return new; end if;
  if v_actor is not null then
    v_exact_role := public.v1_current_exact_role();
  end if;
  insert into public.v1_material_request_revision_snapshots (
    request_id, request_record_version, snapshot_reason, title, timing,
    scheduled_date, delivery_note, lines, captured_by_auth_user_id,
    captured_by_exact_role, captured_at
  ) values (
    new.id, new.record_version,
    case when new.post_approval_amendment_pending
      then 'post_approval_amendment' else 'submitted_for_approval' end,
    new.title, new.timing, new.scheduled_date, new.delivery_note,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', line.id, 'display_order', line.display_order,
      'source_kind', line.source_kind,
      'source_boq_group_id', line.source_boq_group_id,
      'source_boq_row_id', line.source_boq_row_id,
      'item_description', line.item_description,
      'brand_origin', line.brand_origin,
      'technical_attributes', coalesce(line.technical_attributes, '{}'::jsonb),
      'requested_qty', line.requested_qty, 'unit', line.unit
    ) order by line.display_order, line.id)
    from public.v1_material_request_lines line
    where line.request_id = new.id), '[]'::jsonb),
    v_actor, v_exact_role, clock_timestamp()
  ) on conflict (request_id, request_record_version) do nothing;
  return new;
end;
$$;

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
      'workshop_in_charge', 'document_controller', 'admin'
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
  ) or (v_role = 'project_engineer' and
    public.v1_has_active_project_membership(
      v_request.project_id, auth.uid(), 'project_engineer'
    ))) and public.v1_current_user_has_capability(
      'material_requests.approve', v_request.project_id
    );
end;
$$;

create or replace function public.v1_can_edit_material_request_post_approval(
  p_request_id uuid
) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_request public.v1_material_requests%rowtype;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    return false;
  end if;
  select * into v_request from public.v1_material_requests
  where id = p_request_id;
  if not found or not v_request.post_approval_edit_enabled
    or (v_request.state <> 'approved_for_arrangement'
      and not (v_request.post_approval_amendment_pending
        and v_request.state in ('awaiting_request_approval', 'changes_requested')))
    or exists (select 1 from public.v1_procurement_arrangements
      where request_id = p_request_id) then return false; end if;
  if public.v1_can_manage_material_request_post_approval_edit(p_request_id) then
    return true;
  end if;
  return public.v1_current_exact_role() = 'procurement'
    and auth.uid() = v_request.procurement_editor_auth_user_id
    and public.v1_current_user_has_capability(
      'procurement.arrange', v_request.project_id
    );
end;
$$;

create or replace function public.v1_set_material_request_post_approval_edit(
  p_payload jsonb, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_request_id uuid;
  v_expected_version integer;
  v_enabled boolean;
  v_editor uuid;
  v_request public.v1_material_requests%rowtype;
  v_existing jsonb;
  v_before jsonb;
  v_response jsonb;
begin
  perform public.v1_assert_object_keys(p_payload,
    array['request_id', 'expected_version', 'enabled',
      'procurement_editor_auth_user_id'], 'set_material_request_post_approval_edit');
  v_request_id := nullif(p_payload ->> 'request_id', '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_enabled := (p_payload ->> 'enabled')::boolean;
  v_editor := nullif(p_payload ->> 'procurement_editor_auth_user_id', '')::uuid;
  if v_request_id is null or v_expected_version is null or v_expected_version < 1
    or v_enabled is null or (not v_enabled and v_editor is not null) then
    raise exception 'V1_POST_APPROVAL_EDIT_GRANT_INVALID' using errcode = '22023';
  end if;
  select * into v_request from public.v1_material_requests
    where id = v_request_id for update;
  if not found or not public.v1_can_manage_material_request_post_approval_edit(
    v_request_id) then
    raise exception 'V1_POST_APPROVAL_EDIT_GRANT_DENIED' using errcode = '42501';
  end if;
  if v_editor is not null and not exists (
    select 1 from public.v1_profiles profile
    join auth.users user_record on user_record.id = profile.auth_user_id
    where profile.auth_user_id = v_editor and profile.is_active
      and user_record.raw_app_meta_data ->> 'role' = 'procurement'
      and coalesce((public.v1_permission_authoritative_resolution(
        v_editor, 'procurement.arrange', v_request.project_id
      ) ->> 'effective')::boolean, false)
  ) then
    raise exception 'V1_POST_APPROVAL_EDIT_EDITOR_INVALID' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_set_material_request_post_approval_edit', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
  if v_request.record_version <> v_expected_version then
    perform public.v1_raise_version_conflict('V1_MATERIAL_REQUEST_VERSION_CONFLICT');
  end if;
  v_before := public.v1_material_request_projection(v_request_id);
  update public.v1_material_requests set
    post_approval_edit_enabled = v_enabled,
    procurement_editor_auth_user_id = v_editor,
    record_version = record_version + 1,
    updated_at = clock_timestamp()
  where id = v_request_id;
  v_response := public.v1_material_request_projection(v_request_id);
  perform public.v1_write_audit_event(
    'material_request_post_approval_edit_grant_changed', 'material_request',
    v_request_id, v_request.project_id, v_before,
    jsonb_build_object('enabled', v_enabled,
      'procurement_editor_auth_user_id', v_editor,
      'record_version', v_expected_version + 1),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_set_material_request_post_approval_edit', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_list_material_request_procurement_editors(
  p_request_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_project_id uuid;
begin
  if not public.v1_can_manage_material_request_post_approval_edit(p_request_id) then
    raise exception 'V1_POST_APPROVAL_EDIT_EDITOR_LIST_DENIED' using errcode = '42501';
  end if;
  select project_id into v_project_id from public.v1_material_requests
    where id = p_request_id;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'auth_user_id', profile.auth_user_id,
    'display_name', public.v1_safe_profile_display_name(
      profile.display_name, profile.auth_user_id),
    'exact_role', 'procurement'
  ) order by lower(profile.display_name), profile.auth_user_id)
  from public.v1_profiles profile
  join auth.users user_record on user_record.id = profile.auth_user_id
  where profile.is_active and user_record.raw_app_meta_data ->> 'role' = 'procurement'
    and coalesce((public.v1_permission_authoritative_resolution(
      profile.auth_user_id, 'procurement.arrange', v_project_id
    ) ->> 'effective')::boolean, false)), '[]'::jsonb);
end;
$$;

create or replace function public.v1_material_request_participant(
  p_request_id uuid,
  p_auth_user_id uuid
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request public.v1_material_requests%rowtype;
  v_exact_role text;
  v_has_view boolean := false;
begin
  select * into v_request
  from public.v1_material_requests request_record
  where request_record.id = p_request_id;

  if not found or p_auth_user_id is null or not exists (
    select 1 from public.v1_profiles profile
    where profile.auth_user_id = p_auth_user_id and profile.is_active
  ) then
    return false;
  end if;

  v_has_view := coalesce((
    public.v1_permission_authoritative_resolution(
      p_auth_user_id, 'material_requests.view', v_request.project_id
    ) ->> 'effective'
  )::boolean, false);
  if not v_has_view then
    return false;
  end if;

  select coalesce(user_record.raw_app_meta_data ->> 'role', '')
    into v_exact_role
  from auth.users user_record
  where user_record.id = p_auth_user_id;

  if v_exact_role = 'admin' then
    return true;
  end if;
  if v_request.state = 'draft' then
    return v_request.created_by_auth_user_id = p_auth_user_id;
  end if;
  if v_exact_role in (
    'senior_mechanical_engineer', 'project_manager',
    'workshop_in_charge', 'document_controller'
  ) then
    return true;
  end if;
  if v_exact_role in ('project_engineer', 'site_engineer') then
    return exists (
      select 1 from public.v1_project_members member
      where member.project_id = v_request.project_id
        and member.member_auth_user_id = p_auth_user_id
        and member.effective_from <= clock_timestamp()
        and (
          member.effective_to is null
          or member.effective_to > clock_timestamp()
        )
    );
  end if;
  if v_exact_role = 'procurement' then
    return v_request.state in (
      'submitted', 'approved_for_arrangement', 'arranging',
      'awaiting_approval', 'approved', 'partially_dispatched',
      'dispatched', 'partially_received', 'received', 'closed', 'cancelled'
    ) or (v_request.post_approval_amendment_pending
      and v_request.post_approval_edit_enabled
      and v_request.procurement_editor_auth_user_id = p_auth_user_id
      and v_request.state in ('awaiting_request_approval', 'changes_requested')
      and not exists (select 1 from public.v1_procurement_arrangements
        where request_id = p_request_id));
  end if;
  return false;
end;
$$;

create or replace function public.v1_material_request_readable(
  p_request_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.v1_current_actor_is_active()
    and (
      public.v1_material_request_participant(p_request_id, auth.uid())
      or (
        public.v1_can_arrange_material_request(p_request_id)
        and exists (
          select 1
          from public.v1_material_requests request_record
          where request_record.id = p_request_id
            and request_record.state = 'awaiting_request_approval'
            and request_record.procurement_clarification_revision
              > request_record.approved_procurement_clarification_revision
            and exists (
              select 1
              from public.v1_procurement_arrangements arrangement
              where arrangement.request_id = request_record.id
                and arrangement.status = 'working'
                and arrangement.saved_at is null
            )
        )
      )
    );
$$;

create or replace function public.v1_can_edit_material_request_before_approval(
  p_request_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request public.v1_material_requests%rowtype;
  v_exact_role text := public.v1_current_exact_role();
  v_legacy_allowed boolean := false;
begin
  if auth.uid() is null
    or v_exact_role = ''
    or not public.v1_current_actor_is_active() then
    return false;
  end if;

  select * into v_request
  from public.v1_material_requests request_record
  where request_record.id = p_request_id;
  if (v_request.state = 'approved_for_arrangement'
    or v_request.post_approval_amendment_pending)
    and public.v1_can_edit_material_request_post_approval(p_request_id) then
    return true;
  end if;
  if not found
    or v_request.state not in (
      'awaiting_request_approval', 'changes_requested'
    )
    or exists (
      select 1 from public.v1_procurement_arrangements arrangement
      where arrangement.request_id = p_request_id
    ) then
    return false;
  end if;

  if v_request.created_by_auth_user_id = auth.uid() then
    v_legacy_allowed := true;
  elsif v_exact_role = 'admin'
    or v_exact_role in (
      'senior_mechanical_engineer', 'project_manager',
      'workshop_in_charge', 'document_controller'
    ) then
    v_legacy_allowed := true;
  elsif v_exact_role = 'project_engineer' then
    v_legacy_allowed := public.v1_has_active_project_membership(
      v_request.project_id, auth.uid(), 'project_engineer'
    );
  end if;

  return v_legacy_allowed
    and public.v1_current_user_has_capability(
      'material_requests.edit', v_request.project_id
    );
end;
$$;

create or replace function public.v1_material_request_projection(
  p_request_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_include_commercial boolean := public.v1_has_capability('view_commercials');
  v_result jsonb;
begin
  if not public.v1_material_request_readable(p_request_id) then
    raise exception 'V1_MATERIAL_REQUEST_NOT_READABLE' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', request_record.id,
    'project_id', request_record.project_id,
    'project_ref', project.project_ref,
    'project_name', project.name,
    'job_contract_reference', project.job_contract_reference,
    'scope_id', request_record.scope_id,
    'scope_name', scope.name,
    'state', request_record.state,
    'record_version', request_record.record_version,
    'request_number', request_record.request_number,
    'title', request_record.title,
    'timing', request_record.timing,
    'scheduled_date', request_record.scheduled_date,
    'delivery_note', request_record.delivery_note,
    'requester_display_name', request_record.requester_display_name,
    'requester_project_role', request_record.requester_project_role,
    'requester_exact_role', request_record.requester_exact_role,
    'current_action_owner_role', request_record.current_action_owner_role,
    'current_action_code', request_record.current_action_code,
    'submitted_at', request_record.submitted_at,
    'cancelled_at', request_record.cancelled_at,
    'cancellation_reason', request_record.cancellation_reason,
    'created_at', request_record.created_at,
    'updated_at', request_record.updated_at,
    'can_edit_before_approval',
      public.v1_can_edit_material_request_before_approval(request_record.id),
    'post_approval_edit_enabled', request_record.post_approval_edit_enabled,
    'post_approval_amendment_pending', request_record.post_approval_amendment_pending,
    'procurement_editor_auth_user_id', request_record.procurement_editor_auth_user_id,
    'can_manage_post_approval_edit',
      case when request_record.state = 'approved_for_arrangement'
        or request_record.post_approval_amendment_pending
        then public.v1_can_manage_material_request_post_approval_edit(request_record.id)
        else false end,
    'can_edit_post_approval',
      case when request_record.post_approval_edit_enabled and (
        request_record.state = 'approved_for_arrangement'
        or request_record.post_approval_amendment_pending)
        then public.v1_can_edit_material_request_post_approval(request_record.id)
        else false end,
    'can_decide_request', public.v1_can_decide_material_request(request_record.id)
      and request_record.state = 'awaiting_request_approval',
    'request_decision', (
      select jsonb_build_object(
        'id', decision.id,
        'decision', decision.decision,
        'reason', decision.reason,
        'request_record_version', decision.request_record_version,
        'decided_by_display_name', decision.decided_by_display_name_snapshot,
        'decided_by_role', decision.decided_by_role,
        'decided_by_exact_role', decision.decided_by_exact_role,
        'decided_at', decision.created_at
      )
      from public.v1_material_request_decisions decision
      where decision.request_id = request_record.id
      order by decision.created_at desc, decision.id desc limit 1
    ),
    'comments', public.v1_material_request_comment_projection(request_record.id),
    'lines', coalesce((
      select jsonb_agg(public.v1_material_request_line_projection(
        line_record.id, v_include_commercial
      ) order by line_record.display_order)
      from public.v1_material_request_lines line_record
      where line_record.request_id = request_record.id
    ), '[]'::jsonb)
  ) into v_result
  from public.v1_material_requests request_record
  join public.v1_projects project on project.id = request_record.project_id
  join public.v1_project_scopes scope on scope.id = request_record.scope_id
  where request_record.id = p_request_id;
  return v_result;
end;
$$;

create or replace function public.v1_update_material_request_for_approval(
  p_payload jsonb,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
  v_expected_version integer;
  v_request public.v1_material_requests%rowtype;
  v_scope_id uuid;
  v_title text;
  v_timing text;
  v_scheduled_date date;
  v_delivery_note text;
  v_lines jsonb;
  v_line jsonb;
  v_line_id uuid;
  v_line_order integer;
  v_source_kind text;
  v_source_group_id uuid;
  v_source_row_id uuid;
  v_description text;
  v_technical_attributes jsonb;
  v_requested_qty numeric(18, 4);
  v_unit text;
  v_before jsonb;
  v_response jsonb;
  v_existing jsonb;
  v_order_offset integer;
  v_is_post_approval_amendment boolean;
begin
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'request_id', 'expected_version', 'project_id', 'scope_id', 'title',
      'timing', 'scheduled_date', 'delivery_note', 'lines'
    ],
    'update_material_request_for_approval'
  );
  v_request_id := nullif(btrim(coalesce(p_payload ->> 'request_id', '')), '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_scope_id := nullif(btrim(coalesce(p_payload ->> 'scope_id', '')), '')::uuid;
  v_title := nullif(btrim(coalesce(p_payload ->> 'title', '')), '');
  v_timing := coalesce(p_payload ->> 'timing', '');
  v_scheduled_date := nullif(p_payload ->> 'scheduled_date', '')::date;
  v_delivery_note := nullif(btrim(coalesce(p_payload ->> 'delivery_note', '')), '');
  v_lines := coalesce(p_payload -> 'lines', '[]'::jsonb);
  if v_request_id is null or v_expected_version is null or v_expected_version < 1
    or v_scope_id is null or v_timing not in ('urgent', 'normal', 'scheduled')
    or jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) = 0
    or (v_timing = 'scheduled' and v_scheduled_date is null)
    or (v_timing <> 'scheduled' and v_scheduled_date is not null) then
    raise exception 'V1_MATERIAL_REQUEST_APPROVAL_EDIT_INVALID'
      using errcode = '22023';
  end if;

  select * into v_request from public.v1_material_requests request_record
  where request_record.id = v_request_id for update;
  if not found or not public.v1_can_edit_material_request_before_approval(
    v_request_id
  ) then
    raise exception 'V1_MATERIAL_REQUEST_APPROVAL_EDIT_DENIED'
      using errcode = '42501';
  end if;
  if v_request.record_version <> v_expected_version then
    perform public.v1_raise_version_conflict('V1_MATERIAL_REQUEST_VERSION_CONFLICT');
  end if;
  if nullif(p_payload ->> 'project_id', '')::uuid <> v_request.project_id
    or not exists (
      select 1 from public.v1_project_scopes scope
      where scope.id = v_scope_id and scope.project_id = v_request.project_id
        and scope.is_active
    ) then
    raise exception 'V1_MATERIAL_REQUEST_SCOPE_INVALID' using errcode = '22023';
  end if;

  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    perform public.v1_assert_object_keys(
      v_line,
      array[
        'id', 'display_order', 'source_kind', 'source_boq_group_id',
        'source_boq_row_id', 'item_description', 'brand_origin',
        'technical_attributes', 'requested_qty', 'unit'
      ],
      'material_request_line'
    );
    v_line_id := nullif(btrim(coalesce(v_line ->> 'id', '')), '')::uuid;
    v_line_order := nullif(v_line ->> 'display_order', '')::integer;
    v_source_kind := coalesce(v_line ->> 'source_kind', '');
    v_source_group_id := nullif(v_line ->> 'source_boq_group_id', '')::uuid;
    v_source_row_id := nullif(v_line ->> 'source_boq_row_id', '')::uuid;
    v_description := nullif(btrim(coalesce(v_line ->> 'item_description', '')), '');
    v_technical_attributes := coalesce(v_line -> 'technical_attributes', '{}'::jsonb);
    v_requested_qty := nullif(v_line ->> 'requested_qty', '')::numeric(18, 4);
    v_unit := nullif(btrim(coalesce(v_line ->> 'unit', '')), '');
    if v_line_id is null or v_line_order is null or v_line_order < 1
      or v_source_kind not in ('boq', 'excel', 'custom')
      or v_description is null or v_requested_qty is null or v_requested_qty <= 0
      or v_unit is null or jsonb_typeof(v_technical_attributes) <> 'object' then
      raise exception 'V1_MATERIAL_REQUEST_LINE_INVALID' using errcode = '22023';
    end if;
    if v_source_kind = 'boq' then
      if v_source_group_id is null or v_source_row_id is null or not exists (
        select 1
        from public.v1_boq_groups group_record
        join public.v1_boq_rows row_record on row_record.group_id = group_record.id
        where group_record.id = v_source_group_id
          and group_record.project_id = v_request.project_id
          and group_record.scope_id = v_scope_id
          and not group_record.is_archived
          and row_record.id = v_source_row_id and not row_record.is_archived
      ) then
        raise exception 'V1_MATERIAL_REQUEST_BOQ_SOURCE_INVALID'
          using errcode = '22023';
      end if;
    elsif v_source_group_id is not null or v_source_row_id is not null then
      raise exception 'V1_MATERIAL_REQUEST_SOURCE_INVALID' using errcode = '22023';
    end if;
  end loop;
  if (select count(distinct (value ->> 'id')) from jsonb_array_elements(v_lines))
      <> jsonb_array_length(v_lines)
    or (select count(distinct (value ->> 'display_order'))
        from jsonb_array_elements(v_lines)) <> jsonb_array_length(v_lines) then
    raise exception 'V1_MATERIAL_REQUEST_LINES_DUPLICATE' using errcode = '22023';
  end if;

  v_existing := public.v1_idempotency_get_or_claim(
    'v1_update_material_request_for_approval', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
  v_is_post_approval_amendment := v_request.state = 'approved_for_arrangement'
    or v_request.post_approval_amendment_pending;
  v_before := public.v1_material_request_projection(v_request_id);

  -- Retain stable line IDs and their protected commercial relations. A removed
  -- line with any downstream FK fails atomically; no historical link is lost.
  if exists (
    select 1 from jsonb_array_elements(v_lines) incoming
    join public.v1_material_request_lines existing
      on existing.id = (incoming.value ->> 'id')::uuid
    where existing.request_id <> v_request_id
  ) then
    raise exception 'V1_MATERIAL_REQUEST_LINE_INVALID' using errcode = '22023';
  end if;
  delete from public.v1_material_request_lines existing
  where existing.request_id = v_request_id and not exists (
    select 1 from jsonb_array_elements(v_lines) incoming
    where (incoming.value ->> 'id')::uuid = existing.id
  );
  select coalesce(max(display_order), 0) + jsonb_array_length(v_lines) + 1
    into v_order_offset from public.v1_material_request_lines
    where request_id = v_request_id;
  update public.v1_material_request_lines
    set display_order = display_order + v_order_offset
    where request_id = v_request_id;
  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    if exists (select 1 from public.v1_material_request_lines
      where id = (v_line ->> 'id')::uuid and request_id = v_request_id) then
      update public.v1_material_request_lines set
        display_order = (v_line ->> 'display_order')::integer,
        source_kind = v_line ->> 'source_kind',
        source_boq_group_id = nullif(v_line ->> 'source_boq_group_id', '')::uuid,
        source_boq_row_id = nullif(v_line ->> 'source_boq_row_id', '')::uuid,
        item_description = btrim(v_line ->> 'item_description'),
        brand_origin = nullif(btrim(coalesce(v_line ->> 'brand_origin', '')), ''),
        technical_attributes = public.v1_material_request_normalized_technical_attributes(
          coalesce(v_line -> 'technical_attributes', '{}'::jsonb),
          v_line ->> 'source_kind'
        ),
        requested_qty = (v_line ->> 'requested_qty')::numeric(18, 4),
        unit = btrim(v_line ->> 'unit'),
        updated_at = clock_timestamp()
      where id = (v_line ->> 'id')::uuid and request_id = v_request_id;
    else
      insert into public.v1_material_request_lines (
        id, request_id, display_order, source_kind, source_boq_group_id,
        source_boq_row_id, item_description, brand_origin, technical_attributes,
        requested_qty, unit, created_at, updated_at
      ) values (
        (v_line ->> 'id')::uuid, v_request_id,
        (v_line ->> 'display_order')::integer, v_line ->> 'source_kind',
        nullif(v_line ->> 'source_boq_group_id', '')::uuid,
        nullif(v_line ->> 'source_boq_row_id', '')::uuid,
        btrim(v_line ->> 'item_description'),
        nullif(btrim(coalesce(v_line ->> 'brand_origin', '')), ''),
        public.v1_material_request_normalized_technical_attributes(
          coalesce(v_line -> 'technical_attributes', '{}'::jsonb),
          v_line ->> 'source_kind'
        ),
        (v_line ->> 'requested_qty')::numeric(18, 4),
        btrim(v_line ->> 'unit'), clock_timestamp(), clock_timestamp()
      );
    end if;
  end loop;
  update public.v1_material_requests
  set scope_id = v_scope_id,
      title = v_title,
      timing = v_timing,
      scheduled_date = v_scheduled_date,
      delivery_note = v_delivery_note,
      state = 'awaiting_request_approval',
      post_approval_amendment_pending = v_is_post_approval_amendment,
      current_action_owner_role = 'project_engineer',
      current_action_code = 'request_approval_required',
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = v_request_id;

  insert into public.v1_notifications (
    recipient_auth_user_id, event_code, entity_type, entity_id, project_id
  )
  select distinct member.member_auth_user_id, 'material_request_updated_for_approval',
    'material_request', v_request_id, v_request.project_id
  from public.v1_project_members member
  join public.v1_profiles profile on profile.auth_user_id = member.member_auth_user_id
  where member.project_id = v_request.project_id
    and member.project_role = 'project_engineer'
    and member.effective_from <= clock_timestamp()
    and (member.effective_to is null or member.effective_to > clock_timestamp())
    and profile.is_active and member.member_auth_user_id <> auth.uid();

  v_response := public.v1_material_request_projection(v_request_id);
  perform public.v1_write_audit_event(
    case when v_is_post_approval_amendment
      then 'material_request_post_approval_amendment_submitted'
      else 'material_request_updated_for_approval' end,
    'material_request', v_request_id,
    v_request.project_id, v_before,
    jsonb_build_object(
      'record_version', v_expected_version + 1,
      'line_count', jsonb_array_length(v_lines),
      'state', 'awaiting_request_approval'
    ), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_update_material_request_for_approval', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_clear_post_approval_amendment_on_approval()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.state = 'approved_for_arrangement' then
    new.post_approval_amendment_pending := false;
  end if;
  return new;
end;
$$;
drop trigger if exists v1_clear_post_approval_amendment_on_approval
  on public.v1_material_requests;
create trigger v1_clear_post_approval_amendment_on_approval
before update of state on public.v1_material_requests
for each row execute function public.v1_clear_post_approval_amendment_on_approval();


revoke all on function public.v1_can_manage_material_request_post_approval_edit(uuid),
  public.v1_can_edit_material_request_post_approval(uuid),
  public.v1_set_material_request_post_approval_edit(jsonb, uuid),
  public.v1_list_material_request_procurement_editors(uuid)
  from public, anon, authenticated;
grant execute on function public.v1_can_manage_material_request_post_approval_edit(uuid),
  public.v1_can_edit_material_request_post_approval(uuid),
  public.v1_set_material_request_post_approval_edit(jsonb, uuid),
  public.v1_list_material_request_procurement_editors(uuid)
  to service_role;
grant execute on function public.v1_set_material_request_post_approval_edit(jsonb, uuid),
  public.v1_list_material_request_procurement_editors(uuid)
  to authenticated;

commit;

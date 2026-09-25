-- Allow an approved Project MR to be saved while Procurement's first
-- arrangement is working but unsaved. The default-off approver grant remains
-- required; saved arrangements, reservations and downstream activity remain
-- closed to editing. No existing data is rewritten by this migration.
-- Rollback: revoke grants through the audited command and deploy corrective
-- functions; retain request revisions, audit and existing arrangement rows.
begin;

create or replace function public.v1_material_request_working_arrangement_editable(
  p_request_id uuid
) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.v1_procurement_arrangements arrangement
    join public.v1_material_requests request_record
      on request_record.id = arrangement.request_id
    where arrangement.request_id = p_request_id
      and request_record.state = 'arranging'
      and arrangement.status = 'working'
      and arrangement.saved_at is null
      and not exists (
        select 1 from public.v1_procurement_arrangements prior
        where prior.request_id = p_request_id and prior.id <> arrangement.id
      )
      and not exists (
        select 1 from public.v1_inventory_reservations reservation
        where reservation.request_id = p_request_id
      )
      and not exists (
        select 1 from public.v1_procurement_arrangement_lines line
        where line.arrangement_id = arrangement.id
          and (line.decision is not null or line.arranged_qty is not null
            or line.inventory_item_id is not null
            or line.external_supplier is not null)
      )
  );
$$;

revoke all on function
  public.v1_material_request_working_arrangement_editable(uuid)
  from public, anon, authenticated;
grant execute on function
  public.v1_material_request_working_arrangement_editable(uuid)
  to service_role;
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
    v_request.state not in ('approved_for_arrangement', 'arranging')
    and not (v_request.post_approval_amendment_pending
      and v_request.state in ('awaiting_request_approval', 'changes_requested'))
  ) or (v_request.state = 'arranging'
    and not public.v1_material_request_working_arrangement_editable(p_request_id))
    or (v_request.state <> 'arranging' and exists (
      select 1 from public.v1_procurement_arrangements
      where request_id = p_request_id
    )) then return false; end if;
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
    or (v_request.state not in ('approved_for_arrangement', 'arranging')
      and not (v_request.post_approval_amendment_pending
        and v_request.state in ('awaiting_request_approval', 'changes_requested')))
    or (v_request.state = 'arranging'
      and not public.v1_material_request_working_arrangement_editable(p_request_id))
    or (v_request.state <> 'arranging' and exists (
      select 1 from public.v1_procurement_arrangements
      where request_id = p_request_id)) then return false; end if;
  if public.v1_can_manage_material_request_post_approval_edit(p_request_id) then
    return true;
  end if;
  return public.v1_current_exact_role() = 'procurement'
    and (v_request.procurement_role_edit_enabled
      or coalesce(auth.uid() = v_request.procurement_editor_auth_user_id, false))
    and public.v1_current_user_has_capability(
      'procurement.arrange', v_request.project_id
    );
end;
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
  if (v_request.state in ('approved_for_arrangement', 'arranging')
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
    'procurement_role_edit_enabled', request_record.procurement_role_edit_enabled,
    'post_approval_edit_enabled', request_record.post_approval_edit_enabled,
    'post_approval_amendment_pending', request_record.post_approval_amendment_pending,
    'procurement_editor_auth_user_id', request_record.procurement_editor_auth_user_id,
    'can_manage_post_approval_edit',
      case when request_record.state in ('approved_for_arrangement', 'arranging')
        or request_record.post_approval_amendment_pending
        then public.v1_can_manage_material_request_post_approval_edit(request_record.id)
        else false end,
    'can_edit_post_approval',
      case when request_record.post_approval_edit_enabled and (
        request_record.state in ('approved_for_arrangement', 'arranging')
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
  v_is_approved_edit boolean;
  v_working_arrangement_id uuid;
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
  -- An authenticated retry must return the original receipt before comparing
  -- against the version already advanced by its own successful write.
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_update_material_request_for_approval', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
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

  v_is_approved_edit := v_request.state in ('approved_for_arrangement', 'arranging');
  if v_request.state = 'arranging' then
    select id into v_working_arrangement_id
    from public.v1_procurement_arrangements
    where request_id = v_request_id and status = 'working'
      and saved_at is null for update;
    if v_working_arrangement_id is null or not
      public.v1_material_request_working_arrangement_editable(v_request_id) then
      raise exception 'V1_MATERIAL_REQUEST_APPROVAL_EDIT_DENIED'
        using errcode = '42501';
    end if;
  end if;
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
  -- A working arrangement contains only unsaved placeholders. Remove those
  -- for deleted request lines first so the FK cannot strand stale work.
  if v_working_arrangement_id is not null then
    delete from public.v1_procurement_arrangement_lines existing
    where existing.arrangement_id = v_working_arrangement_id
      and not exists (select 1 from jsonb_array_elements(v_lines) incoming
        where (incoming.value ->> 'id')::uuid = existing.request_line_id);
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
  if v_working_arrangement_id is not null then
    insert into public.v1_procurement_arrangement_lines (
      arrangement_id, request_line_id, source_kind
    )
    select v_working_arrangement_id, line.id, 'warehouse'
    from public.v1_material_request_lines line
    where line.request_id = v_request_id
      and not exists (select 1 from public.v1_procurement_arrangement_lines existing
        where existing.arrangement_id = v_working_arrangement_id
          and existing.request_line_id = line.id);
    update public.v1_procurement_arrangements
    set record_version = record_version + 1, updated_at = clock_timestamp()
    where id = v_working_arrangement_id;
  end if;
  update public.v1_material_requests
  set scope_id = v_scope_id,
      title = v_title,
      timing = v_timing,
      scheduled_date = v_scheduled_date,
      delivery_note = v_delivery_note,
      state = case when v_is_approved_edit then v_request.state
        else 'awaiting_request_approval' end,
      post_approval_amendment_pending = case when v_is_approved_edit
        then false else v_request.post_approval_amendment_pending end,
      current_action_owner_role = case when v_is_approved_edit
        then 'procurement' else 'project_engineer' end,
      current_action_code = case when v_request.state = 'arranging'
        then 'arrangement_in_progress'
        when v_is_approved_edit then 'arrangement_required'
        else 'request_approval_required' end,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = v_request_id;

  -- The approval decision still refers to its original version. Preserve a
  -- separate immutable snapshot for the delegated edit, without fabricating a
  -- new Engineering decision or re-entering the approval queue.
  if v_is_approved_edit then
    insert into public.v1_material_request_revision_snapshots (
      request_id, request_record_version, snapshot_reason, title, timing,
      scheduled_date, delivery_note, lines, captured_by_auth_user_id,
      captured_by_exact_role, captured_at
    ) values (
      v_request_id, v_expected_version + 1, 'post_approval_edit', v_title,
      v_timing, v_scheduled_date, v_delivery_note,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'id', line.id, 'display_order', line.display_order,
        'source_kind', line.source_kind,
        'source_boq_group_id', line.source_boq_group_id,
        'source_boq_row_id', line.source_boq_row_id,
        'item_description', line.item_description,
        'brand_origin', line.brand_origin,
        'technical_attributes', coalesce(line.technical_attributes, '{}'::jsonb),
        'requested_qty', line.requested_qty, 'unit', line.unit
      ) order by line.display_order, line.id), '[]'::jsonb)
      from public.v1_material_request_lines line
      where line.request_id = v_request_id),
      auth.uid(), public.v1_current_exact_role(), clock_timestamp()
    );
  end if;

  if not v_is_approved_edit then
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
  end if;

  v_response := public.v1_material_request_projection(v_request_id);
  perform public.v1_write_audit_event(
    case when v_is_approved_edit
      then 'material_request_saved_after_approval'
      else 'material_request_updated_for_approval' end,
    'material_request', v_request_id,
    v_request.project_id, v_before,
    jsonb_build_object(
      'record_version', v_expected_version + 1,
      'line_count', jsonb_array_length(v_lines),
      'state', case when v_is_approved_edit
        then v_request.state else 'awaiting_request_approval' end
    ), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_update_material_request_for_approval', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;
commit;

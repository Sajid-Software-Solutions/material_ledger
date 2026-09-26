-- Owner-private retirement markers prevent old/offline editors reviving a deleted UUID.
-- Additive only: no existing draft, request, line, stock or history is rewritten.
-- Rollback: retain markers/audit; deploy corrective function bodies. Never auto-resurrect.
create table if not exists public.v1_material_request_private_draft_retirements (
  draft_id uuid not null,
  owner_auth_user_id uuid not null references auth.users(id) on delete restrict,
  retired_sync_version integer not null check (retired_sync_version >= 0),
  actor_role text not null,
  deleted_at timestamptz not null default clock_timestamp(),
  primary key (draft_id, owner_auth_user_id)
);
alter table public.v1_material_request_private_draft_retirements enable row level security;
revoke all on public.v1_material_request_private_draft_retirements from public, anon, authenticated;
comment on table public.v1_material_request_private_draft_retirements is
  'Private deletion barrier. Only trusted owner RPCs access this append-only relation. No draft contents.';

-- Expected terminal outcomes are conflicts, not HTTP 500 backend failures.
create or replace function public.v1_raise_private_material_request_draft_terminal(
  p_message text
) returns void language plpgsql security invoker set search_path = '' as $$
begin
  if p_message not in ('V1_PRIVATE_DRAFT_DELETED', 'V1_PRIVATE_DRAFT_ALREADY_SAVED') then
    raise exception 'V1_PRIVATE_DRAFT_TERMINAL_CODE_INVALID' using errcode = '22023';
  end if;
  if nullif(current_setting('request.method', true), '') is not null then
    raise sqlstate 'PGRST' using
      message = jsonb_build_object('code', '55000', 'message', p_message,
        'details', null, 'hint', null)::text,
      detail = '{"status":409,"headers":{}}';
  end if;
  raise exception '%' , p_message using errcode = '55000';
end;
$$;
revoke all on function public.v1_raise_private_material_request_draft_terminal(text)
from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.v1_sync_material_request_private_draft(p_payload jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_draft_id uuid;
  v_expected integer;
  v_client_updated_at timestamptz;
  v_data jsonb;
  v_line jsonb;
  v_current public.v1_material_request_private_drafts%rowtype;
  v_existing jsonb;
  v_response jsonb;
begin
  perform public.v1_assert_object_keys(
    p_payload, array[
      'draft_id', 'expected_sync_version', 'client_updated_at', 'draft_data'
    ], 'sync_material_request_private_draft'
  );
  v_draft_id := nullif(btrim(coalesce(p_payload ->> 'draft_id', '')), '')::uuid;
  v_expected := nullif(p_payload ->> 'expected_sync_version', '')::integer;
  v_client_updated_at := nullif(
    p_payload ->> 'client_updated_at', ''
  )::timestamptz;
  v_data := p_payload -> 'draft_data';
  if v_actor is null or not public.v1_current_actor_is_active()
    or v_draft_id is null or v_expected is null or v_expected < 0
    or v_client_updated_at is null or jsonb_typeof(v_data) <> 'object'
    or octet_length(v_data::text) > 1048576 then
    raise exception 'V1_PRIVATE_DRAFT_INVALID' using errcode = '22023';
  end if;
  perform public.v1_assert_object_keys(
    v_data, array[
      'project_id', 'scope_id', 'title', 'timing', 'scheduled_date',
      'delivery_note', 'lines'
    ], 'private_material_request_draft_data'
  );
  if jsonb_typeof(coalesce(v_data -> 'lines', '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(v_data -> 'lines', '[]'::jsonb)) > 1000
    or coalesce(v_data ->> 'timing', 'normal') not in (
      'urgent', 'normal', 'scheduled'
    ) or length(coalesce(v_data ->> 'title', '')) > 500
    or length(coalesce(v_data ->> 'delivery_note', '')) > 2000 then
    raise exception 'V1_PRIVATE_DRAFT_INVALID' using errcode = '22023';
  end if;
  if nullif(v_data ->> 'project_id', '') is not null
    and not public.v1_project_readable((v_data ->> 'project_id')::uuid) then
    raise exception 'V1_PRIVATE_DRAFT_PROJECT_DENIED' using errcode = '42501';
  end if;
  if nullif(v_data ->> 'scope_id', '') is not null and not exists (
    select 1 from public.v1_project_scopes scope
    where scope.id = (v_data ->> 'scope_id')::uuid
      and scope.project_id = (v_data ->> 'project_id')::uuid
      and scope.is_active
  ) then
    raise exception 'V1_PRIVATE_DRAFT_SCOPE_INVALID' using errcode = '22023';
  end if;
  for v_line in select value
    from jsonb_array_elements(coalesce(v_data -> 'lines', '[]'::jsonb))
  loop
    perform public.v1_assert_object_keys(
      v_line, array[
        'id', 'display_order', 'source_kind', 'source_boq_group_id',
        'source_boq_row_id', 'item_description', 'brand_origin',
        'technical_attributes', 'requested_qty', 'unit'
      ], 'private_material_request_draft_line'
    );
    if length(coalesce(v_line ->> 'item_description', '')) > 4000
      or length(coalesce(v_line ->> 'unit', '')) > 120
      or jsonb_typeof(coalesce(
        v_line -> 'technical_attributes', '{}'::jsonb
      )) <> 'object' then
      raise exception 'V1_PRIVATE_DRAFT_LINE_INVALID' using errcode = '22023';
    end if;
  end loop;
  -- Serialize absent-row creation and deletion as well as existing-row writes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'v1_mr_private:' || v_actor::text || ':' || v_draft_id::text, 0
  ));
  if exists (
    select 1 from public.v1_material_request_private_draft_retirements retired
    where retired.draft_id = v_draft_id and retired.owner_auth_user_id = v_actor
  ) then
    perform public.v1_raise_private_material_request_draft_terminal('V1_PRIVATE_DRAFT_DELETED');
  end if;

  if exists (
    select 1 from public.v1_material_requests request
    where request.id = v_draft_id and request.state <> 'draft'
  ) then
    raise exception 'V1_PRIVATE_DRAFT_ALREADY_SUBMITTED' using errcode = '22023';
  end if;

  select * into v_current
  from public.v1_material_request_private_drafts draft
  where draft.draft_id = v_draft_id and draft.owner_auth_user_id = v_actor
  for update;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_sync_material_request_private_draft', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
  if (not found and v_expected <> 0)
    or (found and v_current.sync_version <> v_expected) then
    perform public.v1_raise_version_conflict('V1_PRIVATE_DRAFT_VERSION_CONFLICT');
  end if;

  insert into public.v1_material_request_private_drafts (
    draft_id, owner_auth_user_id, sync_version, draft_data,
    client_updated_at, created_at, updated_at
  ) values (
    v_draft_id, v_actor, 1, v_data, v_client_updated_at,
    clock_timestamp(), clock_timestamp()
  ) on conflict (draft_id, owner_auth_user_id) do update set
    sync_version = public.v1_material_request_private_drafts.sync_version + 1,
    draft_data = excluded.draft_data,
    client_updated_at = excluded.client_updated_at,
    updated_at = clock_timestamp();

  select jsonb_build_object(
    'draft_id', draft.draft_id,
    'sync_version', draft.sync_version,
    'draft_data', draft.draft_data,
    'client_updated_at', draft.client_updated_at,
    'server_updated_at', draft.updated_at
  ) into v_response
  from public.v1_material_request_private_drafts draft
  where draft.draft_id = v_draft_id and draft.owner_auth_user_id = v_actor;

  perform public.v1_complete_idempotency(
    'v1_sync_material_request_private_draft', p_idempotency_key, v_response
  );
  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_save_material_request_draft(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_role();
  v_request_id uuid;
  v_expected_version integer;
  v_project_id uuid;
  v_scope_id uuid;
  v_title text;
  v_timing text;
  v_scheduled_date date;
  v_delivery_note text;
  v_lines jsonb;
  v_existing public.v1_material_requests%rowtype;
  v_request_exists boolean := false;
  v_line jsonb;
  v_line_id uuid;
  v_line_order integer;
  v_source_kind text;
  v_source_group_id uuid;
  v_source_row_id uuid;
  v_description text;
  v_brand_origin text;
  v_technical_attributes jsonb;
  v_requested_qty numeric(18, 4);
  v_unit text;
begin
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'request_id', 'expected_version', 'project_id', 'scope_id', 'title',
      'timing', 'scheduled_date', 'delivery_note', 'lines'
    ],
    'material_request_draft'
  );
  v_request_id := nullif(btrim(coalesce(p_payload ->> 'request_id', '')), '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_project_id := nullif(btrim(coalesce(p_payload ->> 'project_id', '')), '')::uuid;
  v_scope_id := nullif(btrim(coalesce(p_payload ->> 'scope_id', '')), '')::uuid;
  v_title := nullif(btrim(coalesce(p_payload ->> 'title', '')), '');
  v_timing := coalesce(p_payload ->> 'timing', '');
  v_scheduled_date := nullif(p_payload ->> 'scheduled_date', '')::date;
  v_delivery_note := nullif(btrim(coalesce(p_payload ->> 'delivery_note', '')), '');
  v_lines := coalesce(p_payload -> 'lines', '[]'::jsonb);
  if v_request_id is null or v_expected_version is null or v_expected_version < 0
    or v_project_id is null or v_scope_id is null
    or v_timing not in ('urgent', 'normal', 'scheduled')
    or jsonb_typeof(v_lines) <> 'array'
    or (v_timing = 'scheduled' and v_scheduled_date is null)
    or (v_timing <> 'scheduled' and v_scheduled_date is not null) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.v1_project_scopes scope
    where scope.id = v_scope_id and scope.project_id = v_project_id
      and scope.is_active
  ) then
    raise exception 'V1_MATERIAL_REQUEST_SCOPE_INVALID' using errcode = '22023';
  end if;

  -- Serialize absent-row creation and deletion as well as existing-row writes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'v1_mr_private:' || v_actor::text || ':' || v_request_id::text, 0
  ));
  if exists (
    select 1 from public.v1_material_request_private_draft_retirements retired
    where retired.draft_id = v_request_id and retired.owner_auth_user_id = v_actor
  ) then
    perform public.v1_raise_private_material_request_draft_terminal('V1_PRIVATE_DRAFT_DELETED');
  end if;

  select * into v_existing from public.v1_material_requests request_record
  where request_record.id = v_request_id for update;
  v_request_exists := found;
  if v_request_exists then
    if not public.v1_material_request_engineering_project_access(v_project_id)
      or not public.v1_current_user_has_capability(
        'material_requests.edit', v_project_id
      ) then
      raise exception 'V1_MATERIAL_REQUEST_DRAFT_EDIT_DENIED'
        using errcode = '42501';
    end if;
  elsif not public.v1_can_create_material_request(v_project_id) then
    raise exception 'V1_MATERIAL_REQUEST_DRAFT_DENIED'
      using errcode = '42501';
  end if;
  if v_request_exists then
    if v_existing.state <> 'draft'
      or v_existing.created_by_auth_user_id <> v_actor then
      raise exception 'V1_MATERIAL_REQUEST_DRAFT_EDIT_DENIED' using errcode = '42501';
    end if;
    if v_existing.record_version <> v_expected_version then
      raise exception 'V1_MATERIAL_REQUEST_VERSION_CONFLICT' using errcode = '40001';
    end if;
  elsif v_expected_version <> 0 then
    raise exception 'V1_MATERIAL_REQUEST_VERSION_CONFLICT' using errcode = '40001';
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
    v_source_group_id := nullif(
      btrim(coalesce(v_line ->> 'source_boq_group_id', '')), ''
    )::uuid;
    v_source_row_id := nullif(
      btrim(coalesce(v_line ->> 'source_boq_row_id', '')), ''
    )::uuid;
    v_description := nullif(btrim(coalesce(v_line ->> 'item_description', '')), '');
    v_brand_origin := nullif(btrim(coalesce(v_line ->> 'brand_origin', '')), '');
    v_technical_attributes := coalesce(v_line -> 'technical_attributes', '{}'::jsonb);
    v_requested_qty := nullif(v_line ->> 'requested_qty', '')::numeric(18, 4);
    v_unit := nullif(btrim(coalesce(v_line ->> 'unit', '')), '');
    v_technical_attributes := jsonb_strip_nulls(
      jsonb_build_object(
        'size', nullif(btrim(coalesce(v_technical_attributes ->> 'size', '')), ''),
        'model', nullif(btrim(coalesce(v_technical_attributes ->> 'model', '')), ''),
        'equipment_tag',
          nullif(btrim(coalesce(v_technical_attributes ->> 'equipment_tag', '')), ''),
        'planning_model_tag',
          nullif(btrim(coalesce(v_technical_attributes ->> 'planning_model_tag', '')), ''),
        'quantity_suggested',
          case
            when v_technical_attributes ? 'quantity_suggested' then
              nullif(
                lower(btrim(v_technical_attributes ->> 'quantity_suggested')),
                ''
              )
            else null
          end
      )
    );
    if (v_technical_attributes ->> 'quantity_suggested') is not null
      and lower(v_technical_attributes ->> 'quantity_suggested') not in ('true', 'false') then
      raise exception 'V1_MATERIAL_REQUEST_LINE_INVALID' using errcode = '22023';
    end if;
    if v_line_id is null or v_line_order is null or v_line_order < 1
      or v_source_kind not in ('boq', 'excel', 'custom')
      or v_description is null or v_requested_qty is null or v_requested_qty <= 0
      or v_unit is null or jsonb_typeof(coalesce(v_line -> 'technical_attributes', '{}'::jsonb)) <> 'object'
      then
      raise exception 'V1_MATERIAL_REQUEST_LINE_INVALID' using errcode = '22023';
    end if;
    if v_source_kind = 'boq' then
      if v_source_group_id is null or v_source_row_id is null or not exists (
        select 1
        from public.v1_boq_groups group_record
        join public.v1_boq_rows row_record on row_record.group_id = group_record.id
        where group_record.id = v_source_group_id
          and group_record.project_id = v_project_id
          and group_record.scope_id = v_scope_id
          and not group_record.is_archived
          and row_record.id = v_source_row_id
          and not row_record.is_archived
      ) then
        raise exception 'V1_MATERIAL_REQUEST_BOQ_SOURCE_INVALID' using errcode = '22023';
      end if;
    elsif v_source_group_id is not null or v_source_row_id is not null then
      raise exception 'V1_MATERIAL_REQUEST_SOURCE_INVALID' using errcode = '22023';
    end if;
  end loop;

  if v_request_exists then
    update public.v1_material_requests
       set project_id = v_project_id,
           scope_id = v_scope_id,
           title = v_title,
           timing = v_timing,
           scheduled_date = v_scheduled_date,
           delivery_note = v_delivery_note,
           record_version = record_version + 1,
           updated_at = clock_timestamp()
     where id = v_request_id;
  else
    insert into public.v1_material_requests (
      id, project_id, scope_id, title, timing, scheduled_date, delivery_note,
      state, record_version, created_by_auth_user_id,
      current_action_owner_role, current_action_code, created_at, updated_at
    ) values (
      v_request_id, v_project_id, v_scope_id, v_title, v_timing,
      v_scheduled_date, v_delivery_note, 'draft', 1, v_actor,
      case when v_role = 'admin' then 'admin' else v_role end,
      'draft_owner', clock_timestamp(), clock_timestamp()
    );
  end if;

  delete from public.v1_material_request_lines where request_id = v_request_id;
  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    insert into public.v1_material_request_lines (
      id, request_id, display_order, source_kind, source_boq_group_id,
      source_boq_row_id, item_description, brand_origin, technical_attributes,
      requested_qty, unit, created_at, updated_at
    ) values (
      (v_line ->> 'id')::uuid,
      v_request_id,
      (v_line ->> 'display_order')::integer,
      v_line ->> 'source_kind',
      nullif(v_line ->> 'source_boq_group_id', '')::uuid,
      nullif(v_line ->> 'source_boq_row_id', '')::uuid,
      btrim(v_line ->> 'item_description'),
      nullif(btrim(coalesce(v_line ->> 'brand_origin', '')), ''),
      public.v1_material_request_normalized_technical_attributes(
        coalesce(v_line -> 'technical_attributes', '{}'::jsonb),
        v_line ->> 'source_kind'
      ),
      (v_line ->> 'requested_qty')::numeric(18, 4),
      btrim(v_line ->> 'unit'),
      clock_timestamp(), clock_timestamp()
    );
  end loop;
  return public.v1_material_request_projection(v_request_id);
end;
$function$;

create or replace function public.v1_delete_my_material_request_private_draft(
  p_payload jsonb, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_draft_id uuid;
  v_expected integer;
  v_current public.v1_material_request_private_drafts%rowtype;
  v_exists boolean;
  v_existing jsonb;
  v_response jsonb;
  v_retired boolean;
begin
  perform public.v1_assert_object_keys(
    p_payload, array['draft_id', 'expected_sync_version'],
    'delete_private_material_request_draft'
  );
  v_draft_id := nullif(btrim(coalesce(p_payload ->> 'draft_id', '')), '')::uuid;
  v_expected := nullif(p_payload ->> 'expected_sync_version', '')::integer;
  if v_draft_id is null or v_expected is null or v_expected < 0
    or v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_PRIVATE_DRAFT_DELETE_INVALID' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'v1_mr_private:' || v_actor::text || ':' || v_draft_id::text, 0
  ));
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_delete_my_material_request_private_draft', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;

  -- Removing recovery input must never cancel or erase a business record.
  if exists (select 1 from public.v1_material_requests where id = v_draft_id) then
    perform public.v1_raise_private_material_request_draft_terminal('V1_PRIVATE_DRAFT_ALREADY_SAVED');
  end if;
  select * into v_current
  from public.v1_material_request_private_drafts draft
  where draft.draft_id = v_draft_id and draft.owner_auth_user_id = v_actor
  for update;
  v_exists := found;
  if v_exists and v_current.sync_version <> v_expected then
    perform public.v1_raise_version_conflict('V1_PRIVATE_DRAFT_VERSION_CONFLICT');
  end if;

  insert into public.v1_material_request_private_draft_retirements (
    draft_id, owner_auth_user_id, retired_sync_version, actor_role
  ) values (
    v_draft_id, v_actor, coalesce(v_current.sync_version, 0),
    public.v1_current_role()
  ) on conflict (draft_id, owner_auth_user_id) do nothing;
  v_retired := found;
  delete from public.v1_material_request_private_drafts draft
  where draft.draft_id = v_draft_id and draft.owner_auth_user_id = v_actor;
  if v_retired then
    perform public.v1_write_audit_event(
      'material_request_private_draft_deleted', 'material_request_private_draft',
      v_draft_id, null, jsonb_build_object('sync_version', coalesce(v_current.sync_version, 0)),
      jsonb_build_object('deleted', true), null, p_idempotency_key
    );
  end if;
  v_response := jsonb_build_object('draft_id', v_draft_id, 'deleted', true);
  perform public.v1_complete_idempotency(
    'v1_delete_my_material_request_private_draft', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

-- Preserve the existing RPC boundary; no new ordinary-table authority.
revoke all on function public.v1_delete_my_material_request_private_draft(jsonb,uuid) from public, anon;
grant execute on function public.v1_delete_my_material_request_private_draft(jsonb,uuid) to authenticated;
create or replace function public.v1_get_my_material_request_private_draft(
  p_draft_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_PRIVATE_DRAFT_DENIED' using errcode = '42501';
  end if;
  if exists (select 1 from public.v1_material_request_private_draft_retirements
    where draft_id = p_draft_id and owner_auth_user_id = auth.uid()) then
    perform public.v1_raise_private_material_request_draft_terminal('V1_PRIVATE_DRAFT_DELETED');
  end if;
  return (
    select jsonb_build_object(
      'draft_id', draft.draft_id,
      'sync_version', draft.sync_version,
      'draft_data', draft.draft_data,
      'client_updated_at', draft.client_updated_at,
      'server_updated_at', draft.updated_at
    )
    from public.v1_material_request_private_drafts draft
    where draft.draft_id = p_draft_id
      and draft.owner_auth_user_id = auth.uid()
  );
end;
$$;

create or replace function public.v1_list_my_material_request_private_drafts(
  p_limit integer default 50
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_PRIVATE_DRAFT_DENIED' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'draft_id', draft.draft_id,
      'sync_version', draft.sync_version,
      'draft_data', draft.draft_data,
      'client_updated_at', draft.client_updated_at,
      'server_updated_at', draft.updated_at
    ) order by draft.updated_at desc, draft.draft_id)
    from (
      select * from public.v1_material_request_private_drafts private_draft
      where private_draft.owner_auth_user_id = auth.uid()
        and not exists (select 1 from public.v1_material_requests request
          where request.id = private_draft.draft_id)
      order by private_draft.updated_at desc, private_draft.draft_id
      limit least(greatest(coalesce(p_limit, 50), 1), 100)
    ) draft
  ), '[]'::jsonb);
end;
$$;

notify pgrst, 'reload schema';

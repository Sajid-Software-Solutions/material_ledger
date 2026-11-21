-- Rollback: production function alignment
-- (docs/yorks-v1/PRODUCTION_FUNCTION_DRIFT_2026-11-15.md).
-- Restores the 11 replaced functions exactly as production had them on
-- 15 Nov 2026 (including their compacted text), drops the 8 functions the
-- bundle added unless something now depends on one of them, and gives anon and
-- PUBLIC back execute on the five legacy JWT helpers. Nothing in data changes.
-- The live web (849affb) works with either set of definitions.
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/production_function_alignment_rollback.sql

begin;

do $guard$
declare
  v_allowed constant jsonb := jsonb_build_object(
    'v1_material_search_normalize(text)', jsonb_build_array('absent', '351a0430756a5e2cb730ac22091901ee'),
    'v1_material_search_synonyms(text)', jsonb_build_array('absent', '664152d721f94a1fcaeda2216f92462f'),
    'v1_material_search_one_edit(text,text)', jsonb_build_array('absent', 'da4e7a95947adcd0d7af32e6b790bf83'),
    'v1_search_material_request_candidates(uuid,uuid,text,integer)', jsonb_build_array('c64083a914330a7aa5c353dae5af6963', '1f177e9087dee103fd7eb74b97649b58'),
    'v1_search_company_material_request_candidates(uuid,uuid,text,integer)', jsonb_build_array('23c23e4227f368f14e4856d90e7c2aa0', '9d0e9f3888b285cd9bffa2f797de5780'),
    'v1_material_request_overview(integer)', jsonb_build_array('5c6b96e54bcc884e19b8381816e7df8f', '83e9d3c1227b0baa191b966d8b8b95c5'),
    'v1_material_request_submission_diagnostic(uuid,uuid,uuid)', jsonb_build_array('absent', 'd4c4af385dd1ac080362dc15a04779ba'),
    'v1_can_confirm_material_return(uuid)', jsonb_build_array('f22a335dcb7a7143cd4da6f16174866a', '99b6cbc8dcec9fb5272703afb5692b38'),
    'app_role()', jsonb_build_array('0bc9a3e2215721f357a3333f6cc66b83', 'fe73549c0b069d7287eefe83082cc20d'),
    'app_user_id()', jsonb_build_array('f3d905b9020548149ccfeadca7d1e2fe', 'e27089640fe1db6cd8203b747aa6e387'),
    'notification_visible_to_caller(jsonb)', jsonb_build_array('937c030c5fe6e9288c67816938ab9f40', 'f5f29d8967430dd7aff95c03b079659d'),
    'app_legacy_project_readable(jsonb)', jsonb_build_array('absent', '868de3343460e5f23dd2b6fb91cacb97'),
    'app_legacy_project_writable(jsonb)', jsonb_build_array('absent', '2f9886f3dc5d8e9569ac11b1c983582e'),
    'app_legacy_plan_readable(jsonb)', jsonb_build_array('absent', '4c419e9288ed298eea5958a05c222fd5'),
    'app_legacy_plan_writable(jsonb)', jsonb_build_array('absent', '1bfe72c4ef608cfd9601b7a5cca8206d'),
    'project_progress_definitions(jsonb)', jsonb_build_array('839096d402ff865fd30f88c536d2c34f', '2669c15d30544e6d11170d8eb9abe73f'),
    'project_require_approved_phase1()', jsonb_build_array('5728a75dc73870bc046a28629f02ca75', '84228975d49436cb8d8b677d6749f2e4'),
    'v1_create_document_version(uuid,text,bigint,text)', jsonb_build_array('33c32837d5a32331c9cca1a1cdea4a8d', '468a0043e2754c640ddf4af5bea0e6c6'),
    'v1_import_boq_worksheet(jsonb,uuid)', jsonb_build_array('181ada5a87b31b7a6aab12421f652df6', '6578655c386d24a1c22a84b3dfdeb173'),
    'app_has_cap(text)', jsonb_build_array('52a353bc83eefc45e5ac91afb93a7acb'),
    'app_touch_updated_at()', jsonb_build_array('76377695287d53f3bc550b0b8beb0a9c')
  );
  v_signature text;
  v_fingerprints jsonb;
  v_fingerprint text;
begin
  for v_signature, v_fingerprints in
    select key, value from jsonb_each(v_allowed)
  loop
    select md5(p.prosrc || coalesce(p.proconfig::text, '') || p.provolatile::text || p.prosecdef::text)
    into v_fingerprint
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('public.' || v_signature);
    if not v_fingerprints ? coalesce(v_fingerprint, 'absent') then
      raise exception
        'function alignment rollback: public.% has an unreviewed definition (%)',
        v_signature, coalesce(v_fingerprint, 'absent');
    end if;
  end loop;
end;
$guard$;

-- Production's definitions of 15 Nov 2026 (pg_get_functiondef), in bundle order.

CREATE OR REPLACE FUNCTION public.v1_search_material_request_candidates(p_project_id uuid, p_scope_id uuid, p_query text, p_limit integer DEFAULT 18)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_query text := lower(regexp_replace(
    btrim(coalesce(p_query, '')), '\s+', ' ', 'g'
  ));
  v_limit integer := least(greatest(coalesce(p_limit, 18), 1), 30);
begin
  if auth.uid() is null
    or not public.v1_current_actor_is_active()
    or not coalesce(public.v1_project_readable(p_project_id), false) then
    raise exception 'V1_MATERIAL_REQUEST_CANDIDATE_SEARCH_DENIED'
      using errcode = '42501';
  end if;

  if length(v_query) < 2
    or not exists (
      select 1
      from public.v1_project_scopes scope_record
      where scope_record.id = p_scope_id
        and scope_record.project_id = p_project_id
        and scope_record.is_active
    ) then
    raise exception 'V1_MATERIAL_REQUEST_CANDIDATE_SEARCH_INVALID'
      using errcode = '22023';
  end if;

  return coalesce((
    with candidates as (
      select
        row_record.id,
        case when group_record.scope_id = p_scope_id
          then 'scope_boq' else 'project_boq' end as source_kind,
        case when group_record.scope_id = p_scope_id then 0 else 1 end
          as source_priority,
        null::text as item_code,
        nullif(btrim(row_record.canonical_values ->> 'description'), '')
          as item_description,
        nullif(btrim(row_record.canonical_values ->> 'brand_origin'), '')
          as brand_origin,
        nullif(btrim(row_record.canonical_values ->> 'size'), '') as size_text,
        coalesce(
          nullif(btrim(row_record.canonical_values ->> 'model'), ''),
          nullif(btrim(row_record.canonical_values ->> 'planning_model_tag'), '')
        ) as model_reference,
        nullif(btrim(row_record.canonical_values ->> 'equipment_tag'), '')
          as equipment_tag,
        nullif(btrim(row_record.canonical_values ->> 'unit'), '') as unit,
        group_record.id as source_boq_group_id,
        row_record.id as source_boq_row_id,
        group_record.scope_id as source_scope_id,
        scope_record.name as source_scope_name,
        group_record.worksheet_title as source_group_name,
        lower(concat_ws(' ',
          row_record.canonical_values ->> 'description',
          row_record.canonical_values ->> 'brand_origin',
          row_record.canonical_values ->> 'size',
          row_record.canonical_values ->> 'model',
          row_record.canonical_values ->> 'planning_model_tag',
          row_record.canonical_values ->> 'equipment_tag',
          group_record.worksheet_title,
          scope_record.name
        )) as searchable_text
      from public.v1_boq_rows row_record
      join public.v1_boq_groups group_record
        on group_record.id = row_record.group_id
      left join public.v1_project_scopes scope_record
        on scope_record.id = group_record.scope_id
      where group_record.project_id = p_project_id
        and not group_record.is_archived
        and not row_record.is_archived
        and (scope_record.id is null or scope_record.is_active)
        and nullif(btrim(row_record.canonical_values ->> 'description'), '')
          is not null
        and nullif(btrim(row_record.canonical_values ->> 'unit'), '') is not null

      union all

      select
        item.id,
        'inventory'::text as source_kind,
        2 as source_priority,
        item.item_code,
        item.item_description,
        item.brand_origin,
        item.size_text,
        item.model_reference,
        null::text as equipment_tag,
        item.unit,
        null::uuid as source_boq_group_id,
        null::uuid as source_boq_row_id,
        null::uuid as source_scope_id,
        null::text as source_scope_name,
        null::text as source_group_name,
        lower(concat_ws(' ',
          item.item_code, item.item_description, item.brand_origin,
          item.size_text, item.model_reference, item.unit
        )) as searchable_text
      from public.v1_inventory_items item
      where item.is_active
    ), ranked as (
      select candidate.*,
        case
          when lower(coalesce(candidate.item_code, '')) = v_query then 0
          when lower(candidate.item_description) = v_query then 1
          when lower(candidate.item_description) like v_query || '%' then 2
          when lower(coalesce(candidate.item_code, '')) like v_query || '%'
            then 3
          when position(' ' || v_query in ' ' || candidate.searchable_text) > 0
            then 4
          else 5
        end as match_rank
      from candidates candidate
      where position(v_query in candidate.searchable_text) > 0
    ), limited as (
      select * from ranked
      order by source_priority, match_rank, lower(item_description), id
      limit v_limit
    )
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', limited.id,
      'source_kind', limited.source_kind,
      'item_code', limited.item_code,
      'item_description', limited.item_description,
      'brand_origin', limited.brand_origin,
      'size', limited.size_text,
      'model', limited.model_reference,
      'equipment_tag', limited.equipment_tag,
      'unit', limited.unit,
      'source_boq_group_id', limited.source_boq_group_id,
      'source_boq_row_id', limited.source_boq_row_id,
      'source_scope_id', limited.source_scope_id,
      'source_scope_name', limited.source_scope_name,
      'source_group_name', limited.source_group_name
    )) order by limited.source_priority, limited.match_rank,
       lower(limited.item_description), limited.id)
    from limited
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_search_company_material_request_candidates(p_category_id uuid, p_responsible_unit_id uuid, p_query text, p_limit integer DEFAULT 18)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_query text := lower(regexp_replace(
    btrim(coalesce(p_query, '')), '\s+', ' ', 'g'
  ));
  v_limit integer := least(greatest(coalesce(p_limit, 18), 1), 30);
begin
  if v_actor is null
    or not public.v1_current_actor_is_active()
    or not public.v1_company_material_request_active_authorization(
      v_actor, p_category_id, p_responsible_unit_id, 'requester'
    ) then
    raise exception 'V1_COMPANY_MATERIAL_SEARCH_DENIED'
      using errcode = '42501';
  end if;
  if length(v_query) < 2 or length(v_query) > 200
    or not exists (
      select 1
      from public.v1_company_material_request_categories category
      join public.v1_company_material_request_units unit_record
        on unit_record.id = p_responsible_unit_id
      where category.id = p_category_id
        and category.is_active
        and unit_record.is_active
    ) then
    raise exception 'V1_COMPANY_MATERIAL_SEARCH_INVALID'
      using errcode = '22023';
  end if;

  return coalesce((
    with ranked as (
      select item.*,
        lower(concat_ws(' ', item.item_code, item.item_description,
          item.brand_origin, item.size_text, item.model_reference, item.unit
        )) as searchable_text,
        case
          when lower(coalesce(item.item_code, '')) = v_query then 0
          when lower(item.item_description) = v_query then 1
          when strpos(lower(item.item_description), v_query) = 1 then 2
          when strpos(lower(coalesce(item.item_code, '')), v_query) = 1 then 3
          else 4
        end as match_rank
      from public.v1_inventory_items item
      where item.is_active
        and not exists (
          select 1 from unnest(regexp_split_to_array(v_query, ' ')) token
          where strpos(lower(concat_ws(' ',item.item_code,item.item_description,
            item.brand_origin,item.size_text,item.model_reference,item.unit)),token)=0
        )
    ), limited as (
      select * from ranked
      order by match_rank, lower(item_description), id
      limit v_limit
    )
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', limited.id,
      'source_kind', 'inventory',
      'item_code', limited.item_code,
      'item_description', limited.item_description,
      'brand_origin', limited.brand_origin,
      'size', limited.size_text,
      'model', limited.model_reference,
      'unit', limited.unit
    )) order by limited.match_rank, lower(limited.item_description), limited.id)
    from limited
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_material_request_overview(p_limit integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 15);
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_result jsonb;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_MATERIAL_REQUEST_OVERVIEW_DENIED'
      using errcode = '42501';
  end if;

  with project_access as materialized (
    -- Capability resolution can include organization, role, person and
    -- project overrides. Resolve that authoritative decision once per project
    -- instead of once for every retained request in the project.
    select project.id as project_id,
      coalesce((
        public.v1_permission_authoritative_resolution(
          v_actor, 'material_requests.view', project.id
        ) ->> 'effective'
      )::boolean, false) as can_view,
      exists (
        select 1
        from public.v1_project_members member
        where member.project_id = project.id
          and member.member_auth_user_id = v_actor
          and member.effective_from <= clock_timestamp()
          and (
            member.effective_to is null
            or member.effective_to > clock_timestamp()
          )
      ) as has_active_membership
    from public.v1_projects project
  ), readable as materialized (
    -- This case expression is the set-based equivalent of
    -- v1_material_request_participant(request.id, v_actor). Keep its ordering:
    -- Admin can read drafts; every other role can read a draft only when it is
    -- their own; global engineers then receive organization-wide submitted
    -- work; project roles require dated membership; Procurement receives only
    -- the established procurement lifecycle states.
    select request.*, project.project_ref,
      project.name as project_name, project.job_contract_reference,
      scope.name as scope_name
    from public.v1_material_requests request
    join project_access access on access.project_id = request.project_id
    join public.v1_projects project on project.id = request.project_id
    join public.v1_project_scopes scope on scope.id = request.scope_id
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
    -- Reuse the existing server-authoritative action predicate. Closed and
    -- cancelled requests are guaranteed false and skip the helper entirely.
    select readable.*,
      case when readable.state in ('closed', 'cancelled') then false
        else public.v1_material_request_actor_has_current_action(readable.id)
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
$function$;

CREATE OR REPLACE FUNCTION public.v1_can_confirm_material_return(p_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return public.v1_can_generate_delivery_order(p_request_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.app_role()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', auth.jwt() ->> 'role', '');
$function$;

CREATE OR REPLACE FUNCTION public.app_user_id()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'app_user_id', '');
$function$;

CREATE OR REPLACE FUNCTION public.notification_visible_to_caller(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    public.app_role() = 'admin'
    or (
      coalesce(p_data->>'userId', '') <> ''
      and p_data->>'userId' = public.app_user_id()
    )
    or (
      coalesce(p_data->>'userId', '') = ''
      and (
        coalesce(p_data->>'audience', '') = ''
        or p_data->>'audience' = public.app_role()
      )
    );
$function$;

CREATE OR REPLACE FUNCTION public.project_progress_definitions(p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with source as (
    select case
      when jsonb_typeof(p_data -> 'progressStages') = 'array'
        then coalesce(p_data -> 'progressStages', '[]'::jsonb)
      else '[]'::jsonb
    end as stages
  ),
  definitions as (
    select jsonb_agg(
      jsonb_build_object(
        'id', stage.value ->> 'id',
        'label', stage.value ->> 'label',
        'weightPercent', stage.value -> 'weightPercent'
      )
      order by stage.ordinality
    ) as value
    from source,
      jsonb_array_elements(source.stages) with ordinality as stage(value, ordinality)
  )
  select coalesce(
    definitions.value,
    '[{"id":"cooling-load-design","label":"Cooling Load Design","weightPercent":10},{"id":"material-supply","label":"Material Supply","weightPercent":50},{"id":"progress-installation","label":"Progress Installation","weightPercent":30},{"id":"commissioning-handover","label":"Commissioning & Handover","weightPercent":5},{"id":"energizing-substation","label":"Energizing Substation","weightPercent":5}]'::jsonb
  )
  from definitions;
$function$;

CREATE OR REPLACE FUNCTION public.project_require_approved_phase1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  caller_role text := public.app_role();
  old_status text := case when tg_op = 'INSERT' then null else old.data ->> 'lifecycleStatus' end;
  new_status text := new.data ->> 'lifecycleStatus';
  old_stages jsonb := case when tg_op = 'INSERT' then '[]'::jsonb else coalesce(old.data -> 'progressStages', '[]'::jsonb) end;
  new_stages jsonb := coalesce(new.data -> 'progressStages', '[]'::jsonb);
  total_weight numeric;
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then return new; end if;
  if new_status = 'active' and old_status is distinct from 'active' and not exists (select 1 from public.phase1_plans plan where plan.project_id = new.id and plan.status = 'approved') then
    raise exception using errcode = '55000', message = 'A project requires an approved Phase 1 plan before activation.';
  end if;
  if new_stages is distinct from old_stages then
    if jsonb_typeof(new_stages) <> 'array' or jsonb_array_length(new_stages) = 0 then
      raise exception using errcode = '22023', message = 'Project progress stages must be a non-empty array.';
    end if;
    if exists (select 1 from jsonb_array_elements(new_stages) stage where jsonb_typeof(stage) <> 'object' or btrim(coalesce(stage ->> 'id', '')) = '' or btrim(coalesce(stage ->> 'label', '')) = '' or jsonb_typeof(stage -> 'weightPercent') <> 'number' or (stage ->> 'weightPercent')::numeric <= 0 or jsonb_typeof(stage -> 'progressPercent') <> 'number' or (stage ->> 'progressPercent')::numeric < 0 or (stage ->> 'progressPercent')::numeric > 100) then
      raise exception using errcode = '22023', message = 'Project progress stages contain invalid values.';
    end if;
    if exists (select 1 from jsonb_array_elements(new_stages) stage group by stage ->> 'id' having count(*) > 1) then
      raise exception using errcode = '22023', message = 'Project progress stage ids must be unique.';
    end if;
    select sum((stage ->> 'weightPercent')::numeric) into total_weight from jsonb_array_elements(new_stages) stage;
    if abs(total_weight - 100) > 0.01 then
      raise exception using errcode = '22023', message = 'Project progress weights must total 100.';
    end if;
    if caller_role = 'procurement' then
      raise exception using errcode = '42501', message = 'Procurement has read-only project progress access.';
    end if;
    if caller_role = 'engineer' and public.project_progress_definitions(old.data) is distinct from public.project_progress_definitions(new.data) then
      raise exception using errcode = '42501', message = 'Engineering can update progress but not stage definitions.';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_create_document_version(p_upload_intent_id uuid, p_verified_sha256 text, p_verified_byte_size bigint, p_verified_mime_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_intent public.v1_document_upload_intents%rowtype;
  v_document_id uuid;
  v_version_id uuid;
  v_previous_version_id uuid;
  v_object storage.objects%rowtype;
  v_metadata_size bigint;
  v_metadata_mime text;
  v_request_hash text;
  v_response jsonb;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then raise exception 'V1_DOCUMENT_FINALIZER_SERVICE_ONLY' using errcode = '42501'; end if;
  select * into v_intent from public.v1_document_upload_intents where id = p_upload_intent_id for update;
  if not found then raise exception 'V1_DOCUMENT_UPLOAD_INTENT_NOT_FOUND' using errcode = '22023'; end if;
  if v_intent.finalized_at is not null then return jsonb_build_object('document_id', v_intent.finalized_document_id, 'document_version_id', v_intent.finalized_version_id, 'revision_number', v_intent.planned_revision_number); end if;
  if v_intent.expires_at <= clock_timestamp() then raise exception 'V1_DOCUMENT_UPLOAD_INTENT_EXPIRED' using errcode = '22023'; end if;
  if lower(p_verified_sha256) <> v_intent.expected_sha256 or p_verified_byte_size <> v_intent.byte_size or p_verified_mime_type <> v_intent.mime_type then raise exception 'V1_DOCUMENT_OBJECT_VERIFICATION_FAILED' using errcode = '22023'; end if;
  select * into v_object from storage.objects where bucket_id = v_intent.bucket_id and name = v_intent.object_path;
  if not found or coalesce(v_object.owner_id, '') <> v_intent.actor_auth_user_id::text then raise exception 'V1_DOCUMENT_OBJECT_NOT_OWNED_BY_INTENT' using errcode = '42501'; end if;
  v_metadata_size := nullif(v_object.metadata ->> 'size', '')::bigint;
  v_metadata_mime := coalesce(nullif(v_object.metadata ->> 'mimetype', ''), nullif(v_object.metadata ->> 'contentType', ''));
  if v_metadata_size <> v_intent.byte_size or v_metadata_mime <> v_intent.mime_type then raise exception 'V1_DOCUMENT_STORAGE_METADATA_MISMATCH' using errcode = '22023'; end if;
  v_document_id := coalesce(v_intent.document_id, gen_random_uuid());
  if v_intent.document_id is null then
    insert into public.v1_documents (id, classification, created_by_auth_user_id, created_by_role) values (v_document_id, v_intent.classification, v_intent.actor_auth_user_id, v_intent.actor_role);
  else
    select current_version_id into v_previous_version_id from public.v1_documents where id = v_document_id for update;
  end if;
  v_version_id := gen_random_uuid();
  insert into public.v1_document_versions (id, document_id, revision_number, bucket_id, object_path, original_file_name, mime_type, byte_size, sha256, origin, source_entity_type, source_entity_id, source_revision, uploaded_by_auth_user_id, uploaded_by_role, supersedes_version_id) values (v_version_id, v_document_id, v_intent.planned_revision_number, v_intent.bucket_id, v_intent.object_path, v_intent.original_file_name, v_intent.mime_type, v_intent.byte_size, v_intent.expected_sha256, v_intent.origin, v_intent.source_entity_type, v_intent.source_entity_id, v_intent.source_revision, v_intent.actor_auth_user_id, v_intent.actor_role, v_previous_version_id);
  update public.v1_documents set current_version_id = v_version_id where id = v_document_id;
  if v_intent.document_id is null then
    insert into public.v1_document_links (id, document_id, project_id, entity_type, entity_id, linked_by_auth_user_id, linked_by_role) values (gen_random_uuid(), v_document_id, v_intent.project_id, v_intent.target_entity_type, v_intent.target_entity_id, v_intent.actor_auth_user_id, v_intent.actor_role);
  end if;
  update public.v1_document_upload_intents set finalized_document_id = v_document_id, finalized_version_id = v_version_id, finalized_at = clock_timestamp() where id = v_intent.id;
  v_response := jsonb_build_object('document_id', v_document_id, 'document_version_id', v_version_id, 'revision_number', v_intent.planned_revision_number);
  update public.v1_idempotency_keys set response_json = response_json || v_response where actor_auth_user_id = v_intent.actor_auth_user_id and command_name = 'v1_prepare_document_upload' and idempotency_key = v_intent.idempotency_key;
  select request_hash into v_request_hash from public.v1_idempotency_keys where actor_auth_user_id = v_intent.actor_auth_user_id and command_name = 'v1_prepare_document_upload' and idempotency_key = v_intent.idempotency_key;
  insert into public.v1_audit_events (event_type, entity_type, entity_id, project_id, actor_auth_user_id, actor_role, occurred_at, idempotency_key, after_data, request_hash) values (case when v_previous_version_id is null then 'document_version_created' else 'document_version_superseded' end, 'document_version', v_version_id, v_intent.project_id, v_intent.actor_auth_user_id, v_intent.actor_role, clock_timestamp(), v_intent.idempotency_key, jsonb_build_object('document_id', v_document_id, 'revision_number', v_intent.planned_revision_number, 'classification', v_intent.classification, 'origin', v_intent.origin), v_request_hash);
  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_import_boq_worksheet(p_payload jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_group_id uuid;
  v_expected_version integer;
  v_title text;
  v_columns jsonb;
  v_rows jsonb;
  v_source jsonb;
  v_file_name text;
  v_sheet_name text;
  v_header_row_number integer;
  v_header_row_numbers jsonb;
  v_header_hierarchy jsonb;
  v_header_number_text text;
  v_header_number integer;
  v_previous_header_number integer := 0;
  v_header_path jsonb;
  v_header_label text;
  v_group public.v1_boq_groups%rowtype;
  v_existing_response jsonb;
  v_save_response jsonb;
  v_before jsonb;
  v_source_projection jsonb;
  v_column jsonb;
  v_heading text;
  v_canonical text;
begin
  perform public.v1_assert_object_keys(p_payload, array['group_id', 'expected_version', 'worksheet_title', 'columns', 'rows', 'source'], 'boq_workbook_import');
  v_group_id := nullif(btrim(coalesce(p_payload ->> 'group_id', '')), '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_title := nullif(btrim(coalesce(p_payload ->> 'worksheet_title', '')), '');
  v_columns := coalesce(p_payload -> 'columns', '[]'::jsonb);
  v_rows := coalesce(p_payload -> 'rows', '[]'::jsonb);
  v_source := p_payload -> 'source';
  if v_group_id is null or v_expected_version is null or v_expected_version < 1 or v_title is null or jsonb_typeof(v_columns) <> 'array' or jsonb_typeof(v_rows) <> 'array' or jsonb_typeof(v_source) <> 'object' then
    raise exception 'V1_BOQ_IMPORT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  perform public.v1_assert_object_keys(v_source, array['file_name', 'worksheet_name', 'header_row_number', 'header_row_numbers', 'header_hierarchy'], 'boq_workbook_import_source');
  v_file_name := nullif(btrim(coalesce(v_source ->> 'file_name', '')), '');
  v_sheet_name := nullif(btrim(coalesce(v_source ->> 'worksheet_name', '')), '');
  v_header_row_number := nullif(v_source ->> 'header_row_number', '')::integer;
  if v_file_name is null or char_length(v_file_name) > 255 or v_sheet_name is null or char_length(v_sheet_name) > 128 or v_header_row_number is null or v_header_row_number < 1 then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  v_header_row_numbers := coalesce(v_source -> 'header_row_numbers', jsonb_build_array(v_header_row_number));
  v_header_hierarchy := coalesce(v_source -> 'header_hierarchy', '[]'::jsonb);
  if jsonb_typeof(v_header_row_numbers) <> 'array' or jsonb_array_length(v_header_row_numbers) < 1 or jsonb_array_length(v_header_row_numbers) > 2 or jsonb_typeof(v_header_hierarchy) <> 'array' then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  for v_header_number_text in select value from jsonb_array_elements_text(v_header_row_numbers)
  loop
    if v_header_number_text !~ '^[1-9][0-9]*$' then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
    v_header_number := v_header_number_text::integer;
    if v_header_number <= v_previous_header_number then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
    v_previous_header_number := v_header_number;
  end loop;
  if (v_header_row_numbers ->> 0)::integer <> v_header_row_number then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
  if jsonb_array_length(v_header_hierarchy) > 0 and jsonb_array_length(v_header_hierarchy) <> jsonb_array_length(v_columns) then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
  for v_header_path in select value from jsonb_array_elements(v_header_hierarchy)
  loop
    perform public.v1_assert_object_keys(v_header_path, array['source_index', 'labels'], 'boq_header_path');
    if jsonb_typeof(v_header_path -> 'source_index') <> 'number' or (v_header_path ->> 'source_index') !~ '^[0-9]+$' or jsonb_typeof(v_header_path -> 'labels') <> 'array' or jsonb_array_length(v_header_path -> 'labels') < 1 or jsonb_array_length(v_header_path -> 'labels') > 2 then
      raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
    end if;
    if (v_header_path ->> 'source_index')::integer > 255 then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
    for v_header_label in select value from jsonb_array_elements_text(v_header_path -> 'labels')
    loop
      if nullif(btrim(v_header_label), '') is null or char_length(v_header_label) > 255 then raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023'; end if;
    end loop;
  end loop;
  if exists (select 1 from (select value ->> 'source_index' as source_index, count(*) as total from jsonb_array_elements(v_header_hierarchy) group by value ->> 'source_index') duplicated_source_index where duplicated_source_index.total > 1) then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  select * into v_group from public.v1_boq_groups group_record where group_record.id = v_group_id for update;
  if not found or v_group.scope_id is null or not public.v1_can_edit_boq_project(v_group.project_id) then raise exception 'V1_BOQ_IMPORT_DENIED' using errcode = '42501'; end if;
  v_existing_response := public.v1_idempotency_get_or_claim('v1_import_boq_worksheet', p_idempotency_key, p_payload);
  if v_existing_response is not null then return v_existing_response; end if;
  if v_group.is_archived or (select state from public.v1_projects where id = v_group.project_id) not in ('draft', 'active') then raise exception 'V1_BOQ_PROJECT_NOT_EDITABLE' using errcode = '42501'; end if;
  if v_group.record_version <> v_expected_version then raise exception 'V1_BOQ_VERSION_CONFLICT' using errcode = '40001'; end if;
  if exists (select 1 from public.v1_boq_columns column_record where column_record.group_id = v_group_id and not column_record.is_archived and column_record.is_commercial) and not public.v1_has_capability('manage_commercials') then raise exception 'V1_BOQ_COMMERCIAL_IMPORT_DENIED' using errcode = '42501'; end if;
  for v_column in select value from jsonb_array_elements(v_columns)
  loop
    perform public.v1_assert_object_keys(v_column, array['id', 'heading', 'display_order', 'canonical_field', 'is_commercial'], 'boq_import_column');
    v_heading := nullif(btrim(coalesce(v_column ->> 'heading', '')), '');
    v_canonical := nullif(btrim(coalesce(v_column ->> 'canonical_field', '')), '');
    if v_heading is null then
      raise exception 'V1_BOQ_IMPORT_COLUMN_INVALID' using errcode = '22023';
    end if;
    if public.v1_required_boq_commercial_canonical(v_heading) is not null
      and (
        v_canonical is distinct from
          public.v1_required_boq_commercial_canonical(v_heading)
        or not coalesce((v_column ->> 'is_commercial')::boolean, false)
      )
      and (
        not coalesce((v_column ->> 'is_commercial')::boolean, false)
        or public.v1_has_capability('manage_commercials')
      ) then
      raise exception 'V1_BOQ_COMMERCIAL_CANONICAL_REQUIRES_CLASSIFICATION'
        using errcode = '22023';
    end if;
    if v_canonical in ('unit_cost', 'total_cost')
      and not coalesce((v_column ->> 'is_commercial')::boolean, false) then
      raise exception 'V1_BOQ_COMMERCIAL_CANONICAL_REQUIRES_CLASSIFICATION'
        using errcode = '22023';
    end if;
    if coalesce((v_column ->> 'is_commercial')::boolean, false)
      and not public.v1_has_capability('manage_commercials') then
      raise exception 'V1_BOQ_COMMERCIAL_IMPORT_DENIED' using errcode = '42501';
    end if;
    if v_canonical is not null and v_canonical not in ('description', 'size', 'model', 'equipment_tag', 'brand_origin', 'quantity', 'unit', 'unit_cost', 'total_cost', 'planning_model_tag') then raise exception 'V1_BOQ_IMPORT_COLUMN_INVALID' using errcode = '22023'; end if;
  end loop;
  if exists (select 1 from (select lower(btrim(value ->> 'heading')) as heading, count(*) as total from jsonb_array_elements(v_columns) group by lower(btrim(value ->> 'heading'))) duplicate_heading where duplicate_heading.total > 1) or exists (select 1 from (select nullif(value ->> 'canonical_field', '') as canonical_field, count(*) as total from jsonb_array_elements(v_columns) where nullif(value ->> 'canonical_field', '') is not null group by nullif(value ->> 'canonical_field', '')) duplicate_canonical where duplicate_canonical.total > 1) then raise exception 'V1_BOQ_IMPORT_COLUMN_MAPPING_DUPLICATE' using errcode = '22023'; end if;
  v_before := public.v1_boq_group_projection(v_group_id);
  v_save_response := public.v1_save_boq_worksheet(jsonb_build_object('group_id', v_group_id, 'expected_version', v_expected_version, 'worksheet_title', v_title, 'columns', v_columns, 'rows', v_rows, 'reason', 'Reviewed XLSX workbook import'), gen_random_uuid());
  v_source_projection := jsonb_build_object('file_name', v_file_name, 'worksheet_name', v_sheet_name, 'header_row_number', v_header_row_number, 'header_row_numbers', v_header_row_numbers, 'header_hierarchy', v_header_hierarchy);
  update public.v1_boq_groups set last_imported_at = clock_timestamp(), last_imported_by_auth_user_id = auth.uid(), last_import_source = v_source_projection, updated_at = clock_timestamp() where id = v_group_id;
  perform public.v1_write_audit_event('boq_import_committed', 'boq_group', v_group_id, v_group.project_id, v_before, jsonb_build_object('source', v_source_projection, 'record_version', v_expected_version + 1, 'column_count', jsonb_array_length(v_columns), 'row_count', jsonb_array_length(v_rows)), 'Reviewed XLSX workbook import', p_idempotency_key);
  perform public.v1_complete_idempotency('v1_import_boq_worksheet', p_idempotency_key, v_save_response);
  return v_save_response;
end;
$function$;

-- The added functions. The two search RPCs above no longer call the helpers.
do $drop$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_material_request_submission_diagnostic(uuid,uuid,uuid)',
    'v1_material_search_normalize(text)',
    'v1_material_search_synonyms(text)',
    'v1_material_search_one_edit(text,text)',
    'app_legacy_plan_readable(jsonb)',
    'app_legacy_plan_writable(jsonb)',
    'app_legacy_project_readable(jsonb)',
    'app_legacy_project_writable(jsonb)'
  ] loop
    begin
      execute 'drop function if exists public.' || v_signature;
    exception when dependent_objects_still_exist then
      raise notice 'kept public.%: another object now depends on it', v_signature;
    end;
  end loop;
end;
$drop$;

grant execute on function public.app_role(), public.app_user_id(),
  public.app_has_cap(text), public.app_touch_updated_at(),
  public.notification_visible_to_caller(jsonb)
  to public, anon, authenticated, service_role;

do $check$
declare
  v_fingerprint constant jsonb := jsonb_build_object(
    'v1_search_material_request_candidates(uuid,uuid,text,integer)', 'c64083a914330a7aa5c353dae5af6963',
    'v1_search_company_material_request_candidates(uuid,uuid,text,integer)', '23c23e4227f368f14e4856d90e7c2aa0',
    'v1_material_request_overview(integer)', '5c6b96e54bcc884e19b8381816e7df8f',
    'v1_can_confirm_material_return(uuid)', 'f22a335dcb7a7143cd4da6f16174866a',
    'app_role()', '0bc9a3e2215721f357a3333f6cc66b83',
    'app_user_id()', 'f3d905b9020548149ccfeadca7d1e2fe',
    'notification_visible_to_caller(jsonb)', '937c030c5fe6e9288c67816938ab9f40',
    'project_progress_definitions(jsonb)', '839096d402ff865fd30f88c536d2c34f',
    'project_require_approved_phase1()', '5728a75dc73870bc046a28629f02ca75',
    'v1_create_document_version(uuid,text,bigint,text)', '33c32837d5a32331c9cca1a1cdea4a8d',
    'v1_import_boq_worksheet(jsonb,uuid)', '181ada5a87b31b7a6aab12421f652df6',
    'app_has_cap(text)', '52a353bc83eefc45e5ac91afb93a7acb',
    'app_touch_updated_at()', '76377695287d53f3bc550b0b8beb0a9c'
  );
  v_signature text;
begin
  for v_signature in select key from jsonb_each(v_fingerprint) loop
    if (
      select md5(p.prosrc || coalesce(p.proconfig::text, '') || p.provolatile::text || p.prosecdef::text)
      from pg_catalog.pg_proc p
      where p.oid = to_regprocedure('public.' || v_signature)
    ) is distinct from v_fingerprint ->> v_signature then
      raise exception 'function alignment rollback self-check: public.% differs',
        v_signature;
    end if;
  end loop;
  foreach v_signature in array array[
    'app_role()',
    'app_user_id()',
    'app_has_cap(text)',
    'app_touch_updated_at()',
    'notification_visible_to_caller(jsonb)'
  ] loop
    if not has_function_privilege('anon', 'public.' || v_signature, 'execute') then
      raise exception 'function alignment rollback self-check: anon execute on public.%',
        v_signature;
    end if;
  end loop;
end;
$check$;

commit;

notify pgrst, 'reload schema';

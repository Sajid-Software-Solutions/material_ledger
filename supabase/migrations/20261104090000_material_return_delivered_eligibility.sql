-- Material Return overhaul, server part (product owner decisions, 3-4 November 2026).
--
-- 1. Delivered material is returnable as soon as it is dispatched. The basis of a
--    dispatch line is the confirmed good received quantity when a receipt review
--    exists, otherwise the dispatched quantity. Returnable = basis - quantity on
--    active returns (awaiting approval, approved, dispatched, confirmed).
-- 2. Delivered return lines anchor on dispatch_line_id; receipt_review_line_id is
--    kept when a confirmed review exists. Every line records which basis applied.
-- 3. A receipt review can no longer record a good quantity below what is already
--    on active returns from that dispatch line (the reviewer must reduce or cancel
--    the return first).
-- 4. Return lines carry size, model and equipment tag in technical_attributes, the
--    same shape Material Request lines use.
-- 5. v1_material_return_item_candidates groups delivered material per material
--    (description + size + unit) across all buildings, with search.
--
-- Data preservation: additive. Existing lines are backfilled (basis 'received',
-- technical attributes copied from their request line). Stock, movement, audit and
-- notification rows are untouched. Old clients keep working: the save payload is a
-- superset and receipt_review_line_id is still accepted.
-- Rollback is forward-only: restore the previous function bodies from
-- 20260824014644 in a corrective migration and drop the trigger; the added columns
-- and indexes are harmless to leave in place.

alter table public.v1_material_return_lines
  add column if not exists technical_attributes jsonb not null default '{}'::jsonb,
  add column if not exists basis_kind text;

update public.v1_material_return_lines return_line
set basis_kind = 'received'
where return_line.origin_kind = 'delivered'
  and return_line.basis_kind is null;

update public.v1_material_return_lines return_line
set technical_attributes = jsonb_strip_nulls(jsonb_build_object(
  'size', nullif(btrim(coalesce(request_line.technical_attributes ->> 'size', '')), ''),
  'model', nullif(btrim(coalesce(request_line.technical_attributes ->> 'model', '')), ''),
  'equipment_tag', nullif(btrim(coalesce(
    request_line.technical_attributes ->> 'equipment_tag', ''
  )), '')
))
from public.v1_material_request_lines request_line
where request_line.id = return_line.request_line_id
  and return_line.technical_attributes = '{}'::jsonb;

alter table public.v1_material_return_lines
  drop constraint if exists v1_material_return_lines_source_shape_check,
  drop constraint if exists v1_material_return_lines_basis_kind_check,
  drop constraint if exists v1_material_return_lines_technical_attributes_check;

alter table public.v1_material_return_lines
  add constraint v1_material_return_lines_basis_kind_check check (
    basis_kind is null or basis_kind in ('received', 'dispatched_unconfirmed')
  ),
  add constraint v1_material_return_lines_technical_attributes_check check (
    jsonb_typeof(technical_attributes) = 'object'
    and coalesce(length(technical_attributes ->> 'size'), 0) <= 120
    and coalesce(length(technical_attributes ->> 'model'), 0) <= 120
    and coalesce(length(technical_attributes ->> 'equipment_tag'), 0) <= 120
  ),
  add constraint v1_material_return_lines_source_shape_check check (
    (origin_kind = 'delivered'
      and dispatch_line_id is not null
      and request_line_id is not null
      and good_quantity_snapshot is not null
      and good_quantity_snapshot > 0
      and basis_kind is not null
      and (basis_kind <> 'received' or receipt_review_line_id is not null)
      and source_kind in ('warehouse', 'external_supplier'))
    or
    (origin_kind = 'custom'
      and receipt_review_line_id is null
      and dispatch_line_id is null
      and request_line_id is null
      and source_request_id is null
      and source_dispatch_id is null
      and good_quantity_snapshot is null
      and basis_kind is null
      and source_kind = 'custom')
  );

create unique index if not exists v1_material_return_lines_return_dispatch_line_key
  on public.v1_material_return_lines (material_return_id, dispatch_line_id)
  where dispatch_line_id is not null;
create index if not exists v1_material_return_lines_dispatch_line_idx
  on public.v1_material_return_lines (dispatch_line_id, material_return_id)
  where dispatch_line_id is not null;

-- Legacy writers (the request-scoped compatibility path) still insert lines that
-- only name a receipt review line; give them the basis and request-line metadata.
create or replace function public.v1_material_return_line_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.origin_kind = 'delivered' and new.basis_kind is null then
    new.basis_kind := case when new.receipt_review_line_id is null
      then 'dispatched_unconfirmed' else 'received' end;
  end if;
  if new.origin_kind = 'delivered' and new.request_line_id is not null
    and coalesce(new.technical_attributes, '{}'::jsonb) = '{}'::jsonb then
    select jsonb_strip_nulls(jsonb_build_object(
      'size', nullif(btrim(coalesce(request_line.technical_attributes ->> 'size', '')), ''),
      'model', nullif(btrim(coalesce(request_line.technical_attributes ->> 'model', '')), ''),
      'equipment_tag', nullif(btrim(coalesce(
        request_line.technical_attributes ->> 'equipment_tag', ''
      )), '')
    )) into new.technical_attributes
    from public.v1_material_request_lines request_line
    where request_line.id = new.request_line_id;
    new.technical_attributes := coalesce(new.technical_attributes, '{}'::jsonb);
  end if;
  return new;
end;
$$;

drop trigger if exists v1_material_return_line_defaults
  on public.v1_material_return_lines;
create trigger v1_material_return_line_defaults
before insert on public.v1_material_return_lines
for each row execute function public.v1_material_return_line_defaults();

-- Quantity of a dispatch line already committed to returns that still hold the
-- material (or brought it back). Drafts, returned-for-changes, rejected and
-- cancelled returns do not hold quantity.
create or replace function public.v1_material_return_active_quantity(
  p_dispatch_line_id uuid,
  p_exclude_return_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(return_line.return_quantity), 0)::numeric
  from public.v1_material_return_lines return_line
  join public.v1_material_returns material_return
    on material_return.id = return_line.material_return_id
  where return_line.dispatch_line_id = p_dispatch_line_id
    and material_return.id is distinct from p_exclude_return_id
    and material_return.state in (
      'awaiting_approval', 'approved', 'dispatched', 'confirmed'
    );
$$;

-- Basis of one dispatch line: confirmed good quantity, else dispatched quantity.
create or replace function public.v1_material_return_dispatch_basis(
  p_dispatch_line_id uuid
)
returns table (
  basis_quantity numeric,
  basis_kind text,
  receipt_review_line_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(review_line.good_qty, dispatch_line.dispatched_qty)::numeric,
    case when review_line.id is null then 'dispatched_unconfirmed' else 'received' end,
    review_line.id
  from public.v1_material_dispatch_lines dispatch_line
  left join lateral (
    select candidate.id, candidate.good_qty
    from public.v1_receipt_review_lines candidate
    join public.v1_receipt_reviews review on review.id = candidate.receipt_review_id
    where candidate.dispatch_line_id = dispatch_line.id
      and review.state = 'confirmed'
    order by review.reviewed_at desc, candidate.id
    limit 1
  ) review_line on true
  where dispatch_line.id = p_dispatch_line_id;
$$;

-- Receipt guard: a receipt review cannot leave less good material on site than is
-- already on active returns from the same dispatch line.
create or replace function public.v1_receipt_review_line_return_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active numeric;
begin
  -- Serialize with return submission, which locks the same dispatch line.
  perform 1 from public.v1_material_dispatch_lines dispatch_line
  where dispatch_line.id = new.dispatch_line_id for update;
  v_active := public.v1_material_return_active_quantity(new.dispatch_line_id, null);
  if new.good_qty < v_active then
    raise exception 'V1_RECEIPT_BELOW_ACTIVE_RETURNS'
      using errcode = '22023',
        detail = format('good=%s active_returns=%s', new.good_qty, v_active),
        hint = 'Reduce or cancel the Material Return for this delivery first.';
  end if;
  return new;
end;
$$;

drop trigger if exists v1_receipt_review_line_return_guard
  on public.v1_receipt_review_lines;
create trigger v1_receipt_review_line_return_guard
before insert or update of good_qty, dispatch_line_id
on public.v1_receipt_review_lines
for each row execute function public.v1_receipt_review_line_return_guard();

create or replace function public.v1_material_return_line_projection(
  p_return_id uuid,
  p_include_inventory boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', return_line.id,
    'origin_kind', return_line.origin_kind,
    'receipt_review_line_id', return_line.receipt_review_line_id,
    'dispatch_line_id', return_line.dispatch_line_id,
    'request_line_id', return_line.request_line_id,
    'basis_kind', return_line.basis_kind,
    'source_request_id', return_line.source_request_id,
    'source_request_number', source_request.request_number,
    'source_dispatch_id', return_line.source_dispatch_id,
    'source_dispatch_number', source_dispatch.dispatch_number,
    'source_scope_id', source_request.scope_id,
    'source_scope_name', source_scope.name,
    'display_order', return_line.display_order,
    'item_description', return_line.item_description,
    'brand_origin', return_line.brand_origin,
    'unit', return_line.unit,
    'size', return_line.technical_attributes ->> 'size',
    'model', return_line.technical_attributes ->> 'model',
    'equipment_tag', return_line.technical_attributes ->> 'equipment_tag',
    'item_code', nullif(btrim(source_item.item_code), ''),
    'source_kind', return_line.source_kind,
    'good_quantity_snapshot', return_line.good_quantity_snapshot,
    'eligible_quantity_at_submit', return_line.eligible_quantity_at_submit,
    'return_quantity', return_line.return_quantity,
    'line_note', return_line.line_note,
    'received_good_quantity', return_line.received_good_quantity,
    'received_damaged_quantity', return_line.received_damaged_quantity,
    'not_received_quantity', return_line.not_received_quantity,
    'receipt_note', return_line.receipt_note,
    'source_inventory_item_id', case when p_include_inventory
      then return_line.source_inventory_item_id else null end,
    'target_inventory_item_id', case when p_include_inventory
      then return_line.target_inventory_item_id else null end
  ) order by return_line.display_order), '[]'::jsonb)
  from public.v1_material_return_lines return_line
  left join public.v1_material_requests source_request
    on source_request.id = return_line.source_request_id
  left join public.v1_project_scopes source_scope
    on source_scope.id = source_request.scope_id
  left join public.v1_material_dispatches source_dispatch
    on source_dispatch.id = return_line.source_dispatch_id
  left join public.v1_inventory_items source_item
    on source_item.id = return_line.source_inventory_item_id
  where return_line.material_return_id = p_return_id;
$$;

-- Grouped, searchable delivered material for the return composer.
create or replace function public.v1_material_return_item_candidates(
  p_project_id uuid,
  p_return_id uuid default null,
  p_search text default null,
  p_scope_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set jit = off
as $$
declare
  v_search text := nullif(regexp_replace(btrim(coalesce(p_search, '')), '\s+', ' ', 'g'), '');
  v_like text;
  v_result jsonb;
begin
  if not public.v1_can_create_project_material_return(p_project_id) then
    raise exception 'V1_MATERIAL_RETURN_CREATE_DENIED' using errcode = '42501';
  end if;
  if (v_search is not null and length(v_search) > 120)
    or (p_scope_id is not null and not exists (
      select 1 from public.v1_project_scopes scope
      where scope.id = p_scope_id and scope.project_id = p_project_id
    )) then
    raise exception 'V1_MATERIAL_RETURN_CANDIDATES_INVALID' using errcode = '22023';
  end if;
  if p_return_id is not null and not exists (
    select 1 from public.v1_material_returns material_return
    where material_return.id = p_return_id
      and material_return.project_id = p_project_id
      and material_return.state in ('draft', 'returned_for_changes')
      and (material_return.drafted_by_auth_user_id = auth.uid()
        or public.v1_current_role() = 'admin')
  ) then
    raise exception 'V1_MATERIAL_RETURN_DRAFT_NOT_EDITABLE' using errcode = '42501';
  end if;
  v_like := case when v_search is null then null
    else '%' || replace(replace(replace(lower(v_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;

  with source as (
    select
      dispatch_line.id as dispatch_line_id,
      dispatch_line.request_line_id,
      dispatch_line.source_kind,
      dispatch_line.item_description,
      dispatch_line.brand_origin,
      dispatch_line.unit,
      dispatch_line.dispatched_qty,
      dispatch.id as dispatch_id,
      dispatch.dispatch_number,
      dispatch.dispatched_at,
      request.id as request_id,
      request.request_number,
      request.scope_id,
      nullif(btrim(coalesce(request_line.technical_attributes ->> 'size', '')), '') as size,
      nullif(btrim(coalesce(request_line.technical_attributes ->> 'model', '')), '') as model,
      nullif(btrim(coalesce(
        request_line.technical_attributes ->> 'equipment_tag', ''
      )), '') as equipment_tag,
      nullif(btrim(item.item_code), '') as item_code,
      review_line.id as receipt_review_line_id,
      coalesce(review_line.good_qty, dispatch_line.dispatched_qty) as basis_qty,
      case when review_line.id is null then 'dispatched_unconfirmed'
        else 'received' end as basis_kind
    from public.v1_material_dispatch_lines dispatch_line
    join public.v1_material_dispatches dispatch
      on dispatch.id = dispatch_line.dispatch_id
    join public.v1_material_requests request on request.id = dispatch.request_id
    join public.v1_material_request_lines request_line
      on request_line.id = dispatch_line.request_line_id
    left join public.v1_inventory_items item on item.id = dispatch_line.inventory_item_id
    left join lateral (
      select candidate.id, candidate.good_qty
      from public.v1_receipt_review_lines candidate
      join public.v1_receipt_reviews review on review.id = candidate.receipt_review_id
      where candidate.dispatch_line_id = dispatch_line.id
        and review.state = 'confirmed'
      order by review.reviewed_at desc, candidate.id
      limit 1
    ) review_line on true
    where dispatch.project_id = p_project_id
      and request.project_id = p_project_id
      and (p_scope_id is null or request.scope_id = p_scope_id)
  ),
  active as (
    select return_line.dispatch_line_id, sum(return_line.return_quantity) as quantity
    from public.v1_material_return_lines return_line
    join public.v1_material_returns material_return
      on material_return.id = return_line.material_return_id
    join source on source.dispatch_line_id = return_line.dispatch_line_id
    where material_return.id is distinct from p_return_id
      and material_return.state in (
        'awaiting_approval', 'approved', 'dispatched', 'confirmed'
      )
    group by return_line.dispatch_line_id
  ),
  sourced as (
    select source.*,
      coalesce(active.quantity, 0) as active_qty,
      greatest(source.basis_qty - coalesce(active.quantity, 0), 0) as returnable_qty,
      lower(regexp_replace(btrim(source.item_description), '\s+', ' ', 'g'))
        || chr(31) || lower(coalesce(regexp_replace(source.size, '\s+', ' ', 'g'), ''))
        || chr(31) || lower(btrim(source.unit)) as item_key
    from source
    left join active on active.dispatch_line_id = source.dispatch_line_id
  ),
  matched as (
    select sourced.* from sourced
    where v_like is null
      or lower(sourced.item_description) like v_like
      or lower(coalesce(sourced.size, '')) like v_like
      or lower(coalesce(sourced.model, '')) like v_like
      or lower(coalesce(sourced.equipment_tag, '')) like v_like
      or lower(coalesce(sourced.brand_origin, '')) like v_like
      or lower(coalesce(sourced.item_code, '')) like v_like
      or lower(coalesce(sourced.request_number, '')) like v_like
      or lower(coalesce(sourced.dispatch_number, '')) like v_like
      or extensions.word_similarity(lower(v_search), lower(sourced.item_description)) >= 0.5
  ),
  grouped as (
    select
      matched.item_key,
      min(matched.item_description) as item_description,
      min(matched.size) as size,
      min(matched.unit) as unit,
      coalesce(array_agg(distinct matched.model) filter (where matched.model is not null),
        '{}') as models,
      coalesce(array_agg(distinct matched.equipment_tag)
        filter (where matched.equipment_tag is not null), '{}') as equipment_tags,
      coalesce(array_agg(distinct btrim(matched.brand_origin))
        filter (where nullif(btrim(matched.brand_origin), '') is not null), '{}') as brand_origins,
      coalesce(array_agg(distinct matched.item_code)
        filter (where matched.item_code is not null), '{}') as item_codes,
      sum(matched.dispatched_qty) as delivered_qty,
      sum(matched.active_qty) as on_active_returns_qty,
      sum(matched.returnable_qty) as returnable_qty,
      sum(matched.returnable_qty) filter (where matched.basis_kind = 'dispatched_unconfirmed')
        as unconfirmed_returnable_qty,
      max(matched.dispatched_at) as last_delivered_at,
      jsonb_agg(jsonb_build_object(
        'dispatch_line_id', matched.dispatch_line_id,
        'receipt_review_line_id', matched.receipt_review_line_id,
        'request_line_id', matched.request_line_id,
        'request_id', matched.request_id,
        'request_number', matched.request_number,
        'dispatch_id', matched.dispatch_id,
        'dispatch_number', matched.dispatch_number,
        'scope_id', matched.scope_id,
        'delivered_at', matched.dispatched_at,
        'brand_origin', matched.brand_origin,
        'model', matched.model,
        'equipment_tag', matched.equipment_tag,
        'item_code', matched.item_code,
        'source_kind', matched.source_kind,
        'basis_kind', matched.basis_kind,
        'dispatched_qty', trim_scale(matched.dispatched_qty),
        'basis_qty', trim_scale(matched.basis_qty),
        'on_active_returns_qty', trim_scale(matched.active_qty),
        'returnable_qty', trim_scale(matched.returnable_qty)
      ) order by matched.dispatched_at desc, matched.dispatch_number desc,
        matched.dispatch_line_id) filter (where matched.returnable_qty > 0) as sources
    from matched
    group by matched.item_key
    having sum(matched.returnable_qty) > 0
  )
  select jsonb_build_object(
    'project_id', p_project_id,
    'generated_at', clock_timestamp(),
    'search', v_search,
    'scope_id', p_scope_id,
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'key', grouped.item_key,
      'item_description', grouped.item_description,
      'size', grouped.size,
      'unit', grouped.unit,
      'models', to_jsonb(grouped.models),
      'equipment_tags', to_jsonb(grouped.equipment_tags),
      'brand_origins', to_jsonb(grouped.brand_origins),
      'item_codes', to_jsonb(grouped.item_codes),
      'delivered_qty', trim_scale(grouped.delivered_qty),
      'on_active_returns_qty', trim_scale(grouped.on_active_returns_qty),
      'returnable_qty', trim_scale(grouped.returnable_qty),
      'unconfirmed_returnable_qty', trim_scale(coalesce(grouped.unconfirmed_returnable_qty, 0)),
      'last_delivered_at', grouped.last_delivered_at,
      'sources', grouped.sources
    ) order by
      case when v_search is not null
        and lower(grouped.item_description) like v_like then 0 else 1 end,
      lower(grouped.item_description), lower(coalesce(grouped.size, '')),
      lower(grouped.unit)), '[]'::jsonb)
  ) into v_result
  from grouped;
  return v_result;
end;
$$;

create or replace function public.v1_material_return_creation_workspace(
  p_project_id uuid,
  p_return_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not public.v1_can_create_project_material_return(p_project_id) then
    raise exception 'V1_MATERIAL_RETURN_CREATE_DENIED' using errcode = '42501';
  end if;
  if p_return_id is not null and not exists (
    select 1 from public.v1_material_returns material_return
    where material_return.id = p_return_id
      and material_return.project_id = p_project_id
      and material_return.state in ('draft', 'returned_for_changes')
      and (material_return.drafted_by_auth_user_id = auth.uid()
        or public.v1_current_role() = 'admin')
  ) then
    raise exception 'V1_MATERIAL_RETURN_DRAFT_NOT_EDITABLE' using errcode = '42501';
  end if;
  -- `candidates` keeps the original receipt-confirmed shape for released clients;
  -- committed quantities now count every active line on the same dispatch line.
  select jsonb_build_object(
    'project_id', project.id,
    'project_ref', project.project_ref,
    'project_name', project.name,
    'scopes', coalesce((select jsonb_agg(jsonb_build_object(
      'id', scope.id, 'name', scope.name, 'scope_kind', scope.scope_kind
    ) order by case when scope.scope_kind = 'common' then 0 else 1 end,
      scope.name)
      from public.v1_project_scopes scope
      where scope.project_id = project.id and scope.is_active), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(unit_record.short_code order by
      unit_record.unit_type, unit_record.name, unit_record.id)
      from public.v1_configuration_units unit_record
      where unit_record.is_active), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object(
      'receipt_review_line_id', review_line.id,
      'request_id', request.id,
      'request_number', request.request_number,
      'dispatch_id', dispatch.id,
      'dispatch_number', dispatch.dispatch_number,
      'scope_id', request.scope_id,
      'scope_name', scope.name,
      'item_description', dispatch_line.item_description,
      'brand_origin', dispatch_line.brand_origin,
      'unit', dispatch_line.unit,
      'source_kind', dispatch_line.source_kind,
      'good_received_qty', review_line.good_qty,
      'committed_return_qty', committed.quantity,
      'eligible_return_qty', greatest(0, review_line.good_qty - committed.quantity)
    ) order by review.reviewed_at desc, dispatch_line.created_at)
      from public.v1_receipt_review_lines review_line
      join public.v1_receipt_reviews review on review.id = review_line.receipt_review_id
      join public.v1_material_dispatch_lines dispatch_line
        on dispatch_line.id = review_line.dispatch_line_id
      join public.v1_material_dispatches dispatch on dispatch.id = dispatch_line.dispatch_id
      join public.v1_material_requests request on request.id = dispatch.request_id
      join public.v1_project_scopes scope on scope.id = request.scope_id
      cross join lateral (
        select public.v1_material_return_active_quantity(
          dispatch_line.id, p_return_id
        ) as quantity
      ) committed
      where request.project_id = project.id and review.state = 'confirmed'
        and review_line.good_qty > 0), '[]'::jsonb),
    'draft', case when p_return_id is null then null
      else public.v1_material_return_detail_projection(p_return_id) end
  ) into v_result
  from public.v1_projects project where project.id = p_project_id;
  return v_result;
end;
$$;

create or replace function public.v1_save_project_material_return_draft(
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_return_id uuid := nullif(btrim(coalesce(p_payload ->> 'return_id', '')), '')::uuid;
  v_project_id uuid := nullif(btrim(coalesce(p_payload ->> 'project_id', '')), '')::uuid;
  v_scope_id uuid := nullif(btrim(coalesce(p_payload ->> 'scope_id', '')), '')::uuid;
  v_expected_version integer := nullif(p_payload ->> 'expected_version', '')::integer;
  v_purpose text := nullif(btrim(coalesce(p_payload ->> 'purpose', '')), '');
  v_note text := nullif(btrim(coalesce(p_payload ->> 'note', '')), '');
  v_requested_date date := nullif(p_payload ->> 'requested_return_date', '')::date;
  v_lines jsonb := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_return public.v1_material_returns%rowtype;
  v_existing jsonb;
  v_response jsonb;
  v_line jsonb;
  v_origin text;
  v_review_line_id uuid;
  v_dispatch_line_id uuid;
  v_qty numeric(18, 4);
  v_source record;
  v_basis record;
  v_active numeric;
  v_description text;
  v_brand text;
  v_unit text;
  v_line_note text;
  v_technical jsonb;
  v_seen uuid[] := '{}';
  v_order integer := 0;
begin
  perform public.v1_assert_object_keys(p_payload, array[
    'return_id', 'project_id', 'scope_id', 'expected_version', 'purpose',
    'note', 'requested_return_date', 'lines'
  ], 'save_project_material_return_draft');
  if v_project_id is null or v_scope_id is null or v_expected_version is null
    or v_expected_version < 0 or v_purpose is null
    or jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) = 0
    or jsonb_array_length(v_lines) > 500
    or not public.v1_can_create_project_material_return(v_project_id)
    or not exists (select 1 from public.v1_project_scopes scope
      where scope.id = v_scope_id and scope.project_id = v_project_id
        and scope.is_active) then
    raise exception 'V1_MATERIAL_RETURN_DRAFT_PAYLOAD_INVALID'
      using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_project_material_return_draft', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
  perform 1 from public.v1_projects project where project.id = v_project_id for update;
  if v_return_id is null then
    if v_expected_version <> 0 then
      raise exception 'V1_MATERIAL_RETURN_DRAFT_VERSION_CONFLICT'
        using errcode = '40001';
    end if;
  else
    select * into v_return from public.v1_material_returns material_return
    where material_return.id = v_return_id and material_return.project_id = v_project_id
    for update;
    if not found or v_return.state not in ('draft', 'returned_for_changes')
      or (v_return.drafted_by_auth_user_id <> v_actor
        and public.v1_current_role() <> 'admin') then
      raise exception 'V1_MATERIAL_RETURN_DRAFT_NOT_EDITABLE'
        using errcode = '42501';
    end if;
    if v_return.record_version <> v_expected_version then
      raise exception 'V1_MATERIAL_RETURN_DRAFT_VERSION_CONFLICT'
        using errcode = '40001';
    end if;
  end if;
  if v_return_id is null then
    insert into public.v1_material_returns (
      request_id, project_id, scope_id, state, purpose, note,
      requested_return_date, drafted_by_auth_user_id, drafted_by_role
    ) values (
      null, v_project_id, v_scope_id, 'draft', v_purpose, v_note,
      v_requested_date, v_actor, v_exact_role
    ) returning * into v_return;
    v_return_id := v_return.id;
  else
    delete from public.v1_material_return_lines
    where material_return_id = v_return_id;
    update public.v1_material_returns
    set scope_id = v_scope_id, state = 'draft', purpose = v_purpose,
        note = v_note, requested_return_date = v_requested_date,
        returned_for_changes_reason = null,
        record_version = record_version + 1, updated_at = clock_timestamp()
    where id = v_return_id returning * into v_return;
  end if;

  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'V1_MATERIAL_RETURN_LINE_INVALID' using errcode = '22023';
    end if;
    perform public.v1_assert_object_keys(v_line, array[
      'origin_kind', 'receipt_review_line_id', 'dispatch_line_id',
      'item_description', 'brand_origin', 'unit', 'size', 'model',
      'equipment_tag', 'return_qty', 'note'
    ], 'project_material_return_line');
    v_origin := coalesce(v_line ->> 'origin_kind', '');
    v_review_line_id := nullif(btrim(coalesce(
      v_line ->> 'receipt_review_line_id', ''
    )), '')::uuid;
    v_dispatch_line_id := nullif(btrim(coalesce(
      v_line ->> 'dispatch_line_id', ''
    )), '')::uuid;
    v_qty := nullif(v_line ->> 'return_qty', '')::numeric(18, 4);
    v_description := nullif(btrim(coalesce(v_line ->> 'item_description', '')), '');
    v_brand := nullif(btrim(coalesce(v_line ->> 'brand_origin', '')), '');
    v_unit := nullif(btrim(coalesce(v_line ->> 'unit', '')), '');
    v_line_note := nullif(btrim(coalesce(v_line ->> 'note', '')), '');
    if v_origin not in ('delivered', 'custom') or v_qty is null or v_qty <= 0
      or length(coalesce(v_line_note, '')) > 1000 then
      raise exception 'V1_MATERIAL_RETURN_LINE_INVALID' using errcode = '22023';
    end if;
    v_order := v_order + 1;
    if v_origin = 'delivered' then
      if v_dispatch_line_id is null and v_review_line_id is not null then
        select review_line.dispatch_line_id into v_dispatch_line_id
        from public.v1_receipt_review_lines review_line
        where review_line.id = v_review_line_id;
      end if;
      select dispatch_line.id dispatch_line_id, dispatch_line.request_line_id,
        dispatch_line.source_kind, dispatch_line.inventory_item_id,
        dispatch_line.item_description, dispatch_line.brand_origin,
        dispatch_line.unit, dispatch.id dispatch_id, request.id request_id,
        request_line.technical_attributes
      into v_source
      from public.v1_material_dispatch_lines dispatch_line
      join public.v1_material_dispatches dispatch on dispatch.id = dispatch_line.dispatch_id
      join public.v1_material_requests request on request.id = dispatch.request_id
      join public.v1_material_request_lines request_line
        on request_line.id = dispatch_line.request_line_id
      where dispatch_line.id = v_dispatch_line_id
        and dispatch.project_id = v_project_id
        and request.project_id = v_project_id;
      if not found then
        raise exception 'V1_MATERIAL_RETURN_SOURCE_INVALID' using errcode = '22023';
      end if;
      if v_dispatch_line_id = any(v_seen) then
        raise exception 'V1_MATERIAL_RETURN_LINE_DUPLICATE' using errcode = '22023';
      end if;
      v_seen := v_seen || v_dispatch_line_id;
      select * into v_basis
      from public.v1_material_return_dispatch_basis(v_dispatch_line_id);
      if v_review_line_id is not null
        and v_review_line_id is distinct from v_basis.receipt_review_line_id then
        raise exception 'V1_MATERIAL_RETURN_SOURCE_INVALID' using errcode = '22023';
      end if;
      v_active := public.v1_material_return_active_quantity(v_dispatch_line_id, v_return_id);
      if v_basis.basis_quantity <= 0 then
        raise exception 'V1_MATERIAL_RETURN_SOURCE_INVALID' using errcode = '22023';
      end if;
      if v_qty > v_basis.basis_quantity - v_active then
        raise exception 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED'
          using errcode = '22023';
      end if;
      insert into public.v1_material_return_lines (
        material_return_id, receipt_review_line_id, dispatch_line_id,
        request_line_id, origin_kind, source_request_id, source_dispatch_id,
        source_kind, source_inventory_item_id, item_description, brand_origin,
        unit, technical_attributes, basis_kind, good_quantity_snapshot,
        return_quantity, line_note, display_order
      ) values (
        v_return_id, v_basis.receipt_review_line_id, v_source.dispatch_line_id,
        v_source.request_line_id, 'delivered', v_source.request_id,
        v_source.dispatch_id, v_source.source_kind,
        v_source.inventory_item_id, v_source.item_description,
        v_source.brand_origin, v_source.unit,
        jsonb_strip_nulls(jsonb_build_object(
          'size', nullif(btrim(coalesce(v_source.technical_attributes ->> 'size', '')), ''),
          'model', nullif(btrim(coalesce(v_source.technical_attributes ->> 'model', '')), ''),
          'equipment_tag', nullif(btrim(coalesce(
            v_source.technical_attributes ->> 'equipment_tag', ''
          )), '')
        )),
        v_basis.basis_kind, v_basis.basis_quantity, v_qty, v_line_note, v_order
      );
    else
      v_technical := jsonb_strip_nulls(jsonb_build_object(
        'size', nullif(btrim(coalesce(v_line ->> 'size', '')), ''),
        'model', nullif(btrim(coalesce(v_line ->> 'model', '')), ''),
        'equipment_tag', nullif(btrim(coalesce(v_line ->> 'equipment_tag', '')), '')
      ));
      if v_description is null or length(v_description) > 500
        or length(coalesce(v_brand, '')) > 200
        or coalesce(length(v_technical ->> 'size'), 0) > 120
        or coalesce(length(v_technical ->> 'model'), 0) > 120
        or coalesce(length(v_technical ->> 'equipment_tag'), 0) > 120
        or v_unit is null or not exists (
          select 1 from public.v1_configuration_units controlled_unit
          where controlled_unit.is_active
            and lower(btrim(controlled_unit.short_code)) = lower(btrim(v_unit))
        ) then
        raise exception 'V1_MATERIAL_RETURN_CUSTOM_LINE_INVALID'
          using errcode = '22023';
      end if;
      insert into public.v1_material_return_lines (
        material_return_id, origin_kind, source_kind, item_description,
        brand_origin, unit, technical_attributes, return_quantity, line_note,
        display_order
      ) values (
        v_return_id, 'custom', 'custom', v_description, v_brand, v_unit,
        v_technical, v_qty, v_line_note, v_order
      );
    end if;
  end loop;

  v_response := public.v1_material_return_detail_projection(v_return_id);
  perform public.v1_write_audit_event(
    'material_return_draft_saved', 'material_return', v_return_id, v_project_id,
    null, jsonb_build_object('line_count', v_order, 'source', 'project_wide'),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_save_project_material_return_draft', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_submit_project_material_return(
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_return_id uuid := nullif(btrim(coalesce(p_payload ->> 'return_id', '')), '')::uuid;
  v_expected_version integer := nullif(p_payload ->> 'expected_version', '')::integer;
  v_return public.v1_material_returns%rowtype;
  v_line public.v1_material_return_lines%rowtype;
  v_basis record;
  v_committed numeric;
  v_sequence integer;
  v_number text;
  v_default_purpose text;
  v_existing jsonb;
  v_response jsonb;
begin
  perform public.v1_assert_object_keys(p_payload,
    array['return_id', 'expected_version'], 'submit_project_material_return');
  if v_return_id is null or v_expected_version is null or v_expected_version < 1 then
    raise exception 'V1_MATERIAL_RETURN_SUBMIT_PAYLOAD_INVALID'
      using errcode = '22023';
  end if;
  select * into v_return from public.v1_material_returns material_return
  where material_return.id = v_return_id for update;
  if not found or not public.v1_can_create_project_material_return(v_return.project_id)
    or (v_return.drafted_by_auth_user_id <> v_actor
      and public.v1_current_role() <> 'admin') then
    raise exception 'V1_MATERIAL_RETURN_SUBMIT_DENIED' using errcode = '42501';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_submit_project_material_return', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;
  if v_return.state not in ('draft', 'returned_for_changes')
    or v_return.record_version <> v_expected_version then
    raise exception 'V1_MATERIAL_RETURN_SUBMIT_VERSION_CONFLICT'
      using errcode = '40001';
  end if;
  if not exists (select 1 from public.v1_material_return_lines line
    where line.material_return_id = v_return.id) then
    raise exception 'V1_MATERIAL_RETURN_LINES_REQUIRED' using errcode = '22023';
  end if;
  if v_return.purpose is null then
    select 'Return from material request ' || request.request_number
      into v_default_purpose
    from public.v1_material_requests request
    where request.id = v_return.request_id;
    if v_default_purpose is null then
      raise exception 'V1_MATERIAL_RETURN_PURPOSE_REQUIRED'
        using errcode = '22023';
    end if;
  end if;
  -- Lock every source dispatch line in a stable order. Receipt reviews take the
  -- same lock (v1_receipt_review_line_return_guard), so a receipt and a return
  -- submission for one delivery can never both pass their checks concurrently.
  perform 1 from public.v1_material_dispatch_lines dispatch_line
  where dispatch_line.id in (
    select line.dispatch_line_id from public.v1_material_return_lines line
    where line.material_return_id = v_return.id and line.dispatch_line_id is not null
  )
  order by dispatch_line.id
  for update;
  for v_line in select line.* from public.v1_material_return_lines line
    where line.material_return_id = v_return.id order by line.id for update
  loop
    if v_line.origin_kind = 'delivered' then
      select * into v_basis
      from public.v1_material_return_dispatch_basis(v_line.dispatch_line_id);
      v_committed := public.v1_material_return_active_quantity(
        v_line.dispatch_line_id, v_return.id
      );
      if v_basis.basis_quantity is null
        or v_line.return_quantity > v_basis.basis_quantity - v_committed then
        raise exception 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED'
          using errcode = '22023';
      end if;
      update public.v1_material_return_lines
      set eligible_quantity_at_submit = v_basis.basis_quantity - v_committed,
          good_quantity_snapshot = v_basis.basis_quantity,
          basis_kind = v_basis.basis_kind,
          receipt_review_line_id = v_basis.receipt_review_line_id
      where id = v_line.id;
    end if;
  end loop;
  if v_return.return_number is null then
    insert into public.v1_return_reference_counters (
      project_id, next_return_sequence, updated_at
    ) values (v_return.project_id, 2, clock_timestamp())
    on conflict (project_id) do update set
      next_return_sequence = public.v1_return_reference_counters.next_return_sequence + 1,
      updated_at = clock_timestamp()
    returning next_return_sequence - 1 into v_sequence;
    select project.project_ref || '-RTN' || lpad(v_sequence::text, 3, '0')
      into v_number from public.v1_projects project
      where project.id = v_return.project_id;
  else
    v_number := v_return.return_number;
  end if;
  update public.v1_material_returns
  set state = 'awaiting_approval', return_number = v_number,
      purpose = coalesce(purpose, v_default_purpose),
      submitted_by_auth_user_id = v_actor, submitted_by_role = v_exact_role,
      submitted_at = clock_timestamp(), returned_for_changes_reason = null,
      record_version = record_version + 1, updated_at = clock_timestamp()
  where id = v_return.id;

  insert into public.v1_notifications (
    recipient_auth_user_id, event_code, entity_type, entity_id, project_id
  )
  select candidate.auth_user_id, 'material_return_approval_required',
    'material_return', v_return.id, v_return.project_id
  from (
    select member.member_auth_user_id auth_user_id
    from public.v1_project_members member
    where member.project_id = v_return.project_id
      and member.project_role = 'project_engineer'
      and member.effective_from <= clock_timestamp()
      and (member.effective_to is null or member.effective_to > clock_timestamp())
    union
    select profile.auth_user_id
    from public.v1_profiles profile
    join auth.users auth_user on auth_user.id = profile.auth_user_id
    where profile.is_active and coalesce(
      auth_user.raw_app_meta_data ->> 'role', ''
    ) in (
      'senior_mechanical_engineer', 'project_manager',
      'workshop_in_charge', 'document_controller', 'admin'
    )
  ) candidate
  where candidate.auth_user_id <> v_actor
  on conflict do nothing;

  v_response := public.v1_material_return_detail_projection(v_return.id);
  perform public.v1_write_audit_event(
    'material_return_submitted_for_approval', 'material_return', v_return.id,
    v_return.project_id, null, jsonb_build_object('return_number', v_number),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_submit_project_material_return', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

revoke all on function public.v1_material_return_line_defaults()
  from public, anon, authenticated;
revoke all on function public.v1_receipt_review_line_return_guard()
  from public, anon, authenticated;
revoke all on function public.v1_material_return_active_quantity(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_material_return_dispatch_basis(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_material_return_line_projection(uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.v1_material_return_item_candidates(uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_material_return_creation_workspace(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_save_project_material_return_draft(jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_submit_project_material_return(jsonb, uuid)
  from public, anon, authenticated;

grant execute on function public.v1_material_return_item_candidates(uuid, uuid, text, uuid)
  to authenticated, service_role;
grant execute on function public.v1_material_return_creation_workspace(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.v1_save_project_material_return_draft(jsonb, uuid)
  to authenticated, service_role;
grant execute on function public.v1_submit_project_material_return(jsonb, uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';

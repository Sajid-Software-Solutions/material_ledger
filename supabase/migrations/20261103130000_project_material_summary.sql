-- Yorks V1 read-only project Material Summary.
--
-- Purpose: answer "how much of each material was requested for, and sent to,
-- this project" overall, per calendar month and per Monday-Sunday week, with
-- the Material Requests that carried each item.
--
-- Rules (frozen with the product owner, 3 November 2026):
-- - Every quantity is attributed to the date its Material Request was
--   submitted, in Asia/Dubai. Weeks start on Monday and end on Sunday.
-- - Requested quantity counts submitted, non-cancelled requests. Sent
--   quantity counts every committed dispatch line, including lines that were
--   dispatched before a later cancellation, because the material physically
--   went to the project. Returned quantity counts confirmed returns only.
-- - Items are grouped by case- and whitespace-insensitive description plus
--   unit. Different spellings are never merged; search returns close
--   spellings next to each other so the reader can see all of them.
-- - Operational only: no unit cost, total cost, supplier or valuation field
--   can enter the response.
--
-- Data preservation: read-only projection. The only schema change is an
-- additive index. Rollback is forward-only: revoke or drop this function and
-- index in a corrective migration; no data is affected.

create index if not exists v1_material_return_lines_request_line_idx
  on public.v1_material_return_lines (request_line_id)
  where request_line_id is not null;

create or replace function public.v1_project_material_summary(
  p_project_id uuid,
  p_from date default null,
  p_to date default null,
  p_scope_id uuid default null,
  p_search text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
-- The many grouped CTEs give the planner inflated row estimates that trigger
-- JIT compilation; measured at ~1.4 s of compile time for a ~40 ms query.
set jit = off
as $$
declare
  v_search text := nullif(
    btrim(regexp_replace(coalesce(p_search, ''), '\s+', ' ', 'g')),
    ''
  );
  v_like text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or p_project_id is null
    or not public.v1_project_readable(p_project_id) then
    raise exception 'V1_PROJECT_MATERIAL_SUMMARY_DENIED'
      using errcode = '42501';
  end if;

  if (p_from is not null and p_to is not null and p_from > p_to)
    or char_length(coalesce(v_search, '')) > 120
    or (
      p_scope_id is not null and not exists (
        select 1 from public.v1_project_scopes scope
        where scope.id = p_scope_id and scope.project_id = p_project_id
      )
    ) then
    raise exception 'V1_PROJECT_MATERIAL_SUMMARY_INVALID'
      using errcode = '22023';
  end if;

  v_search := lower(v_search);
  v_like := '%' || replace(replace(replace(
    coalesce(v_search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';

  with source_lines as (
    select
      line.id as request_line_id,
      request.id as request_id,
      request.request_number,
      request.scope_id,
      (request.submitted_at at time zone 'Asia/Dubai')::date as requested_on,
      btrim(regexp_replace(line.item_description, '\s+', ' ', 'g'))
        as item_description,
      nullif(btrim(line.brand_origin), '') as brand_origin,
      btrim(line.unit) as unit,
      case when request.state = 'cancelled' then 0::numeric
        else line.requested_qty end as requested_qty
    from public.v1_material_requests request
    join public.v1_material_request_lines line
      on line.request_id = request.id
    where request.project_id = p_project_id
      and request.state <> 'draft'
      and request.submitted_at is not null
      and request.request_number is not null
      and (p_scope_id is null or request.scope_id = p_scope_id)
      and (p_from is null
        or (request.submitted_at at time zone 'Asia/Dubai')::date >= p_from)
      and (p_to is null
        or (request.submitted_at at time zone 'Asia/Dubai')::date <= p_to)
  ),
  sent as (
    select
      dispatch_line.request_line_id,
      sum(dispatch_line.dispatched_qty) as quantity,
      array_agg(distinct btrim(item.item_code)) filter (
        where nullif(btrim(item.item_code), '') is not null
      ) as item_codes
    from public.v1_material_dispatch_lines dispatch_line
    join source_lines source
      on source.request_line_id = dispatch_line.request_line_id
    left join public.v1_inventory_items item
      on item.id = dispatch_line.inventory_item_id
    group by dispatch_line.request_line_id
  ),
  returned as (
    select
      return_line.request_line_id,
      sum(coalesce(
        return_line.received_good_quantity, return_line.return_quantity
      )) as quantity
    from public.v1_material_return_lines return_line
    join public.v1_material_returns material_return
      on material_return.id = return_line.material_return_id
    join source_lines source
      on source.request_line_id = return_line.request_line_id
    where material_return.state = 'confirmed'
    group by return_line.request_line_id
  ),
  facts as (
    select
      source.*,
      lower(source.item_description) || chr(31) || lower(source.unit)
        as item_key,
      coalesce(sent.quantity, 0) as sent_qty,
      coalesce(returned.quantity, 0) as returned_qty,
      coalesce(sent.item_codes, '{}'::text[]) as item_codes
    from source_lines source
    left join sent on sent.request_line_id = source.request_line_id
    left join returned on returned.request_line_id = source.request_line_id
  ),
  filtered as (
    select fact.*
    from facts fact
    where (fact.requested_qty > 0 or fact.sent_qty > 0
        or fact.returned_qty > 0)
      and (
        v_search is null
        or lower(fact.item_description) like v_like
        or lower(fact.request_number) like v_like
        or lower(coalesce(fact.brand_origin, '')) like v_like
        or exists (
          select 1 from unnest(fact.item_codes) code
          where lower(code) like v_like
        )
        or (
          char_length(v_search) >= 3
          and extensions.word_similarity(
            v_search, lower(fact.item_description)
          ) >= 0.5
        )
      )
  ),
  item_codes as (
    select fact.item_key, array_agg(distinct code order by code) as codes
    from filtered fact
    cross join lateral unnest(fact.item_codes) code
    group by fact.item_key
  ),
  items as (
    select
      fact.item_key,
      mode() within group (order by fact.item_description) as item_description,
      mode() within group (order by fact.unit) as unit,
      coalesce(
        array_agg(distinct fact.brand_origin)
          filter (where fact.brand_origin is not null),
        '{}'::text[]
      ) as brand_origins,
      sum(fact.requested_qty) as requested_qty,
      sum(fact.sent_qty) as sent_qty,
      sum(fact.returned_qty) as returned_qty,
      min(fact.requested_on) as first_requested_on,
      max(fact.requested_on) as last_requested_on
    from filtered fact
    group by fact.item_key
  ),
  ranked_items as (
    select item.*,
      (row_number() over (
        order by lower(item.item_description), lower(item.unit), item.item_key
      ) - 1)::integer as item_index
    from items item
  ),
  ranked_requests as (
    select distinct_request.*,
      (row_number() over (
        order by distinct_request.requested_on,
          distinct_request.request_number, distinct_request.request_id
      ) - 1)::integer as request_index
    from (
      select distinct fact.request_id, fact.request_number, fact.requested_on,
        fact.scope_id
      from filtered fact
    ) distinct_request
  ),
  indexed as (
    select fact.*, item.item_index, request.request_index
    from filtered fact
    join ranked_items item on item.item_key = fact.item_key
    join ranked_requests request on request.request_id = fact.request_id
  ),
  item_request_refs as (
    select refs.item_index,
      array_agg(refs.request_index order by refs.request_index) as refs
    from (
      select distinct item_index, request_index from indexed
    ) refs
    group by refs.item_index
  ),
  periods as (
    select
      bucket.granularity,
      bucket.period_start,
      fact.item_index,
      sum(fact.requested_qty) as requested_qty,
      sum(fact.sent_qty) as sent_qty,
      sum(fact.returned_qty) as returned_qty,
      array_agg(distinct fact.request_index) as request_refs
    from indexed fact
    cross join lateral (
      values
        ('month'::text, date_trunc('month', fact.requested_on)::date),
        ('week'::text, date_trunc('week', fact.requested_on)::date)
    ) bucket(granularity, period_start)
    group by bucket.granularity, bucket.period_start, fact.item_index
  )
  -- Compact, index-based shape: each request and item is sent once; every
  -- period row is [period_start, item_index, requested, sent, returned,
  -- [request_index...]]. Quantities are exact decimal strings.
  select jsonb_build_object(
    'project_id', p_project_id,
    'timezone', 'Asia/Dubai',
    'week_starts_on', 'monday',
    'generated_at', clock_timestamp(),
    'filters', jsonb_build_object(
      'from', p_from,
      'to', p_to,
      'scope_id', p_scope_id,
      'search', v_search
    ),
    'scopes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scope.id,
        'name', scope.name,
        'scope_kind', scope.scope_kind,
        'is_active', scope.is_active
      ) order by (scope.scope_kind = 'common') desc, scope.name, scope.id)
      from public.v1_project_scopes scope
      where scope.project_id = p_project_id
    ), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', request.request_id,
        'number', request.request_number,
        'requested_on', request.requested_on,
        'scope_id', request.scope_id
      ) order by request.request_index)
      from ranked_requests request
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', item.item_key,
        'item_description', item.item_description,
        'unit', item.unit,
        'brand_origins', to_jsonb(item.brand_origins),
        'item_codes', to_jsonb(coalesce(codes.codes, '{}'::text[])),
        'requested_qty', trim_scale(item.requested_qty)::text,
        'sent_qty', trim_scale(item.sent_qty)::text,
        'returned_qty', trim_scale(item.returned_qty)::text,
        'first_requested_on', item.first_requested_on,
        'last_requested_on', item.last_requested_on,
        'request_refs', to_jsonb(coalesce(refs.refs, '{}'::integer[]))
      ) order by item.item_index)
      from ranked_items item
      left join item_codes codes on codes.item_key = item.item_key
      left join item_request_refs refs on refs.item_index = item.item_index
    ), '[]'::jsonb),
    'months', coalesce((
      select jsonb_agg(jsonb_build_array(
        period.period_start, period.item_index,
        trim_scale(period.requested_qty)::text,
        trim_scale(period.sent_qty)::text,
        trim_scale(period.returned_qty)::text,
        to_jsonb(period.request_refs)
      ) order by period.period_start desc, period.item_index)
      from periods period where period.granularity = 'month'
    ), '[]'::jsonb),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_array(
        period.period_start, period.item_index,
        trim_scale(period.requested_qty)::text,
        trim_scale(period.sent_qty)::text,
        trim_scale(period.returned_qty)::text,
        to_jsonb(period.request_refs)
      ) order by period.period_start desc, period.item_index)
      from periods period where period.granularity = 'week'
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.v1_project_material_summary(
  uuid, date, date, uuid, text
) from public, anon, authenticated;
grant execute on function public.v1_project_material_summary(
  uuid, date, date, uuid, text
) to authenticated, service_role;

comment on function public.v1_project_material_summary(
  uuid, date, date, uuid, text
) is
  'Authorized non-commercial project summary of requested, sent and returned material quantities by item, month and Monday-Sunday week (Asia/Dubai).';

notify pgrst, 'reload schema';

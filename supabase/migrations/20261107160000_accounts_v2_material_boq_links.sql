-- R39 Accounts Workspace V2 — link Material Supply items to BOQ folders
--
-- Owner request of 7 November 2026: connect the BOQ to the item breakdown so
-- deliveries can tell the claim what has arrived, with both sides still edited
-- on their own. Common / All Buildings stays out (FR-031): it is not a building
-- a contract is split across, so only a physical building's own BOQ folders can
-- be linked, and never the Workshop Materials folder.
--
-- * v1_accounts_material_boq_links: which BOQ folders of a building stand for an
--   item of an items-measured stage. Keyed by building, stage and item key, so
--   a link outlives a contract revision. Configuration only: no money.
-- * v1_get_accounts_material_sources: each physical building's linkable BOQ
--   folders, the links, and per linked item what has been delivered: the good
--   quantity on confirmed receipt reviews of Material Requests raised from
--   those folders, less what was confirmed returned. Quantities and delivery
--   references only; nothing commercial. When every BOQ row shares the item's
--   unit the quantities add up; otherwise the item gets the share of its BOQ
--   rows delivered (a 1 Lot item 40% delivered is 0.4): by quantity when the
--   rows share one unit, as the average row share when their units differ.
--   A folder stands for one item of a stage, so nothing is counted twice.
-- * v1_save_accounts_material_boq_links: replaces a project's links in one
--   step, with configure_project_commercials, a reason and an audit event.
--
-- Delivered quantities only suggest progress. The Project Engineer still
-- confirms it on the workbench, with evidence, as before.
--
-- Additive and idempotent: one table, four functions. The BOQ, Material Request,
-- dispatch and receipt tables are only read.
-- Rollback: drop the three public functions, the two helpers and the table; no
-- other object refers to them.

create table if not exists public.v1_accounts_material_boq_links (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.v1_projects(id) on delete restrict,
  project_scope_id uuid not null references public.v1_project_scopes(id) on delete restrict,
  stage_key text not null check (btrim(stage_key) <> ''),
  item_key text not null check (btrim(item_key) <> ''),
  boq_group_id uuid not null references public.v1_boq_groups(id) on delete restrict,
  created_by_auth_user_id uuid not null,
  created_by_exact_role text not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (project_scope_id, stage_key, item_key, boq_group_id)
);

create index if not exists v1_accounts_material_boq_links_project_idx
  on public.v1_accounts_material_boq_links(project_id);

alter table public.v1_accounts_material_boq_links enable row level security;
revoke all on table public.v1_accounts_material_boq_links from public, anon, authenticated;

-- A unit written so that the usual spellings of one unit compare equal.
create or replace function public.v1_accounts_unit_key(p_unit text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when u in ('no', 'nos', 'nr', 'nrs', 'number', 'numbers', 'pc', 'pcs', 'piece',
      'pieces', 'ea', 'each', 'unit', 'units') then 'nos'
    when u in ('lot', 'lots', 'ls', 'l.s', 'lump sum', 'lumpsum', 'job') then 'lot'
    when u in ('m2', 'sqm', 'sq.m', 'sq m', 'm²') then 'm2'
    when u in ('m', 'lm', 'rm', 'mtr', 'mtrs', 'meter', 'meters', 'metre', 'metres') then 'm'
    when u in ('set', 'sets') then 'set'
    else u
  end
  from (select lower(btrim(regexp_replace(coalesce(p_unit, ''), '\.$', ''))) as u) x;
$$;

-- A BOQ cell as a number, or null when it is not one.
create or replace function public.v1_accounts_boq_number(p_value text)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
begin
  return nullif(btrim(replace(coalesce(p_value, ''), ',', '')), '')::numeric;
exception when others then
  return null;
end;
$$;

revoke all on function public.v1_accounts_unit_key(text) from public, anon, authenticated;
revoke all on function public.v1_accounts_boq_number(text) from public, anon, authenticated;

create or replace function public.v1_get_accounts_material_sources(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_baseline uuid;
  v_folders jsonb;
  v_links jsonb;
  v_delivered jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');

  select current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;

  -- A physical building's own folders, never Workshop Materials or archived.
  select coalesce(jsonb_agg(jsonb_build_object(
      'boq_group_id', f.id,
      'project_scope_id', f.scope_id,
      'name', f.name,
      'template_key', f.template_key,
      'row_count', f.row_count,
      'unit', f.unit,
      'quantity', f.quantity::text
    ) order by f.building_order, f.display_order, f.name), '[]'::jsonb)
  into v_folders
  from (
    select g.id, g.scope_id, g.name, g.display_order, t.template_key,
      scope.scope_code as building_order,
      (select count(*) from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived) as row_count,
      (select case when count(distinct public.v1_accounts_unit_key(r.canonical_values ->> 'unit')) = 1
          then min(btrim(r.canonical_values ->> 'unit')) end
        from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived) as unit,
      (select case when count(distinct public.v1_accounts_unit_key(r.canonical_values ->> 'unit')) = 1
          then sum(public.v1_accounts_boq_number(r.canonical_values ->> 'quantity')) end
        from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived) as quantity
    from public.v1_boq_groups g
    join public.v1_project_scopes scope on scope.id = g.scope_id
    left join public.v1_boq_group_templates t on t.id = g.template_id
    where g.project_id = p_project_id
      and scope.scope_kind = 'building'
      and not g.is_archived
      and coalesce(t.template_key, '') <> 'workshop_materials'
  ) f;

  select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', l.project_scope_id,
      'stage_key', l.stage_key,
      'item_key', l.item_key,
      'boq_group_id', l.boq_group_id
    ) order by l.project_scope_id, l.stage_key, l.item_key, l.boq_group_id), '[]'::jsonb)
  into v_links
  from public.v1_accounts_material_boq_links l
  where l.project_id = p_project_id;

  -- What arrived, per BOQ row: good quantity received less confirmed returns.
  with linked_rows as (
    select l.project_scope_id, l.stage_key, l.item_key, r.id as row_id,
      public.v1_accounts_boq_number(r.canonical_values ->> 'quantity') as row_qty,
      public.v1_accounts_unit_key(r.canonical_values ->> 'unit') as row_unit
    from public.v1_accounts_material_boq_links l
    join public.v1_boq_groups g on g.id = l.boq_group_id and not g.is_archived
    join public.v1_boq_rows r on r.group_id = g.id and not r.is_archived
    where l.project_id = p_project_id
  ),
  -- One line per delivery of a row, so an item counts each delivery once even
  -- when it brought several of the item's rows.
  received_lines as (
    select mrl.source_boq_row_id as row_id, d.id as dispatch_id, d.dispatch_date,
      d.created_at, d.delivery_reference, rrl.good_qty
    from public.v1_receipt_review_lines rrl
    join public.v1_receipt_reviews rr on rr.id = rrl.receipt_review_id and rr.state = 'confirmed'
    join public.v1_material_dispatch_lines dl on dl.id = rrl.dispatch_line_id
    join public.v1_material_dispatches d on d.id = dl.dispatch_id
    join public.v1_material_request_lines mrl on mrl.id = dl.request_line_id
    where d.project_id = p_project_id
      and mrl.source_boq_row_id in (select row_id from linked_rows)
      and rrl.good_qty > 0
  ),
  received as (
    select row_id, sum(good_qty) as good
    from received_lines
    group by row_id
  ),
  item_deliveries as (
    select lr.project_scope_id, lr.stage_key, lr.item_key,
      count(distinct rl.dispatch_id)::integer as deliveries,
      max(rl.dispatch_date) as last_date,
      (array_agg(rl.delivery_reference order by rl.dispatch_date desc nulls last,
        rl.created_at desc) filter (where rl.delivery_reference is not null))[1] as last_reference
    from linked_rows lr
    join received_lines rl on rl.row_id = lr.row_id
    group by lr.project_scope_id, lr.stage_key, lr.item_key
  ),
  returned as (
    -- As the Material Request read nets them: what Procurement confirmed
    -- receiving back, or the quantity returned when that was not recorded.
    select mrl.source_boq_row_id as row_id,
      sum(coalesce(rl.received_good_quantity, rl.return_quantity)) as back
    from public.v1_material_return_lines rl
    join public.v1_material_returns mr on mr.id = rl.material_return_id
    join public.v1_material_request_lines mrl on mrl.id = rl.request_line_id
    where mr.project_id = p_project_id and mr.state = 'confirmed'
      and rl.origin_kind = 'delivered'
      and mrl.source_boq_row_id in (select row_id from linked_rows)
    group by mrl.source_boq_row_id
  ),
  per_row as (
    select lr.*, greatest(coalesce(rc.good, 0) - coalesce(rt.back, 0), 0) as delivered
    from linked_rows lr
    left join received rc on rc.row_id = lr.row_id
    left join returned rt on rt.row_id = lr.row_id
  ),
  -- Rows in the item's unit add up. Rows in one other unit give the share of
  -- their total delivered; rows in mixed units give the average row share.
  per_item as (
    select p.project_scope_id, p.stage_key, p.item_key,
      si.quantity as item_qty,
      bool_and(p.row_unit = public.v1_accounts_unit_key(si.unit_code))
        filter (where p.row_qty > 0) as same_unit,
      count(distinct p.row_unit) filter (where p.row_qty > 0) = 1 as rows_one_unit,
      sum(p.delivered) as delivered_sum,
      sum(least(p.delivered, p.row_qty)) filter (where p.row_qty > 0) as capped_sum,
      sum(p.row_qty) filter (where p.row_qty > 0) as row_total,
      avg(least(p.delivered / p.row_qty, 1)) filter (where p.row_qty > 0) as row_share
    from per_row p
    join public.v1_accounts_baseline_stage_items si
      on si.baseline_revision_id = v_baseline
     and si.project_scope_id = p.project_scope_id
     and si.stage_key = p.stage_key
     and si.item_key = p.item_key
    group by p.project_scope_id, p.stage_key, p.item_key, si.quantity, si.unit_code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', i.project_scope_id,
      'stage_key', i.stage_key,
      'item_key', i.item_key,
      'basis', case when coalesce(i.same_unit, false) then 'quantity' else 'share' end,
      'delivered_qty', round(case
        when coalesce(i.same_unit, false) then i.delivered_sum
        when coalesce(i.rows_one_unit, false) and i.row_total > 0
          then i.capped_sum / i.row_total * i.item_qty
        else coalesce(i.row_share, 0) * i.item_qty end, 4)::text,
      'deliveries', d.deliveries,
      'last_delivery_reference', d.last_reference,
      'last_delivery_date', d.last_date
    ) order by i.project_scope_id, i.stage_key, i.item_key), '[]'::jsonb)
  into v_delivered
  from per_item i
  join item_deliveries d
    on d.project_scope_id = i.project_scope_id
   and d.stage_key = i.stage_key
   and d.item_key = i.item_key;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', p_project_id,
    'can_link', public.v1_current_user_has_capability('configure_project_commercials', p_project_id),
    'folders', v_folders,
    'links', v_links,
    'delivered', v_delivered
  );
end;
$$;

create or replace function public.v1_save_accounts_material_boq_links(
  p_project_id uuid,
  p_links jsonb,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exact text;
  v_baseline uuid;
  v_link jsonb;
  v_scope uuid;
  v_group uuid;
  v_before jsonb;
  v_after jsonb;
  v_existing jsonb;
  v_payload jsonb;
  v_response jsonb;
begin
  v_exact := public.v1_accounts_require_capability(p_project_id, 'configure_project_commercials');
  if jsonb_typeof(coalesce(p_links, 'null'::jsonb)) <> 'array' then
    raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'links', p_links);
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_accounts_material_boq_links', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_material_links|' || p_project_id::text, 0));

  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'stage_key', stage_key, 'item_key', item_key, 'boq_group_id', boq_group_id)
      order by project_scope_id, stage_key, item_key, boq_group_id), '[]'::jsonb)
  into v_before
  from public.v1_accounts_material_boq_links where project_id = p_project_id;

  select current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;

  -- Every link: an item of the current contract in a physical building of this
  -- project, and one of that building's own folders, not Workshop Materials
  -- and not archived.
  for v_link in select value from jsonb_array_elements(p_links) loop
    begin
      v_scope := (v_link ->> 'project_scope_id')::uuid;
      v_group := (v_link ->> 'boq_group_id')::uuid;
    exception when others then
      raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
    end;
    if nullif(btrim(coalesce(v_link ->> 'stage_key', '')), '') is null
      or nullif(btrim(coalesce(v_link ->> 'item_key', '')), '') is null
      or not exists (
        select 1 from public.v1_project_scopes s
        where s.id = v_scope and s.project_id = p_project_id and s.scope_kind = 'building')
      or not exists (
        select 1 from public.v1_accounts_baseline_stage_items si
        where si.baseline_revision_id = v_baseline and si.project_scope_id = v_scope
          and si.stage_key = btrim(v_link ->> 'stage_key')
          and si.item_key = btrim(v_link ->> 'item_key'))
      or not exists (
        select 1 from public.v1_boq_groups g
        left join public.v1_boq_group_templates t on t.id = g.template_id
        where g.id = v_group and g.project_id = p_project_id and g.scope_id = v_scope
          and not g.is_archived and coalesce(t.template_key, '') <> 'workshop_materials') then
      raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
    end if;
  end loop;

  -- A folder stands for one item of a stage, so no delivery is counted twice.
  if exists (
    select 1 from (
      select distinct l ->> 'project_scope_id' as s, btrim(l ->> 'stage_key') as st,
        btrim(l ->> 'item_key') as it, l ->> 'boq_group_id' as g
      from jsonb_array_elements(p_links) l
    ) x group by s, st, g having count(*) > 1) then
    raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
  end if;

  delete from public.v1_accounts_material_boq_links where project_id = p_project_id;
  insert into public.v1_accounts_material_boq_links(
    project_id, project_scope_id, stage_key, item_key, boq_group_id,
    created_by_auth_user_id, created_by_exact_role)
  select distinct p_project_id, (l ->> 'project_scope_id')::uuid, btrim(l ->> 'stage_key'),
    btrim(l ->> 'item_key'), (l ->> 'boq_group_id')::uuid, auth.uid(), v_exact
  from jsonb_array_elements(p_links) l;

  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'stage_key', stage_key, 'item_key', item_key, 'boq_group_id', boq_group_id)
      order by project_scope_id, stage_key, item_key, boq_group_id), '[]'::jsonb)
  into v_after
  from public.v1_accounts_material_boq_links where project_id = p_project_id;

  perform public.v1_write_audit_event('accounts.material_links.saved',
    'accounts_material_links', p_project_id, p_project_id,
    jsonb_build_object('links', v_before), jsonb_build_object('links', v_after),
    btrim(p_reason), p_idempotency_key);

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'link_count', jsonb_array_length(v_after));
  perform public.v1_complete_idempotency(
    'v1_save_accounts_material_boq_links', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_get_accounts_material_sources(uuid) from public, anon;
revoke all on function public.v1_save_accounts_material_boq_links(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.v1_get_accounts_material_sources(uuid) to authenticated;
grant execute on function public.v1_save_accounts_material_boq_links(uuid, jsonb, text, uuid) to authenticated;

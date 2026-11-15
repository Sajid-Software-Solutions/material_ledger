-- Release bundle: contract materials (PRODUCT_DECISIONS.md section 61).
-- Applies migration 20261115120000 in one transaction, then checks itself.
-- Adds one table (BOQ row ties, configuration only), two internal helpers and
-- three functions, and replaces v1_get_accounts_material_sources and
-- v1_save_accounts_material_boq_links. No existing row changes. Re-running it
-- is harmless.
-- Before it: run the read-only supabase/preflight/contract_materials_preflight.sql
-- and check both live functions still match 20261107160000.
-- Apply by hand (staging, then production, each with the owner's OK):
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/contract_materials_bundle.sql
-- Like the other hand-applied bundles it does not write
-- supabase_migrations.schema_migrations.
-- Rollback: supabase/release/contract_materials_rollback.sql

begin;

create table if not exists public.v1_accounts_material_boq_row_links (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.v1_projects(id) on delete restrict,
  project_scope_id uuid not null references public.v1_project_scopes(id) on delete restrict,
  item_key text not null check (btrim(item_key) <> '' and item_key = btrim(item_key)),
  boq_row_id uuid not null references public.v1_boq_rows(id) on delete restrict,
  created_by_auth_user_id uuid not null,
  created_by_exact_role text not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (boq_row_id),
  unique (project_scope_id, item_key)
);

create index if not exists v1_accounts_material_boq_row_links_project_idx
  on public.v1_accounts_material_boq_row_links(project_id);

alter table public.v1_accounts_material_boq_row_links enable row level security;
revoke all on table public.v1_accounts_material_boq_row_links
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- What has reached site per item: the reading of 20261107160000, with tied
-- contract rows added. A live row of a linked folder counts for its link's
-- stage; a live tied row counts for its line's Material Supply item.
-- Good quantity on confirmed receipt reviews, less what Procurement confirmed
-- receiving back. Rows in the item's unit add up; rows in one other unit give
-- the share of their total delivered; rows in mixed units give the average
-- row share.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_material_delivered(p_project_id uuid)
returns table (
  project_scope_id uuid,
  stage_key text,
  item_key text,
  basis text,
  delivered_qty numeric,
  deliveries integer,
  last_delivery_reference text,
  last_delivery_date date
)
language sql
stable
security definer
set search_path = ''
as $$
  with baseline as (
    select cp.current_baseline_revision_id as id
    from public.v1_accounts_project_commercial_profiles cp
    where cp.project_id = p_project_id
  ),
  linked_rows as (
    select l.project_scope_id, l.stage_key, l.item_key, r.id as row_id,
      public.v1_accounts_boq_number(r.canonical_values ->> 'quantity') as row_qty,
      public.v1_accounts_unit_key(r.canonical_values ->> 'unit') as row_unit
    from public.v1_accounts_material_boq_links l
    join public.v1_boq_groups g on g.id = l.boq_group_id and not g.is_archived
    join public.v1_boq_rows r on r.group_id = g.id and not r.is_archived
    where l.project_id = p_project_id
    union all
    select rl.project_scope_id, 'material_supply'::text, rl.item_key, r.id,
      public.v1_accounts_boq_number(r.canonical_values ->> 'quantity'),
      public.v1_accounts_unit_key(r.canonical_values ->> 'unit')
    from public.v1_accounts_material_boq_row_links rl
    join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived
    join public.v1_boq_groups g on g.id = r.group_id and not g.is_archived
    where rl.project_id = p_project_id
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
      on si.baseline_revision_id = (select id from baseline)
     and si.project_scope_id = p.project_scope_id
     and si.stage_key = p.stage_key
     and si.item_key = p.item_key
    group by p.project_scope_id, p.stage_key, p.item_key, si.quantity, si.unit_code
  )
  select i.project_scope_id, i.stage_key, i.item_key,
    case when coalesce(i.same_unit, false) then 'quantity' else 'share' end,
    round(case
      when coalesce(i.same_unit, false) then i.delivered_sum
      when coalesce(i.rows_one_unit, false) and i.row_total > 0
        then i.capped_sum / i.row_total * i.item_qty
      else coalesce(i.row_share, 0) * i.item_qty end, 4),
    d.deliveries, d.last_reference, d.last_date
  from per_item i
  join item_deliveries d
    on d.project_scope_id = i.project_scope_id
   and d.stage_key = i.stage_key
   and d.item_key = i.item_key;
$$;

revoke all on function public.v1_accounts_material_delivered(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Every line of every items-measured stage on the current contract, with what
-- is confirmed and what the invoiced claims carried: the quantity as it stood
-- when the latest invoiced claim was checked (the invoice's "to date"), and
-- the invoice of the latest claim that moved it. Internal: the reads below
-- decide what the caller may see.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_contract_line_facts(p_project_id uuid)
returns table (
  project_scope_id uuid,
  building_name text,
  scope_code text,
  stage_key text,
  stage_label text,
  stage_order integer,
  progress_entry_id uuid,
  stage_item_id uuid,
  item_key text,
  item_label text,
  display_order integer,
  quantity numeric,
  unit_code text,
  weight_percent numeric,
  item_value numeric,
  confirmed_qty numeric,
  needs_review boolean,
  invoiced_qty numeric,
  last_invoice_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with baseline as (
    select cp.current_baseline_revision_id as id
    from public.v1_accounts_project_commercial_profiles cp
    where cp.project_id = p_project_id
      and cp.current_baseline_revision_id is not null
  ),
  claims as (
    select c.id, c.ready_for_accounts_at as at,
      row_number() over (order by c.ready_for_accounts_at, c.created_at, c.id) as n
    from public.v1_accounts_client_claims c
    where c.project_id = p_project_id
      and c.status = 'invoiced'
      and c.ready_for_accounts_at is not null
  ),
  items as (
    select si.project_scope_id, scope.name as building_name, scope.scope_code,
      si.stage_key, sa.stage_name as stage_label, sa.display_order as stage_order,
      bp.id as progress_entry_id, si.id as stage_item_id, si.item_key,
      si.item_label, si.display_order, si.quantity, si.unit_code,
      si.weight_percent_of_contract as weight_percent,
      public.v1_accounts_stage_item_value(si.id) as item_value,
      coalesce(ip.confirmed_qty, 0) as confirmed_qty,
      coalesce(ip.needs_review, false) as needs_review
    from baseline b
    join public.v1_accounts_baseline_stage_items si on si.baseline_revision_id = b.id
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = b.id
     and sa.stage_key = si.stage_key
     and sa.measurement_mode = 'items'
    join public.v1_project_scopes scope on scope.id = si.project_scope_id
    left join public.v1_accounts_billing_progress bp
      on bp.baseline_revision_id = b.id
     and bp.project_scope_id = si.project_scope_id
     and bp.stage_key = si.stage_key
    left join public.v1_accounts_billing_item_progress ip on ip.stage_item_id = si.id
  ),
  at_claims as (
    select i.stage_item_id, cl.n, cl.id as claim_id,
      least(i.quantity, public.v1_accounts_item_qty_at(p_project_id,
        i.project_scope_id, i.stage_key, i.item_key, cl.at)) as qty
    from items i
    cross join claims cl
  ),
  moved as (
    select a.*,
      a.qty <> coalesce(lag(a.qty) over (partition by a.stage_item_id order by a.n), 0)
        as changed
    from at_claims a
  )
  select i.project_scope_id, i.building_name, i.scope_code, i.stage_key,
    i.stage_label, i.stage_order, i.progress_entry_id, i.stage_item_id,
    i.item_key, i.item_label, i.display_order, i.quantity, i.unit_code,
    i.weight_percent, i.item_value, i.confirmed_qty, i.needs_review,
    coalesce((select m.qty from moved m where m.stage_item_id = i.stage_item_id
      order by m.n desc limit 1), 0),
    (select inv.id
     from moved m
     join public.v1_accounts_client_invoices inv on inv.claim_id = m.claim_id
     where m.stage_item_id = i.stage_item_id and m.changed and m.qty > 0
       and inv.status not in ('cancelled', 'superseded')
     order by m.n desc, inv.revision_number desc, inv.created_at desc
     limit 1)
  from items i;
$$;

revoke all on function public.v1_accounts_contract_line_facts(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Accounts › Materials: each building's contract lines, as the invoice's
-- material and installation sheets print them, but live.
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_accounts_material_register(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set jit = off
as $$
declare
  v_values boolean;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_stages jsonb;
  v_buildings jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  v_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );

  select br.* into v_baseline
  from public.v1_accounts_project_commercial_profiles cp
  join public.v1_accounts_baseline_revisions br on br.id = cp.current_baseline_revision_id
  where cp.project_id = p_project_id;
  if v_baseline.id is null then
    return jsonb_build_object(
      'schema_version', 1, 'project_id', p_project_id,
      'baseline_revision_id', null, 'baseline_revision_number', null,
      'can_view_values', v_values,
      'stages', '[]'::jsonb, 'buildings', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'stage_key', sa.stage_key, 'stage_label', sa.stage_name,
      'display_order', sa.display_order) order by sa.display_order), '[]'::jsonb)
  into v_stages
  from public.v1_accounts_baseline_stage_allocations sa
  where sa.baseline_revision_id = v_baseline.id and sa.measurement_mode = 'items';

  with facts as materialized (
    select * from public.v1_accounts_contract_line_facts(p_project_id)
  ),
  site as materialized (
    select * from public.v1_accounts_material_delivered(p_project_id) d
    where d.stage_key = 'material_supply'
  ),
  ties as (
    select rl.project_scope_id, rl.item_key, rl.boq_row_id, r.group_id as boq_group_id
    from public.v1_accounts_material_boq_row_links rl
    join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived
    join public.v1_boq_groups g on g.id = r.group_id and not g.is_archived
    where rl.project_id = p_project_id
  ),
  stage_lines as (
    select f.project_scope_id, f.item_key, f.item_label, f.display_order, f.stage_order,
      jsonb_build_object(
        'stage_key', f.stage_key,
        'stage_item_id', f.stage_item_id,
        'quantity', f.quantity::text,
        'unit_code', f.unit_code,
        'confirmed_qty', f.confirmed_qty::text,
        'needs_review', f.needs_review)
      || case when v_values then jsonb_build_object(
          'weight_percent', f.weight_percent::text,
          'amount', f.item_value::text,
          'rate', round(f.item_value / f.quantity, 2)::text,
          'done_amount', round(f.item_value * least(f.confirmed_qty, f.quantity)
            / f.quantity, 2)::text,
          'invoiced_qty', f.invoiced_qty::text,
          'last_invoice', (
            select jsonb_build_object('invoice_id', inv.id,
              'invoice_reference', inv.invoice_reference, 'status', inv.status)
            from public.v1_accounts_client_invoices inv
            where inv.id = f.last_invoice_id))
        else '{}'::jsonb end as stage_json
    from facts f
  ),
  lines as (
    select sl.project_scope_id, sl.item_key,
      min(sl.display_order) as display_order,
      (array_agg(sl.item_label order by sl.stage_order))[1] as item_label,
      jsonb_agg(sl.stage_json order by sl.stage_order) as stages
    from stage_lines sl
    group by sl.project_scope_id, sl.item_key
  ),
  cells as (
    select distinct f.project_scope_id, f.stage_key, f.stage_label, f.stage_order,
      f.progress_entry_id
    from facts f
    where f.progress_entry_id is not null
  ),
  billed as (
    select l.project_scope_id, l.stage_key,
      coalesce(sum(l.claimed_amount) filter (where c.status = 'invoiced'), 0) as invoiced,
      coalesce(sum(l.claimed_amount)
        filter (where c.status in ('draft', 'ready_for_accounts')), 0) as in_claim
    from public.v1_accounts_client_claim_lines l
    join public.v1_accounts_client_claims c on c.id = l.claim_id
    where c.project_id = p_project_id
    group by l.project_scope_id, l.stage_key
  ),
  cell_json as (
    select c.project_scope_id, c.stage_order,
      jsonb_build_object('stage_key', c.stage_key, 'stage_label', c.stage_label,
        'display_order', c.stage_order)
      || case when v_values then (
          select jsonb_build_object(
            'stage_value', round(public.v1_accounts_stage_value(c.progress_entry_id), 2)::text,
            'done_amount', x.done::text,
            'invoiced_amount', x.invoiced::text,
            'in_claim_amount', x.in_claim::text,
            'not_invoiced_amount', greatest(x.done - x.invoiced, 0)::text,
            'over_invoiced', x.invoiced > x.done)
          from (
            select public.v1_accounts_progress_eligible_amount(c.progress_entry_id) as done,
              coalesce(b.invoiced, 0)::numeric(20,2) as invoiced,
              coalesce(b.in_claim, 0)::numeric(20,2) as in_claim
            from (select 1) one
            left join billed b
              on b.project_scope_id = c.project_scope_id and b.stage_key = c.stage_key
          ) x)
        else '{}'::jsonb end as js
    from cells c
  ),
  buildings as (
    select distinct f.project_scope_id, f.building_name, f.scope_code
    from facts f
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', b.project_scope_id,
      'building_name', b.building_name,
      'scope_code', b.scope_code,
      'stages', coalesce((
        select jsonb_agg(cj.js order by cj.stage_order)
        from cell_json cj where cj.project_scope_id = b.project_scope_id), '[]'::jsonb),
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
            'item_key', ln.item_key,
            'item_label', ln.item_label,
            'display_order', ln.display_order,
            'boq_row_id', t.boq_row_id,
            'boq_group_id', t.boq_group_id,
            'site', case when s.item_key is null then null else jsonb_build_object(
              'basis', s.basis,
              'delivered_qty', s.delivered_qty::text,
              'deliveries', s.deliveries,
              'last_delivery_reference', s.last_delivery_reference,
              'last_delivery_date', s.last_delivery_date) end,
            'stages', ln.stages)
          order by ln.display_order, ln.item_key)
        from lines ln
        left join ties t
          on t.project_scope_id = ln.project_scope_id and t.item_key = ln.item_key
        left join site s
          on s.project_scope_id = ln.project_scope_id and s.item_key = ln.item_key
        where ln.project_scope_id = b.project_scope_id), '[]'::jsonb)
    ) order by b.scope_code, b.building_name), '[]'::jsonb)
  into v_buildings
  from buildings b;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', p_project_id,
    'baseline_revision_id', v_baseline.id,
    'baseline_revision_number', v_baseline.revision_number,
    'can_view_values', v_values,
    'stages', v_stages,
    'buildings', v_buildings)
    || case when v_values then jsonb_build_object(
        'currency_code', v_baseline.currency_code,
        'contract_value', v_baseline.contract_value::text)
      else '{}'::jsonb end;
end;
$$;

-- ---------------------------------------------------------------------------
-- BOQ › a folder's tied rows: what was requested and received for each, and,
-- for those who may see Accounts, where its contract line stands.
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_boq_contract_status(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set jit = off
as $$
declare
  v_group public.v1_boq_groups%rowtype;
  v_progress boolean := false;
  v_values boolean := false;
  v_currency text;
  v_rows jsonb;
begin
  select * into v_group from public.v1_boq_groups where id = p_group_id;
  if not found
    or not public.v1_project_readable(v_group.project_id)
    or not public.v1_current_user_has_capability('boq.view', v_group.project_id) then
    raise exception 'V1_BOQ_GROUP_NOT_READABLE' using errcode = '42501';
  end if;
  v_progress := public.v1_current_user_has_capability(
    'view_project_accounts', v_group.project_id);
  v_values := v_progress and public.v1_current_user_has_capability(
    'view_project_commercial_values', v_group.project_id);
  if v_values then
    select br.currency_code into v_currency
    from public.v1_accounts_project_commercial_profiles cp
    join public.v1_accounts_baseline_revisions br on br.id = cp.current_baseline_revision_id
    where cp.project_id = v_group.project_id;
  end if;

  with tied as (
    select rl.boq_row_id, rl.project_scope_id, rl.item_key, r.display_order
    from public.v1_accounts_material_boq_row_links rl
    join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived
    where r.group_id = p_group_id and rl.project_id = v_group.project_id
  ),
  -- Submitted requests that are not cancelled; drafts never count.
  requested as (
    select line.source_boq_row_id as row_id, sum(line.requested_qty) as qty
    from public.v1_material_request_lines line
    join public.v1_material_requests request on request.id = line.request_id
    where request.project_id = v_group.project_id
      and line.source_boq_row_id in (select boq_row_id from tied)
      and request.state not in ('draft', 'cancelled')
      and request.submitted_at is not null
    group by line.source_boq_row_id
  ),
  received_lines as (
    select mrl.source_boq_row_id as row_id, d.id as dispatch_id, d.dispatch_date,
      d.created_at, d.delivery_reference, rrl.good_qty
    from public.v1_receipt_review_lines rrl
    join public.v1_receipt_reviews rr on rr.id = rrl.receipt_review_id and rr.state = 'confirmed'
    join public.v1_material_dispatch_lines dl on dl.id = rrl.dispatch_line_id
    join public.v1_material_dispatches d on d.id = dl.dispatch_id
    join public.v1_material_request_lines mrl on mrl.id = dl.request_line_id
    where d.project_id = v_group.project_id
      and mrl.source_boq_row_id in (select boq_row_id from tied)
      and rrl.good_qty > 0
  ),
  received as (
    select rl.row_id, sum(rl.good_qty) as good,
      count(distinct rl.dispatch_id)::integer as deliveries,
      max(rl.dispatch_date) as last_date,
      (array_agg(rl.delivery_reference order by rl.dispatch_date desc nulls last,
        rl.created_at desc) filter (where rl.delivery_reference is not null))[1] as last_reference
    from received_lines rl
    group by rl.row_id
  ),
  returned as (
    select mrl.source_boq_row_id as row_id,
      sum(coalesce(rl.received_good_quantity, rl.return_quantity)) as back
    from public.v1_material_return_lines rl
    join public.v1_material_returns mr on mr.id = rl.material_return_id
    join public.v1_material_request_lines mrl on mrl.id = rl.request_line_id
    where mr.project_id = v_group.project_id and mr.state = 'confirmed'
      and rl.origin_kind = 'delivered'
      and mrl.source_boq_row_id in (select boq_row_id from tied)
    group by mrl.source_boq_row_id
  ),
  facts as materialized (
    select f.* from public.v1_accounts_contract_line_facts(v_group.project_id) f
    where v_progress
      and (f.project_scope_id, f.item_key) in (select project_scope_id, item_key from tied)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'boq_row_id', t.boq_row_id,
      'project_scope_id', t.project_scope_id,
      'item_key', t.item_key,
      'requested_qty', coalesce(q.qty, 0)::text,
      'received_qty', greatest(coalesce(rc.good, 0) - coalesce(rt.back, 0), 0)::text,
      'deliveries', coalesce(rc.deliveries, 0),
      'last_delivery_reference', rc.last_reference,
      'last_delivery_date', rc.last_date)
    || case when v_progress then jsonb_build_object('stages', coalesce((
        select jsonb_agg(jsonb_build_object(
            'stage_key', f.stage_key,
            'stage_label', f.stage_label,
            'quantity', f.quantity::text,
            'unit_code', f.unit_code,
            'confirmed_qty', f.confirmed_qty::text)
          || case when v_values then jsonb_build_object(
              'amount', f.item_value::text,
              'rate', round(f.item_value / f.quantity, 2)::text)
            else '{}'::jsonb end
          order by f.stage_order)
        from facts f
        where f.project_scope_id = t.project_scope_id and f.item_key = t.item_key), '[]'::jsonb))
      else '{}'::jsonb end
    order by t.display_order, t.boq_row_id), '[]'::jsonb)
  into v_rows
  from tied t
  left join requested q on q.row_id = t.boq_row_id
  left join received rc on rc.row_id = t.boq_row_id
  left join returned rt on rt.row_id = t.boq_row_id;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', v_group.project_id,
    'group_id', p_group_id,
    'can_view_progress', v_progress,
    'can_view_values', v_values,
    'rows', v_rows)
    || case when v_values and v_currency is not null
      then jsonb_build_object('currency_code', v_currency) else '{}'::jsonb end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tie BOQ rows to contract lines. Replaces the project's ties in one step.
-- ---------------------------------------------------------------------------
create or replace function public.v1_save_accounts_material_row_links(
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
  v_row uuid;
  v_item text;
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
  v_payload := jsonb_build_object('project_id', p_project_id, 'row_links', p_links);
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_accounts_material_row_links', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  -- The same lock as the folder links: the two never interleave.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_material_links|' || p_project_id::text, 0));

  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'item_key', item_key, 'boq_row_id', boq_row_id)
      order by project_scope_id, item_key, boq_row_id), '[]'::jsonb)
  into v_before
  from public.v1_accounts_material_boq_row_links where project_id = p_project_id;

  select current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;

  -- Every tie: a line of the current contract in a physical building of this
  -- project, and a live row of one of that building's own folders, never
  -- Workshop Materials and never a folder linked as a whole.
  for v_link in select value from jsonb_array_elements(p_links) loop
    begin
      v_scope := (v_link ->> 'project_scope_id')::uuid;
      v_row := (v_link ->> 'boq_row_id')::uuid;
    exception when others then
      raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
    end;
    v_item := nullif(btrim(coalesce(v_link ->> 'item_key', '')), '');
    if v_scope is null or v_row is null or v_item is null
      or not exists (
        select 1 from public.v1_project_scopes s
        where s.id = v_scope and s.project_id = p_project_id and s.scope_kind = 'building')
      or not exists (
        select 1
        from public.v1_accounts_baseline_stage_items si
        join public.v1_accounts_baseline_stage_allocations sa
          on sa.baseline_revision_id = si.baseline_revision_id
         and sa.stage_key = si.stage_key
         and sa.measurement_mode = 'items'
        where si.baseline_revision_id = v_baseline and si.project_scope_id = v_scope
          and si.item_key = v_item)
      or not exists (
        select 1
        from public.v1_boq_rows r
        join public.v1_boq_groups g on g.id = r.group_id
        left join public.v1_boq_group_templates t on t.id = g.template_id
        where r.id = v_row and not r.is_archived
          and g.project_id = p_project_id and g.scope_id = v_scope
          and not g.is_archived and coalesce(t.template_key, '') <> 'workshop_materials')
      or exists (
        select 1
        from public.v1_boq_rows r
        join public.v1_accounts_material_boq_links fl on fl.boq_group_id = r.group_id
        where r.id = v_row) then
      raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
    end if;
  end loop;

  -- One row per line and building, one line per row.
  if exists (
      select 1 from jsonb_array_elements(p_links) l
      group by l ->> 'boq_row_id' having count(*) > 1)
    or exists (
      select 1 from jsonb_array_elements(p_links) l
      group by l ->> 'project_scope_id', btrim(l ->> 'item_key') having count(*) > 1) then
    raise exception 'R39_ACCOUNTS_INVALID_MATERIAL_LINK' using errcode = '22023';
  end if;

  delete from public.v1_accounts_material_boq_row_links where project_id = p_project_id;
  insert into public.v1_accounts_material_boq_row_links(
    project_id, project_scope_id, item_key, boq_row_id,
    created_by_auth_user_id, created_by_exact_role)
  select p_project_id, (l ->> 'project_scope_id')::uuid, btrim(l ->> 'item_key'),
    (l ->> 'boq_row_id')::uuid, auth.uid(), v_exact
  from jsonb_array_elements(p_links) l;

  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'item_key', item_key, 'boq_row_id', boq_row_id)
      order by project_scope_id, item_key, boq_row_id), '[]'::jsonb)
  into v_after
  from public.v1_accounts_material_boq_row_links where project_id = p_project_id;

  perform public.v1_write_audit_event('accounts.material_row_links.saved',
    'accounts_material_links', p_project_id, p_project_id,
    jsonb_build_object('row_links', v_before), jsonb_build_object('row_links', v_after),
    btrim(p_reason), p_idempotency_key);

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'link_count', jsonb_array_length(v_after));
  perform public.v1_complete_idempotency(
    'v1_save_accounts_material_row_links', p_idempotency_key, v_response);
  return v_response;
end;
$$;

-- ---------------------------------------------------------------------------
-- 20261107160000's read, with tied rows: their folders are not offered for a
-- folder link, the ties are listed, and deliveries come from the helper above.
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_accounts_material_sources(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_folders jsonb;
  v_links jsonb;
  v_row_links jsonb;
  v_delivered jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');

  -- A physical building's own folders, never Workshop Materials, archived, or
  -- a folder holding a row tied to a contract line.
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
      and not exists (
        select 1
        from public.v1_accounts_material_boq_row_links rl
        join public.v1_boq_rows tied on tied.id = rl.boq_row_id and not tied.is_archived
        where tied.group_id = g.id)
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

  select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', rl.project_scope_id,
      'item_key', rl.item_key,
      'boq_row_id', rl.boq_row_id,
      'boq_group_id', r.group_id
    ) order by rl.project_scope_id, rl.item_key), '[]'::jsonb)
  into v_row_links
  from public.v1_accounts_material_boq_row_links rl
  join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived
  join public.v1_boq_groups g on g.id = r.group_id and not g.is_archived
  where rl.project_id = p_project_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', d.project_scope_id,
      'stage_key', d.stage_key,
      'item_key', d.item_key,
      'basis', d.basis,
      'delivered_qty', d.delivered_qty::text,
      'deliveries', d.deliveries,
      'last_delivery_reference', d.last_delivery_reference,
      'last_delivery_date', d.last_delivery_date
    ) order by d.project_scope_id, d.stage_key, d.item_key), '[]'::jsonb)
  into v_delivered
  from public.v1_accounts_material_delivered(p_project_id) d;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', p_project_id,
    'can_link', public.v1_current_user_has_capability('configure_project_commercials', p_project_id),
    'folders', v_folders,
    'links', v_links,
    'row_links', v_row_links,
    'delivered', v_delivered
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 20261107160000's folder-link command, refusing a folder that holds a row
-- tied to a contract line (its deliveries already count through the tie).
-- ---------------------------------------------------------------------------
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
  -- project, and one of that building's own folders, not Workshop Materials,
  -- not archived and not holding a row tied to a contract line.
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
          and not g.is_archived and coalesce(t.template_key, '') <> 'workshop_materials')
      or exists (
        select 1
        from public.v1_accounts_material_boq_row_links rl
        join public.v1_boq_rows tied on tied.id = rl.boq_row_id and not tied.is_archived
        where tied.group_id = v_group) then
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

revoke all on function public.v1_get_accounts_material_register(uuid) from public, anon;
revoke all on function public.v1_get_boq_contract_status(uuid) from public, anon;
revoke all on function public.v1_save_accounts_material_row_links(uuid, jsonb, text, uuid) from public, anon;
revoke all on function public.v1_get_accounts_material_sources(uuid) from public, anon;
revoke all on function public.v1_save_accounts_material_boq_links(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.v1_get_accounts_material_register(uuid) to authenticated;
grant execute on function public.v1_get_boq_contract_status(uuid) to authenticated;
grant execute on function public.v1_save_accounts_material_row_links(uuid, jsonb, text, uuid) to authenticated;
grant execute on function public.v1_get_accounts_material_sources(uuid) to authenticated;
grant execute on function public.v1_save_accounts_material_boq_links(uuid, jsonb, text, uuid) to authenticated;


-- Self-check.
do $check$
begin
  if to_regclass('public.v1_accounts_material_boq_row_links') is null
    or to_regprocedure('public.v1_accounts_contract_line_facts(uuid)') is null
    or to_regprocedure('public.v1_accounts_material_delivered(uuid)') is null
    or has_table_privilege('authenticated',
      'public.v1_accounts_material_boq_row_links', 'select')
    or has_function_privilege('authenticated',
      'public.v1_accounts_contract_line_facts(uuid)', 'execute')
    or has_function_privilege('authenticated',
      'public.v1_accounts_material_delivered(uuid)', 'execute')
    or not has_function_privilege('authenticated',
      'public.v1_get_accounts_material_register(uuid)', 'execute')
    or not has_function_privilege('authenticated',
      'public.v1_get_boq_contract_status(uuid)', 'execute')
    or not has_function_privilege('authenticated',
      'public.v1_save_accounts_material_row_links(uuid,jsonb,text,uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_get_accounts_material_register(uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_get_boq_contract_status(uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_save_accounts_material_row_links(uuid,jsonb,text,uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_get_accounts_material_sources(uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_save_accounts_material_boq_links(uuid,jsonb,text,uuid)', 'execute')
    or position('v1_accounts_material_delivered' in pg_get_functiondef(
      'public.v1_get_accounts_material_sources(uuid)'::regprocedure)) = 0
    or position('v1_accounts_material_boq_row_links' in pg_get_functiondef(
      'public.v1_save_accounts_material_boq_links(uuid,jsonb,text,uuid)'::regprocedure)) = 0 then
    raise exception 'contract materials bundle self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';

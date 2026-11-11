-- R39 Accounts Workspace V2 — the invoice's per-building breakdown, as the
-- signed workbook prints it (project engineer review of YRA-322, 9 Nov 2026)
--
-- The invoice's third page listed only the five billing stages per building.
-- The workbook prints, per building, the Material sheet ("Delivered material
-- summary") and the Installation sheet: every item with its total quantity,
-- unit, weight (% of contract) and contract amount, then quantity, % and amount
-- till the previous month, this month and to date.
--
-- v1_accounts_invoice_item_breakdown builds those rows for a claim: the claim's
-- baseline items and values, and the confirmed quantities as they stood when
-- the previous invoiced claim was checked and when this claim was checked (the
-- same progress history the claim workbench reads). Where a stage's billed
-- money differs from its items' value (work billed before a contract
-- correction), the difference is returned as an adjustment so each stage
-- still adds up to what the invoice bills.
--
-- The document builder now stores those rows on each building
-- ("item_stages"). Invoices issued before this keep their frozen snapshot;
-- v1_get_client_invoice_document adds the rows to such a snapshot when it is
-- read (computed from append-only history, so they are stable), without
-- writing to it.
--
-- Additive: one read helper and CREATE OR REPLACE of two functions (a copy of
-- 20261108100000_accounts_v2_excel_rounding_and_dates.sql and
-- 20261105113000_accounts_v2_p3_invoice_issue.sql with the item rows). No
-- table or row changes; access is unchanged.
-- Rollback: re-apply those two functions; the helper may then be dropped.

create or replace function public.v1_accounts_invoice_item_breakdown(
  p_project_id uuid,
  p_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_this_at timestamptz;
  v_before_at timestamptz;
  v_out jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id;
  if not found then return '{}'::jsonb; end if;

  -- This claim's progress is what was confirmed when it was checked (a draft:
  -- now). Before it: when the latest earlier invoiced claim was checked.
  v_this_at := coalesce(
    case when v_claim.status = 'draft' then null else v_claim.ready_for_accounts_at end,
    clock_timestamp());
  select max(c.ready_for_accounts_at) into v_before_at
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id
    and c.id <> p_claim_id
    and c.id is distinct from v_claim.supersedes_claim_id
    and c.status = 'invoiced'
    and (c.created_at, c.id) < (v_claim.created_at, v_claim.id);

  with prior as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    join public.v1_accounts_client_claims c on c.id = l.claim_id
    where c.project_id = p_project_id
      and c.id <> p_claim_id
      and c.id is distinct from v_claim.supersedes_claim_id
      and c.status = 'invoiced'
      and (c.created_at, c.id) < (v_claim.created_at, v_claim.id)
    group by l.project_scope_id, l.stage_key
  ), this_claim as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ), items as (
    select si.project_scope_id, si.stage_key, si.item_key, si.item_label,
      si.display_order, si.quantity, si.unit_code, si.weight_percent_of_contract as w,
      public.v1_accounts_stage_item_value(si.id)::numeric as value,
      least(si.quantity, case when v_before_at is null then 0
        else public.v1_accounts_item_qty_at(p_project_id, si.project_scope_id,
          si.stage_key, si.item_key, v_before_at) end) as prev_qty,
      least(si.quantity, public.v1_accounts_item_qty_at(p_project_id,
        si.project_scope_id, si.stage_key, si.item_key, v_this_at)) as to_date_qty
    from public.v1_accounts_baseline_stage_items si
    where si.baseline_revision_id = v_claim.baseline_revision_id
  ), rows as (
    select i.*,
      greatest(i.to_date_qty - i.prev_qty, 0) as this_qty,
      i.value * i.prev_qty / i.quantity as prev_amt,
      i.value * greatest(i.to_date_qty - i.prev_qty, 0) / i.quantity as this_amt
    from items i
  ), stages as (
    select r.project_scope_id, r.stage_key, sa.stage_name, sa.display_order,
      public.v1_accounts_stage_value(bp.id)::numeric as stage_value,
      sum(r.w) as w,
      sum(r.prev_amt) as items_prev, sum(r.this_amt) as items_this,
      coalesce(max(pr.amount), 0) as cell_prev,
      coalesce(max(tc.amount), 0) as cell_this,
      jsonb_agg(jsonb_build_object(
        'item_key', r.item_key,
        'item_label', r.item_label,
        'display_order', r.display_order,
        'quantity', r.quantity::text,
        'unit_code', r.unit_code,
        'weight_percent', r.w::text,
        'contract_amount', r.value::text,
        'previous_qty', r.prev_qty::text,
        'previous_percent', round(r.w * r.prev_qty / r.quantity, 4)::text,
        'previous_amount', round(r.prev_amt, 2)::text,
        'this_qty', r.this_qty::text,
        'this_percent', round(r.w * r.this_qty / r.quantity, 4)::text,
        'this_amount', round(r.this_amt, 2)::text,
        'total_qty', (r.prev_qty + r.this_qty)::text,
        'total_percent', round(r.w * (r.prev_qty + r.this_qty) / r.quantity, 4)::text,
        'total_amount', round(r.prev_amt + r.this_amt, 2)::text
      ) order by r.display_order) as item_rows
    from rows r
    join public.v1_accounts_billing_progress bp
      on bp.baseline_revision_id = v_claim.baseline_revision_id
      and bp.project_scope_id = r.project_scope_id and bp.stage_key = r.stage_key
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = v_claim.baseline_revision_id
      and sa.stage_key = r.stage_key
    left join prior pr
      on pr.project_scope_id = r.project_scope_id and pr.stage_key = r.stage_key
    left join this_claim tc
      on tc.project_scope_id = r.project_scope_id and tc.stage_key = r.stage_key
    group by r.project_scope_id, r.stage_key, sa.stage_name, sa.display_order, bp.id
  )
  select coalesce(jsonb_object_agg(b.project_scope_id::text, b.stages), '{}'::jsonb)
  into v_out
  from (
    select s.project_scope_id, jsonb_agg(jsonb_build_object(
        'stage_key', s.stage_key,
        'stage_label', s.stage_name,
        'contract_amount', round(s.stage_value, 2)::text,
        'weight_percent', s.w::text,
        'items', s.item_rows,
        -- Billed money not explained by the items at this baseline's values
        -- (work billed before a contract correction). Zero normally.
        'adjustment_previous_amount', round(s.cell_prev - s.items_prev, 2)::text,
        'adjustment_this_amount', round(s.cell_this - s.items_this, 2)::text,
        'previous_amount', round(s.cell_prev, 2)::text,
        'this_amount', round(s.cell_this, 2)::text,
        'total_amount', round(s.cell_prev + s.cell_this, 2)::text
      ) order by s.display_order) as stages
    from stages s
    group by s.project_scope_id
  ) b;
  return v_out;
end;
$$;

revoke all on function public.v1_accounts_invoice_item_breakdown(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.v1_accounts_build_invoice_document(
  p_project_id uuid,
  p_claim_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_due_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_invoice public.v1_accounts_client_invoices%rowtype;
  v_rate numeric;
  v_this_exact numeric;
  v_prev_exact numeric;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_total numeric(20,2);
  v_prev_ex numeric(20,2); v_prev_vat numeric(20,2); v_prev_total numeric(20,2);
  v_cum_ex numeric(20,2); v_cum_vat numeric(20,2); v_cum_total numeric(20,2);
  v_con_ex numeric(20,2); v_con_vat numeric(20,2); v_con_total numeric(20,2);
  v_lines jsonb;
  v_company jsonb;
  v_override jsonb;
  v_bill_to jsonb;
  v_summary_stages jsonb;
  v_buildings jsonb;
  v_items jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  v_rate := coalesce(v_baseline.vat_rate_percent, 0);

  -- Once the claim is invoiced, the invoice's frozen amounts are the document's.
  select * into v_invoice from public.v1_accounts_client_invoices i
  where i.claim_id = p_claim_id and i.status <> 'cancelled'
  order by i.created_at desc limit 1;

  v_this_exact := public.v1_accounts_claim_exact_gross(p_claim_id);
  if v_invoice.id is not null then
    v_ex_vat := v_invoice.claimed_ex_vat;
    v_vat := v_invoice.vat_amount_snapshot;
    v_total := v_invoice.total_incl_vat_snapshot;
  else
    select x.ex_vat, x.vat, x.total into v_ex_vat, v_vat, v_total
    from public.v1_accounts_excel_amounts(v_this_exact, v_rate) x;
  end if;

  -- Till previous: every claim invoiced before this one, on every building and
  -- stage. A revision's predecessor is the same claim, so it is not previous.
  select coalesce(sum(coalesce(l.claimed_amount_exact, l.claimed_amount)), 0)
  into v_prev_exact
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id
    and c.id <> p_claim_id
    and c.id is distinct from v_claim.supersedes_claim_id
    and c.status = 'invoiced'
    and (c.created_at, c.id) < (v_claim.created_at, v_claim.id);

  select x.ex_vat, x.vat, x.total into v_prev_ex, v_prev_vat, v_prev_total
  from public.v1_accounts_excel_amounts(v_prev_exact, v_rate) x;
  select x.ex_vat, x.vat, x.total into v_cum_ex, v_cum_vat, v_cum_total
  from public.v1_accounts_excel_amounts(v_prev_exact + v_this_exact, v_rate) x;
  select x.ex_vat, x.vat, x.total into v_con_ex, v_con_vat, v_con_total
  from public.v1_accounts_excel_amounts(v_baseline.contract_value, v_rate) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'building_scope_id', line.project_scope_id,
      'building_name', scope.name,
      'stage_key', line.stage_key,
      'stage_label', stage.stage_name,
      'amount', line.amount::text
    ) order by stage.display_order, scope.name), '[]'::jsonb) into v_lines
  from (
    select l.project_scope_id, l.stage_key, sum(l.claimed_amount) as amount
    from public.v1_accounts_client_claim_lines l where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ) line
  join public.v1_project_scopes scope on scope.id = line.project_scope_id
  left join public.v1_accounts_baseline_stage_allocations stage
    on stage.baseline_revision_id = v_claim.baseline_revision_id and stage.stage_key = line.stage_key;

  -- Full building x stage grid for the claim's baseline: contract value, till
  -- previous (all earlier invoiced claims) and this invoice, per cell.
  -- Amounts stay exact through the grid and are rounded once at each level
  -- (cell, stage, building), as the workbook does.
  with prior as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    join public.v1_accounts_client_claims c on c.id = l.claim_id
    where c.project_id = p_project_id
      and c.id <> p_claim_id
      and c.id is distinct from v_claim.supersedes_claim_id
      and c.status = 'invoiced'
      and (c.created_at, c.id) < (v_claim.created_at, v_claim.id)
    group by l.project_scope_id, l.stage_key
  ), this_claim as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ), grid as (
    select
      bp.project_scope_id,
      scope.name as building_name,
      ba.allocation_percent as building_pct,
      bp.stage_key,
      sa.stage_name,
      sa.display_order,
      sa.allocation_percent as stage_pct,
      public.v1_accounts_stage_value(bp.id)::numeric(20,2) as stage_value,
      coalesce(pr.amount, 0) as prev_amt,
      coalesce(tc.amount, 0) as this_amt
    from public.v1_accounts_billing_progress bp
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    join public.v1_accounts_baseline_building_allocations ba
      on ba.baseline_revision_id = bp.baseline_revision_id
      and ba.project_scope_id = bp.project_scope_id
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id
      and sa.stage_key = bp.stage_key
    left join prior pr
      on pr.project_scope_id = bp.project_scope_id and pr.stage_key = bp.stage_key
    left join this_claim tc
      on tc.project_scope_id = bp.project_scope_id and tc.stage_key = bp.stage_key
    where bp.baseline_revision_id = v_claim.baseline_revision_id
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'stage_key', s.stage_key,
          'stage_label', s.stage_name,
          'contract_percent', s.stage_pct::text,
          'contract_amount', s.cval::text,
          'previous_amount', round(s.prev, 2)::text,
          'this_amount', round(s.this, 2)::text,
          'total_amount', round(s.prev + s.this, 2)::text
        ) order by s.display_order), '[]'::jsonb)
      from (
        select g.stage_key, g.stage_name, g.display_order, g.stage_pct,
          sum(g.stage_value) as cval, sum(g.prev_amt) as prev, sum(g.this_amt) as this
        from grid g
        group by g.stage_key, g.stage_name, g.display_order, g.stage_pct
      ) s
    ),
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'building_scope_id', b.project_scope_id,
          'name', b.building_name,
          'share_percent', b.building_pct::text,
          'building_value', b.bval::text,
          'previous_amount', round(b.prev, 2)::text,
          'this_amount', round(b.this, 2)::text,
          'total_amount', round(b.prev + b.this, 2)::text,
          'stages', b.stages
        ) order by b.building_name), '[]'::jsonb)
      from (
        select g.project_scope_id, g.building_name, g.building_pct,
          sum(g.stage_value) as bval, sum(g.prev_amt) as prev, sum(g.this_amt) as this,
          jsonb_agg(jsonb_build_object(
            'stage_key', g.stage_key,
            'stage_label', g.stage_name,
            'stage_value', g.stage_value::text,
            'previous_amount', round(g.prev_amt, 2)::text,
            'this_amount', round(g.this_amt, 2)::text,
            'total_amount', round(g.prev_amt + g.this_amt, 2)::text
          ) order by g.display_order) as stages
        from grid g
        group by g.project_scope_id, g.building_name, g.building_pct
      ) b
    )
  into v_summary_stages, v_buildings;

  -- Per building, the item rows of every items-mode stage (the workbook's
  -- Material and Installation sheets).
  v_items := public.v1_accounts_invoice_item_breakdown(p_project_id, p_claim_id);
  select coalesce(jsonb_agg(b.value || jsonb_build_object('item_stages',
      coalesce(v_items -> (b.value ->> 'building_scope_id'), '[]'::jsonb))
      order by b.ordinality), '[]'::jsonb)
  into v_buildings
  from jsonb_array_elements(coalesce(v_buildings, '[]'::jsonb)) with ordinality b;

  -- Who is billed: the chosen party, else the main contractor, else the client.
  -- A chosen party that no longer exists (project parties are replaced when a
  -- project is edited) falls back the same way.
  select jsonb_build_object('party_id', pp.id, 'kind', pp.party_kind,
      'name', pp.party_name, 'address', pp.address)
  into v_bill_to
  from public.v1_project_parties pp
  where pp.project_id = p_project_id
    and (pp.id = v_settings.bill_to_party_id
      or pp.party_kind in ('main_contractor', 'client'))
  order by (pp.id = v_settings.bill_to_party_id) desc nulls last,
    (pp.party_kind = 'main_contractor') desc, pp.party_order
  limit 1;

  -- Published company letterhead/bank block, frozen with the invoice. A
  -- historical import may set the letterhead/bank the paper copy carried.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';
  begin
    v_override := nullif(current_setting('yorks.invoice_company_override', true), '')::jsonb;
  exception when others then
    v_override := null;
  end;
  if jsonb_typeof(v_override) = 'object' then
    v_company := v_company || v_override;
  end if;

  return jsonb_build_object(
    'schema_version', 3,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref,
      'name', v_project.name, 'contract_reference', v_project.job_contract_reference),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'bill_to', v_bill_to,
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', coalesce(v_profile.contract_number, v_project.job_contract_reference)),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_rate::text, 'vat', v_vat::text,
      'total_incl_vat', v_total::text),
    'contract_value', v_baseline.contract_value::text,
    'summary', jsonb_build_object(
      'contract_total', v_baseline.contract_value::text,
      'previous_total', v_prev_ex::text,
      'this_total', v_ex_vat::text,
      'total_total', v_cum_ex::text,
      'contract_vat', v_con_vat::text,
      'contract_grand', v_con_total::text,
      'previous_vat', v_prev_vat::text,
      'previous_grand', v_prev_total::text,
      'this_vat', v_vat::text,
      'this_grand', v_total::text,
      'total_vat', v_cum_vat::text,
      'total_grand', v_cum_total::text,
      'stages', coalesce(v_summary_stages, '[]'::jsonb)
    ),
    'buildings', coalesce(v_buildings, '[]'::jsonb),
    'lines', v_lines
  );
end;
$function$;

-- An invoice issued before the item rows were stored gets them when it is
-- read. The stored snapshot and its hash are unchanged.
create or replace function public.v1_get_client_invoice_document(p_project_id uuid, p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_doc public.v1_accounts_client_invoice_documents%rowtype;
  v_snapshot jsonb;
  v_claim_id uuid;
  v_items jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  select * into v_doc from public.v1_accounts_client_invoice_documents where invoice_id = p_invoice_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_DOCUMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  v_snapshot := v_doc.document_snapshot;
  if jsonb_typeof(v_snapshot -> 'buildings') = 'array'
    and not exists (
      select 1 from jsonb_array_elements(v_snapshot -> 'buildings') b
      where b ? 'item_stages'
    ) then
    select claim_id into v_claim_id from public.v1_accounts_client_invoices
    where id = p_invoice_id and project_id = p_project_id;
    v_items := public.v1_accounts_invoice_item_breakdown(p_project_id, v_claim_id);
    select coalesce(jsonb_agg(b.value || jsonb_build_object('item_stages',
        coalesce(v_items -> (b.value ->> 'building_scope_id'), '[]'::jsonb))
        order by b.ordinality), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(v_snapshot -> 'buildings') with ordinality b;
    v_snapshot := jsonb_set(v_snapshot, '{buildings}', v_items);
  end if;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id, 'invoice_id', p_invoice_id,
    'snapshot_sha256', v_doc.snapshot_sha256, 'controlled_document_id', v_doc.controlled_document_id,
    'document', v_snapshot);
end;
$$;

grant execute on function public.v1_get_client_invoice_document(uuid, uuid) to authenticated;
revoke all on function public.v1_accounts_build_invoice_document(uuid, uuid, text, date, date, date)
  from public, anon, authenticated;

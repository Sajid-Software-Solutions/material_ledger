-- R39 Accounts Workspace V2 — P7 (part b): invoice document summary pages
--
-- The tax-invoice PDF so far rendered only the stage-level invoice page. Yorks'
-- real invoice (and the approved prototype) also carry a Main Summary matrix
-- (per stage: contract / till-previous / this-month / total completion) and a
-- per-building breakdown. All of it is derivable from what the claim already
-- snapshots per building x stage (stage_value_snapshot, previously_claimed and
-- claimed), so this re-creates v1_accounts_build_invoice_document to add two
-- additive blocks — `summary` and `buildings` — without touching the existing
-- keys or the frozen amounts. Every figure uses the same round-each-cell model
-- as the invoice total (D4 / Option A), so the per-building lines sum exactly to
-- the printed gross.
--
-- Additive, accounts-only, read-only shape change (a wider document snapshot).

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
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_prev_total numeric(20,2);
  v_lines jsonb;
  v_company jsonb;
  v_summary_stages jsonb;
  v_buildings jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;

  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2) into v_ex_vat
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;
  v_vat := round(v_ex_vat * v_baseline.vat_rate_percent / 100, 2);
  select coalesce(sum(line.previously_claimed_amount_snapshot), 0)::numeric(20,2)
  into v_prev_total
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;

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

  -- Full building x stage grid for the claim's baseline (every cell, including
  -- the ones not claimed this invoice), with the claim's previous/this amounts
  -- left-joined in. Cell value uses the engine's stage-value distribution.
  with grid as (
    select
      bp.project_scope_id,
      scope.name as building_name,
      ba.allocation_percent as building_pct,
      bp.stage_key,
      sa.stage_name,
      sa.display_order,
      sa.allocation_percent as stage_pct,
      public.v1_accounts_stage_value(bp.id)::numeric(20,2) as stage_value,
      coalesce(cl.previously_claimed_amount_snapshot, 0)::numeric(20,2) as prev_amt,
      coalesce(cl.claimed_amount, 0)::numeric(20,2) as this_amt
    from public.v1_accounts_billing_progress bp
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    join public.v1_accounts_baseline_building_allocations ba
      on ba.baseline_revision_id = bp.baseline_revision_id
      and ba.project_scope_id = bp.project_scope_id
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id
      and sa.stage_key = bp.stage_key
    left join public.v1_accounts_client_claim_lines cl
      on cl.claim_id = p_claim_id
      and cl.project_scope_id = bp.project_scope_id
      and cl.stage_key = bp.stage_key
    where bp.baseline_revision_id = v_claim.baseline_revision_id
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'stage_key', s.stage_key,
          'stage_label', s.stage_name,
          'contract_percent', s.stage_pct::text,
          'contract_amount', s.cval::text,
          'previous_amount', s.prev::text,
          'this_amount', s.this::text,
          'total_amount', (s.prev + s.this)::text
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
          'previous_amount', b.prev::text,
          'this_amount', b.this::text,
          'total_amount', (b.prev + b.this)::text,
          'stages', b.stages
        ) order by b.building_name), '[]'::jsonb)
      from (
        select g.project_scope_id, g.building_name, g.building_pct,
          sum(g.stage_value) as bval, sum(g.prev_amt) as prev, sum(g.this_amt) as this,
          jsonb_agg(jsonb_build_object(
            'stage_key', g.stage_key,
            'stage_label', g.stage_name,
            'stage_value', g.stage_value::text,
            'previous_amount', g.prev_amt::text,
            'this_amount', g.this_amt::text,
            'total_amount', (g.prev_amt + g.this_amt)::text
          ) order by g.display_order) as stages
        from grid g
        group by g.project_scope_id, g.building_name, g.building_pct
      ) b
    )
  into v_summary_stages, v_buildings;

  -- Frozen published company letterhead/bank block.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';

  return jsonb_build_object(
    'schema_version', 2,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref, 'name', v_project.name),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text, 'vat', v_vat::text,
      'total_incl_vat', (v_ex_vat + v_vat)::text),
    'contract_value', v_baseline.contract_value::text,
    'summary', jsonb_build_object(
      'contract_total', v_baseline.contract_value::text,
      'previous_total', v_prev_total::text,
      'this_total', v_ex_vat::text,
      'total_total', (v_prev_total + v_ex_vat)::text,
      'stages', coalesce(v_summary_stages, '[]'::jsonb)
    ),
    'buildings', coalesce(v_buildings, '[]'::jsonb),
    'lines', v_lines
  );
end;
$$;

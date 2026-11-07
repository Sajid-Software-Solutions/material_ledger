-- R39 Accounts Workspace V2 — the claim workbench keeps claim money to people
-- who may see commercial values
--
-- v1_get_claim_workbench returned the claim snapshot to everyone who may read
-- the workbench. The snapshot carries the claim total (claimed_ex_vat) and each
-- line's stage value, eligible, previously claimed and claimed amounts, so a Site
-- Engineer (view_project_accounts without view_project_commercial_values) saw
-- them. Those keys are now removed for that reader; the percent and the claim's
-- reference, period and status stay, as on the cells.
--
-- Additions for the Progress & Claims tab:
--   * who prepared and who checked the claim (safe display names, everyone);
--   * the live invoice the claim produced (reference, status, submission date;
--     commercial only);
--   * per cell, the progress done before the claim and in it (percent; for item
--     stages, per item quantity), so the tab can show "Done before" and "This
--     claim". Progress before a claim is what was confirmed when the claim
--     before it was checked, read from the progress history of the same
--     building and stage, so it carries across contract revisions. No money;
--   * per cell, the money claimed before the claim and in it (commercial only).
--
-- And for the Invoices & Payments tracker, four keys on v1_list_client_invoices
-- (a copy of 20261106200000_accounts_v2_p6_retention_payable.sql): the latest
-- certification date, the last receipt date that was not reversed, the
-- reference of the invoice a revision replaces, and whether a revision is being
-- prepared. Its access check and money are unchanged.
--
-- And for the Contract tab, the project's job/contract reference and site on
-- v1_get_project_commercial_setup (a copy of
-- 20261106180000_accounts_v2_p6_retention.sql), so a contract can start from
-- what was entered when the project was created. Project details only; no
-- money and no change to who may read it.
--
-- This is a copy of the body in
-- 20261107113000_accounts_v2_p3_workbench_suggestions.sql with those changes.
-- Additive: two internal read helpers and CREATE OR REPLACE of one read. No
-- table or row changes.
-- Rollback: re-apply the three functions from those migrations; the helpers are
-- unused by anything else and may be dropped.

-- Confirmed percent of one building and stage as it stood at a moment, across
-- baseline revisions. Zero before anything was confirmed.
create or replace function public.v1_accounts_dimension_percent_at(
  p_project_id uuid, p_project_scope_id uuid, p_stage_key text, p_at timestamptz
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.new_confirmed_percent
    from public.v1_accounts_billing_progress_revisions r
    join public.v1_accounts_billing_progress bp on bp.id = r.progress_entry_id
    where bp.project_id = p_project_id
      and bp.project_scope_id = p_project_scope_id
      and bp.stage_key = p_stage_key
      and r.new_confirmed_percent is not null
      and r.occurred_at <= p_at
    order by r.occurred_at desc, r.revision_number desc
    limit 1), 0);
$$;

-- Confirmed quantity of one item (by its key) of one building and stage as it
-- stood at a moment, across baseline revisions.
create or replace function public.v1_accounts_item_qty_at(
  p_project_id uuid, p_project_scope_id uuid, p_stage_key text, p_item_key text,
  p_at timestamptz
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.new_confirmed_qty
    from public.v1_accounts_billing_item_progress_revisions r
    join public.v1_accounts_billing_item_progress ip on ip.id = r.item_progress_id
    where ip.project_id = p_project_id
      and ip.project_scope_id = p_project_scope_id
      and ip.stage_key = p_stage_key
      and ip.item_key = p_item_key
      and r.new_confirmed_qty is not null
      and r.occurred_at <= p_at
    order by r.occurred_at desc, r.revision_number desc
    limit 1), 0);
$$;

revoke all on function public.v1_accounts_dimension_percent_at(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.v1_accounts_item_qty_at(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;

create or replace function public.v1_get_claim_workbench(
  p_project_id uuid,
  p_claim_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_values boolean;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_cells jsonb := '[]'::jsonb;
  v_claim jsonb := null;
  v_claim_id uuid;
  v_claim_gross numeric := 0;
  v_claim_vat numeric := 0;
  v_claim_retention numeric := 0;
  -- The claim the tab is looking at, and the two moments its progress split
  -- is read at: when the claim before it was checked (v_before_at, null when
  -- none was), and the claim's own check (v_this_at, null = as confirmed now).
  v_ctx_status text;
  v_ctx_created timestamptz;
  v_before_at timestamptz;
  v_this_at timestamptz;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if not found or v_profile.current_baseline_revision_id is null then
    return jsonb_build_object(
      'schema_version', 1, 'project_id', p_project_id,
      'baseline_revision_id', null, 'cells', '[]'::jsonb, 'claim', null,
      'capabilities', public.v1_accounts_capability_envelope(p_project_id),
      'commands', public.v1_accounts_receivables_commands(p_project_id)
    );
  end if;
  select * into v_baseline
  from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;

  select id into v_claim_id
  from public.v1_accounts_client_claims
  where project_id = p_project_id
    and (
      (p_claim_id is not null and id = p_claim_id)
      or (p_claim_id is null and status in ('draft', 'ready_for_accounts'))
    )
  order by (status = 'draft') desc, updated_at desc
  limit 1;

  if v_claim_id is not null then
    select status, created_at,
        case when status = 'draft' then null else ready_for_accounts_at end
      into v_ctx_status, v_ctx_created, v_this_at
    from public.v1_accounts_client_claims where id = v_claim_id;
    select max(c.ready_for_accounts_at) into v_before_at
    from public.v1_accounts_client_claims c
    where c.project_id = p_project_id and c.id <> v_claim_id
      and c.status in ('ready_for_accounts', 'invoiced')
      and (c.created_at, c.id) < (v_ctx_created, v_claim_id);
  else
    select max(c.ready_for_accounts_at) into v_before_at
    from public.v1_accounts_client_claims c
    where c.project_id = p_project_id and c.status in ('ready_for_accounts', 'invoiced');
  end if;

  select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_cells
  from (
    select sa.display_order as ord, scope.name as bname,
      jsonb_build_object(
        'progress_entry_id', bp.id,
        'building_scope_id', bp.project_scope_id,
        'building_name', scope.name,
        'stage_key', bp.stage_key,
        'stage_label', sa.stage_name,
        'stage_position', sa.display_order,
        'measurement_mode', sa.measurement_mode,
        'confirmed_percent', bp.confirmed_percent::text,
        'review_status', bp.review_status,
        'record_version', bp.record_version
      )
      -- Progress before this claim and in it. A checked or invoiced claim holds
      -- nothing for a building and stage it has no line for.
      || jsonb_build_object(
        'percent_before_claim', pct.before_pct::text,
        'percent_this_claim', case
          when v_ctx_status in ('ready_for_accounts', 'invoiced') and not pct.has_line then '0'
          else greatest(pct.at_pct - pct.before_pct, 0)::text end)
      -- A site suggestion still ahead of what is confirmed. No money in it.
      || case when bp.suggested_percent > bp.confirmed_percent then jsonb_build_object(
          'suggested_percent', bp.suggested_percent::text,
          'suggested_evidence_document_ids',
            coalesce(to_jsonb(bp.suggested_evidence_document_ids), '[]'::jsonb),
          'suggested_by', (
            select public.v1_safe_profile_display_name(p.display_name, p.auth_user_id)
            from public.v1_profiles p where p.auth_user_id = bp.suggested_by_auth_user_id)
        ) else '{}'::jsonb end
      || case when v_can_values then jsonb_build_object(
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'eligible', public.v1_accounts_progress_eligible_amount(bp.id)::text,
          'claimed', public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null)::text,
          'available', greatest(
            public.v1_accounts_progress_eligible_amount(bp.id)
              - public.v1_accounts_dimension_claimed_amount(
                  bp.project_id, bp.project_scope_id, bp.stage_key, null), 0)::text,
          'over_claimed', public.v1_accounts_dimension_claimed_amount(
              bp.project_id, bp.project_scope_id, bp.stage_key, null)
            > public.v1_accounts_progress_eligible_amount(bp.id),
          -- Money on this building and stage in claims made before this one,
          -- and in this one.
          'claimed_before_claim', case when v_claim_id is null
            then public.v1_accounts_dimension_claimed_amount(
              bp.project_id, bp.project_scope_id, bp.stage_key, null)
            else coalesce((
              select sum(line.claimed_amount)
              from public.v1_accounts_client_claim_lines line
              join public.v1_accounts_client_claims c on c.id = line.claim_id
              where line.project_id = bp.project_id
                and line.project_scope_id = bp.project_scope_id
                and line.stage_key = bp.stage_key
                and c.status not in ('cancelled', 'superseded')
                and c.id <> v_claim_id
                and (c.created_at, c.id) < (v_ctx_created, v_claim_id)), 0)
            end::numeric(20,2)::text,
          'this_claim_amount', coalesce((
            select sum(line.claimed_amount)
            from public.v1_accounts_client_claim_lines line
            where line.claim_id = v_claim_id
              and line.project_scope_id = bp.project_scope_id
              and line.stage_key = bp.stage_key), 0)::numeric(20,2)::text
        ) else '{}'::jsonb end
      || case when sa.measurement_mode = 'items' then jsonb_build_object('items', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'stage_item_id', si.id, 'item_key', si.item_key,
              'item_label', si.item_label, 'display_order', si.display_order,
              'quantity', si.quantity::text, 'unit_code', si.unit_code,
              'confirmed_qty', coalesce(ip.confirmed_qty, 0)::text,
              'needs_review', coalesce(ip.needs_review, false),
              'qty_before_claim', iq.before_qty::text,
              'qty_this_claim', case
                when v_ctx_status in ('ready_for_accounts', 'invoiced') and not pct.has_line then '0'
                else greatest(iq.at_qty - iq.before_qty, 0)::text end
            )
            || case when v_can_values then jsonb_build_object(
                'item_value', public.v1_accounts_stage_item_value(si.id)::text)
              else '{}'::jsonb end
            order by si.display_order), '[]'::jsonb)
          from public.v1_accounts_baseline_stage_items si
          left join public.v1_accounts_billing_item_progress ip
            on ip.stage_item_id = si.id and ip.progress_entry_id = bp.id
          cross join lateral (select
              case when v_before_at is null then 0 else public.v1_accounts_item_qty_at(
                bp.project_id, bp.project_scope_id, bp.stage_key, si.item_key, v_before_at) end
                as before_qty,
              case when v_this_at is null then coalesce(ip.confirmed_qty, 0)
                else public.v1_accounts_item_qty_at(
                  bp.project_id, bp.project_scope_id, bp.stage_key, si.item_key, v_this_at) end
                as at_qty) iq
          where si.baseline_revision_id = v_baseline.id
            and si.project_scope_id = bp.project_scope_id
            and si.stage_key = bp.stage_key
        )) else '{}'::jsonb end
      as cell
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    cross join lateral (select
        case when v_before_at is null then 0 else public.v1_accounts_dimension_percent_at(
          bp.project_id, bp.project_scope_id, bp.stage_key, v_before_at) end as before_pct,
        case when v_this_at is null then bp.confirmed_percent
          else public.v1_accounts_dimension_percent_at(
            bp.project_id, bp.project_scope_id, bp.stage_key, v_this_at) end as at_pct,
        exists (select 1 from public.v1_accounts_client_claim_lines line
          where line.claim_id = v_claim_id
            and line.project_scope_id = bp.project_scope_id
            and line.stage_key = bp.stage_key) as has_line) pct
    where bp.baseline_revision_id = v_baseline.id
  ) rows;

  if v_claim_id is not null then
    v_claim := public.v1_accounts_claim_snapshot(v_claim_id)
      -- Who prepared and who checked it, by safe display name. No money.
      || jsonb_build_object(
        'prepared_by', (
          select public.v1_safe_profile_display_name(p.display_name, p.auth_user_id)
          from public.v1_accounts_client_claims c
          join public.v1_profiles p on p.auth_user_id = c.created_by_auth_user_id
          where c.id = v_claim_id),
        'checked_by', (
          select public.v1_safe_profile_display_name(p.display_name, p.auth_user_id)
          from public.v1_accounts_client_claims c
          join public.v1_profiles p on p.auth_user_id = c.ready_for_accounts_by_auth_user_id
          where c.id = v_claim_id));
    -- The snapshot carries the claim total and each line's money. Someone who
    -- may read the workbench but not commercial values gets neither.
    if not v_can_values then
      v_claim := (v_claim - 'claimed_ex_vat') || jsonb_build_object('lines', coalesce((
        select jsonb_agg(line
          - 'stage_value_snapshot' - 'eligible_amount_snapshot'
          - 'previously_claimed_amount_snapshot' - 'claimed_amount')
        from jsonb_array_elements(v_claim->'lines') line), '[]'::jsonb));
    end if;
    -- Payable figures: gross (ex VAT) + VAT at the baseline rate = net payable
    -- (incl VAT), plus this claim's share of the contract. Commercial only.
    if v_can_values then
      v_claim_gross := coalesce((select sum(claimed_amount)
        from public.v1_accounts_client_claim_lines where claim_id = v_claim_id), 0);
      v_claim_vat := round(v_claim_gross * coalesce(v_baseline.vat_rate_percent, 0) / 100, 2);
      -- §28 R-1 preview: retention the profile would currently withhold on this
      -- claim's gross ex-VAT, and the net payable once it is held back.
      v_claim_retention := round(
        v_claim_gross * coalesce(v_profile.retention_percent, 0) / 100, 2);
      v_claim := v_claim || jsonb_build_object(
        'vat_amount', v_claim_vat::text,
        'net_payable', (v_claim_gross + v_claim_vat)::text,
        'contract_value', v_baseline.contract_value::text,
        'this_claim_percent', case when v_baseline.contract_value > 0
          then round(v_claim_gross / v_baseline.contract_value * 100, 1)
          else 0 end::text,
        'retention_percent', coalesce(v_profile.retention_percent, 0)::text,
        'retention_preview', v_claim_retention::text,
        'net_payable_after_retention',
          (v_claim_gross + v_claim_vat - v_claim_retention)::text,
        -- The live invoice this claim produced, if any.
        'invoice', (
          select jsonb_build_object('invoice_id', i.id,
            'invoice_reference', i.invoice_reference, 'status', i.status,
            'submission_date', i.submission_date)
          from public.v1_accounts_client_invoices i
          where i.claim_id = v_claim_id and i.status <> 'cancelled'
          order by i.revision_number desc nulls last, i.created_at desc
          limit 1));
    end if;
  end if;

  return jsonb_build_object(
    'schema_version', 1, 'project_id', p_project_id,
    'baseline_revision_id', v_baseline.id,
    'baseline_revision_number', v_baseline.revision_number,
    'cells', v_cells, 'claim', v_claim,
    'capabilities', public.v1_accounts_capability_envelope(p_project_id),
    'commands', public.v1_accounts_receivables_commands(p_project_id)
  );
end;
$$;

create or replace function public.v1_list_client_invoices(
  p_project_id uuid,p_status text default null,p_due_state text default null,
  p_before_updated_at timestamptz default null,p_before_id uuid default null,p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_rows jsonb;v_next_time timestamptz;v_next_id uuid;v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  perform public.v1_accounts_require_capability(p_project_id,'manage_client_invoices');
  if p_status is not null and p_status not in ('draft','submitted','under_certification','partially_certified','certified','partially_paid','paid','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVALID_INVOICE_STATUS' using errcode='22023';end if;
  if p_due_state is not null and p_due_state not in ('on_track','due_soon','due_today','overdue') then raise exception 'R39_ACCOUNTS_INVALID_DUE_STATE' using errcode='22023';end if;
  with derived as (select invoice.*,public.v1_accounts_invoice_certified_ex_vat(invoice.id) certified_ex,
      public.v1_accounts_invoice_certified_incl_vat(invoice.id) certified_total,public.v1_accounts_invoice_paid_amount(invoice.id) paid,
      public.v1_accounts_invoice_pdc_exposure(invoice.id) exposure,
      public.v1_accounts_invoice_due_state(invoice.status,invoice.due_date,invoice.reminder_lead_days_snapshot) due_state
    from public.v1_accounts_client_invoices invoice where invoice.project_id=p_project_id),
  page as (select * from derived where (p_status is null or status=p_status) and (p_due_state is null or due_state=p_due_state)
    and (p_before_updated_at is null or (updated_at,id)<(p_before_updated_at,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by updated_at desc,id desc limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object('invoice_id',id,'claim_id',claim_id,'invoice_reference',invoice_reference,'status',status,
    'claimed_ex_vat',claimed_ex_vat::text,'certified_ex_vat',certified_ex::text,'total_incl_vat',total_incl_vat_snapshot::text,
    'retention_snapshot',retention_snapshot::text,
    'amount_paid_till_date',paid::text,'still_due',greatest(certified_total-retention_snapshot-paid,0)::text,'pdc_exposure',exposure::text,
    'submission_date',submission_date,'due_date',due_date,'due_state',due_state,'record_version',record_version,'updated_at',updated_at,
    -- For the tracker: when it was last certified and last paid, which invoice a
    -- revision replaces, and whether a revision is being prepared.
    'certification_date',(select c.certification_date from public.v1_accounts_client_certifications c
      where c.invoice_id=page.id order by c.revision_number desc limit 1),
    'last_receipt_date',(select max(p.payment_date) from public.v1_accounts_client_payments p
      where p.invoice_id=page.id and p.entry_kind='receipt'
        and not exists(select 1 from public.v1_accounts_client_payments r
          where r.original_payment_id=p.id and r.entry_kind='reversal')),
    'replaces_reference',(select prior.invoice_reference from public.v1_accounts_client_invoices prior
      where prior.id=page.supersedes_invoice_id),
    'revision_in_progress',status<>'cancelled' and exists(select 1 from public.v1_accounts_client_claims successor
      where successor.supersedes_claim_id=page.claim_id and successor.status in ('draft','ready_for_accounts')))
    order by updated_at desc,id desc),'[]'::jsonb),min(updated_at),(array_agg(id order by updated_at asc,id asc))[1]
  into v_rows,v_next_time,v_next_id from page;
  return jsonb_build_object('schema_version',3,'project_id',p_project_id,'invoices',v_rows,
    'next_cursor',case when jsonb_array_length(v_rows)=v_limit then jsonb_build_object('before_updated_at',v_next_time,'before_id',v_next_id) else null end,
    'capabilities',public.v1_accounts_receivables_capabilities(p_project_id),
    'commands',public.v1_accounts_receivables_commands(p_project_id));
end;
$$;

create or replace function public.v1_get_project_commercial_setup(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_configure boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_contract numeric(20,2) := 0;
  v_buildings jsonb := '[]'::jsonb;
  v_stages jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id);
  if not v_can_view then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id);
  v_can_configure := public.v1_current_user_has_capability(
    'configure_project_commercials', p_project_id);

  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
    where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    -- From project creation, so the Contract tab can start from them.
    'job_contract_reference', v_project.job_contract_reference,
    'project_site', v_project.project_site,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'configure_project_commercials', v_can_configure),
    'can_configure', v_can_configure);

  if not v_can_values then
    return v_result;
  end if;

  select * into v_settings
  from public.v1_accounts_project_invoice_settings
  where project_id = p_project_id;

  if v_baseline.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', b.project_scope_id,
        'name', s.name,
        'scope_kind', s.scope_kind,
        'allocation_percent', b.allocation_percent::text,
        'value', round(v_contract * b.allocation_percent / 100, 2)::text
      ) order by s.scope_kind, s.name), '[]'::jsonb)
      into v_buildings
    from public.v1_accounts_baseline_building_allocations b
    join public.v1_project_scopes s on s.id = b.project_scope_id
    where b.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'stage_key', st.stage_key,
        'stage_name', st.stage_name,
        'display_order', st.display_order,
        'measurement_mode', st.measurement_mode,
        'allocation_percent', st.allocation_percent::text,
        'value', round(v_contract * st.allocation_percent / 100, 2)::text
      ) order by st.display_order), '[]'::jsonb)
      into v_stages
    from public.v1_accounts_baseline_stage_allocations st
    where st.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', it.project_scope_id,
        'building_name', s.name,
        'stage_key', it.stage_key,
        'item_key', it.item_key,
        'item_label', it.item_label,
        'display_order', it.display_order,
        'quantity', it.quantity::text,
        'unit_code', it.unit_code,
        'weight_percent_of_contract', it.weight_percent_of_contract::text,
        'value', public.v1_accounts_stage_item_value(it.id)::text
      ) order by s.name, it.stage_key, it.display_order), '[]'::jsonb)
      into v_items
    from public.v1_accounts_baseline_stage_items it
    join public.v1_project_scopes s on s.id = it.project_scope_id
    where it.baseline_revision_id = v_baseline.id;

    v_result := v_result || jsonb_build_object(
      'profile_version', v_profile.record_version,
      'revision_number', v_baseline.revision_number,
      'currency_code', v_baseline.currency_code,
      'contract_value', v_contract::text,
      'contract_incl_vat',
        round(v_contract * (1 + v_baseline.vat_rate_percent / 100), 2)::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text,
      'payment_terms_days', v_baseline.payment_terms_days,
      'reminder_lead_days', v_baseline.reminder_lead_days,
      'buildings', v_buildings,
      'stages', v_stages,
      'items', v_items);
  else
    v_result := v_result || jsonb_build_object(
      'profile_version',
        case when v_profile.project_id is not null
          then v_profile.record_version else null end,
      'currency_code', null,
      'buildings', '[]'::jsonb,
      'stages', '[]'::jsonb,
      'items', '[]'::jsonb);
  end if;

  if v_settings.project_id is not null then
    v_result := v_result || jsonb_build_object(
      'invoice_settings', jsonb_build_object(
        'invoice_prefix', v_settings.invoice_prefix,
        'next_sequence', v_settings.next_sequence,
        'scope_line', v_settings.scope_line,
        'attention_name', v_settings.attention_name,
        'bill_to_party_id', v_settings.bill_to_party_id,
        'record_version', v_settings.record_version));
  else
    v_result := v_result || jsonb_build_object('invoice_settings', null);
  end if;

  v_result := v_result || jsonb_build_object(
    'parties', coalesce((
      select jsonb_object_agg(party_kind, party)
      from (
        select distinct on (party_kind) party_kind,
          jsonb_build_object(
            'name', party_name,
            'address', address,
            'contact_name', contact_name,
            'contact_phone', contact_phone,
            'contact_email', contact_email) as party
        from public.v1_project_parties
        where project_id = p_project_id
          and party_kind in ('client', 'main_contractor')
        order by party_kind, party_order
      ) p
    ), '{}'::jsonb));

  v_result := v_result || jsonb_build_object(
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', v_profile.contract_number,
      'retention_percent',
        case when v_profile.retention_percent is null then null
          else v_profile.retention_percent::text end));

  return v_result;
end;
$$;

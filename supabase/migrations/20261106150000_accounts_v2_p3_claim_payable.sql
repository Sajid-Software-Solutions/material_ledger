-- R39 Accounts Workspace V2 — P3 (part c): claim payable figures
--
-- The prototype claim side panel shows Gross / VAT / Net payable and the claim's
-- share of the contract. The workbench's claim object (from
-- v1_accounts_claim_snapshot) carries only the ex-VAT gross, and the client
-- cannot derive VAT or net (exact decimal arithmetic is server-side only). This
-- CREATE OR REPLACE of v1_get_claim_workbench merges server-computed
-- vat_amount, net_payable (incl VAT), contract_value and this_claim_percent into
-- the claim object.
--
-- Additive and accounts-only. The merged figures are monetary, so they are added
-- only with view_project_commercial_values (AT-SEC-001/008); the claim object is
-- otherwise unchanged, and every other key the prior version returned is
-- returned unchanged. No table, row or status change. VAT uses the baseline's
-- own vat_rate_percent and rounds once to fils.

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
            > public.v1_accounts_progress_eligible_amount(bp.id)
        ) else '{}'::jsonb end
      || case when sa.measurement_mode = 'items' then jsonb_build_object('items', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'stage_item_id', si.id, 'item_key', si.item_key,
              'item_label', si.item_label, 'display_order', si.display_order,
              'quantity', si.quantity::text, 'unit_code', si.unit_code,
              'confirmed_qty', coalesce(ip.confirmed_qty, 0)::text,
              'needs_review', coalesce(ip.needs_review, false)
            )
            || case when v_can_values then jsonb_build_object(
                'item_value', public.v1_accounts_stage_item_value(si.id)::text)
              else '{}'::jsonb end
            order by si.display_order), '[]'::jsonb)
          from public.v1_accounts_baseline_stage_items si
          left join public.v1_accounts_billing_item_progress ip
            on ip.stage_item_id = si.id and ip.progress_entry_id = bp.id
          where si.baseline_revision_id = v_baseline.id
            and si.project_scope_id = bp.project_scope_id
            and si.stage_key = bp.stage_key
        )) else '{}'::jsonb end
      as cell
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    where bp.baseline_revision_id = v_baseline.id
  ) rows;

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
    v_claim := public.v1_accounts_claim_snapshot(v_claim_id);
    -- Payable figures: gross (ex VAT) + VAT at the baseline rate = net payable
    -- (incl VAT), plus this claim's share of the contract. Commercial only.
    if v_can_values then
      v_claim_gross := coalesce((select sum(claimed_amount)
        from public.v1_accounts_client_claim_lines where claim_id = v_claim_id), 0);
      v_claim_vat := round(v_claim_gross * coalesce(v_baseline.vat_rate_percent, 0) / 100, 2);
      v_claim := v_claim || jsonb_build_object(
        'vat_amount', v_claim_vat::text,
        'net_payable', (v_claim_gross + v_claim_vat)::text,
        'contract_value', v_baseline.contract_value::text,
        'this_claim_percent', case when v_baseline.contract_value > 0
          then round(v_claim_gross / v_baseline.contract_value * 100, 1)
          else 0 end::text);
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

grant execute on function public.v1_get_claim_workbench(uuid, uuid) to authenticated;

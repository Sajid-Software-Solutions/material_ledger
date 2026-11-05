-- R39 Accounts Workspace V2 — P4 (part b): Summary workspace projection
--
-- v1_get_project_accounts_workspace is the one call behind the V2 Summary tab:
-- the 4-step strip, the ex-VAT money-flow bar, KPIs, a server-derived attention
-- list, the building x stage invoiced heatmap, and the cash position. Monetary
-- keys are omitted (not zeroed) without view_project_commercial_values; supplier
-- and cash keys need view_supplier_costs (AT-SEC-001/008). It reuses the same
-- invoice/supplier filters as v1_get_project_accounts_overview, so the retired
-- (cancelled) superseded predecessors drop out automatically.
--
-- Additive, accounts-only, read-only. The advisory site-record suggestions
-- (6.8) ship with their mapping UI in P8. See
-- R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 6.7.

create or replace function public.v1_get_project_accounts_workspace(
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
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_contract numeric(20,2) := 0;
  v_vatf numeric := 1;
  v_invoiced numeric := 0;
  v_received numeric := 0;
  v_certified numeric := 0;
  v_pdc numeric := 0;
  v_still_due numeric := 0;
  v_draft numeric := 0;
  v_bills_total numeric := 0;
  v_bills_paid numeric := 0;
  v_bills_open numeric := 0;
  v_bills_overdue integer := 0;
  v_open_claim_id uuid;
  v_open_claim_gross numeric := 0;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
    v_vatf := 1 + coalesce(v_baseline.vat_rate_percent, 0) / 100;
    v_progress_any := exists (select 1 from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline.id and confirmed_percent > 0);
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  select c.id, coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status = 'draft'
  order by c.updated_at desc limit 1;

  if v_can_supplier then
    select coalesce(sum(case when b.status <> 'cancelled' then b.total_incl_vat else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then public.v1_accounts_supplier_paid_amount(b.id) else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then greatest(b.total_incl_vat - public.v1_accounts_supplier_paid_amount(b.id), 0) else 0 end), 0),
           count(*) filter (where b.status <> 'cancelled' and b.due_date < current_date
             and public.v1_accounts_supplier_paid_amount(b.id) < b.total_incl_vat)
      into v_bills_total, v_bills_paid, v_bills_open, v_bills_overdue
    from public.v1_accounts_supplier_bills b where b.project_id = p_project_id;
  end if;

  v_paid_ex := round(least(v_received / v_vatf, v_invoiced), 2);

  -- Heatmap: invoiced % per current building x stage cell.
  if v_can_view and v_can_values and v_baseline.id is not null then
    select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_heatmap from (
      select sa.display_order as ord, scope.name as bname,
        jsonb_build_object('building_scope_id', bp.project_scope_id, 'building_name', scope.name,
          'stage_key', bp.stage_key, 'stage_label', sa.stage_name,
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'invoiced_amount', inv.amount::text,
          'invoiced_percent', case when public.v1_accounts_stage_value(bp.id) > 0
            then round(inv.amount / public.v1_accounts_stage_value(bp.id) * 100, 1) else 0 end::text) as cell
      from public.v1_accounts_billing_progress bp
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
      join public.v1_project_scopes scope on scope.id = bp.project_scope_id
      left join lateral (
        select coalesce(sum(l.claimed_amount), 0) as amount
        from public.v1_accounts_client_claim_lines l
        join public.v1_accounts_client_claims c on c.id = l.claim_id
        where c.project_id = p_project_id and c.status = 'invoiced'
          and l.project_scope_id = bp.project_scope_id and l.stage_key = bp.stage_key
      ) inv on true
      where bp.baseline_revision_id = v_baseline.id
    ) cells;
  end if;

  -- Attention (server-derived).
  if v_baseline.id is null then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object(
      'severity', 'bad', 'kind', 'setup_incomplete', 'action_key', 'open_contract',
      'target_type', 'project', 'target_id', p_project_id));
  elsif v_can_values then
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'bad', 'kind', 'invoice_overdue', 'action_key', 'open_invoice',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id
        and i.status not in ('draft','returned','cancelled','paid') and i.due_date < current_date), '[]'::jsonb);
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'pri', 'kind', 'awaiting_certification', 'action_key', 'certify',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id and i.status = 'submitted'
        and not exists (select 1 from public.v1_accounts_client_certifications c where c.invoice_id = i.id)), '[]'::jsonb);
    if v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_contract > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_pdc > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','cheques_in_hand',
        'action_key','open_invoices','target_type','project','target_id',p_project_id));
    end if;
  end if;
  if v_can_supplier and v_bills_overdue > 0 then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','warn','kind','supplier_overdue',
      'action_key','open_supplier_bills','target_type','project','target_id',p_project_id,
      'params', jsonb_build_object('count', v_bills_overdue)));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', jsonb_build_array(
      jsonb_build_object('key','setup', 'state', case when v_baseline.id is not null then 'done' else 'current' end),
      jsonb_build_object('key','progress', 'state', case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end),
      jsonb_build_object('key','invoice', 'state', case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end),
      jsonb_build_object('key','paid', 'state', case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end)),
    'attention', v_attention);

  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'money_flow', jsonb_build_object(
        'paid', v_paid_ex::text,
        'invoiced_waiting', greatest(v_invoiced - v_paid_ex, 0)::text,
        'done_not_invoiced', v_draft::text,
        'remaining', greatest(v_contract - v_invoiced - v_draft, 0)::text),
      'kpis', jsonb_build_object(
        'contract_value', v_contract::text,
        'contract_incl_vat', round(v_contract * v_vatf, 2)::text,
        'invoiced', v_invoiced::text,
        'received', v_received::text,
        'certified', v_certified::text,
        'outstanding', v_still_due::text,
        'cheques_in_hand', v_pdc::text,
        'done_not_invoiced', v_draft::text),
      'heatmap', v_heatmap);
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', jsonb_build_object('billed', v_bills_total::text, 'paid', v_bills_paid::text,
        'unpaid', v_bills_open::text, 'overdue_count', v_bills_overdue),
      'cash', jsonb_build_object('received', v_received::text, 'paid_to_suppliers', v_bills_paid::text,
        'net', (v_received - v_bills_paid)::text));
  end if;
  return v_result;
end;
$$;

revoke all on function public.v1_get_project_accounts_workspace(uuid) from public, anon;
grant execute on function public.v1_get_project_accounts_workspace(uuid) to authenticated, service_role;

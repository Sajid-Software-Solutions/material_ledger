-- R39 Accounts Workspace V2 — P3 (part 1): claim workbench read + reopen
--
-- The claim workbench is the Progress & claims screen's single round trip. This
-- part adds the read-only projection v1_get_claim_workbench (every building x
-- stage cell for the current baseline, with items, role-safe values, dimension
-- claimed and available, plus the current open draft claim) and the small
-- v1_reopen_client_claim command ("Back to draft"). The save command, invoice
-- issue/revise/snapshot and the superseded status arrive in P3 part 2.
--
-- Additive and accounts-only. Reuses the P1/P2 helpers (eligible, dimension
-- claimed, stage item value) and the existing receivables/progress capability
-- envelopes. See docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md
-- sections 8.5 and 8.6.

-- ---------------------------------------------------------------------------
-- Read: one round trip for the workbench. Monetary keys are omitted (not
-- zeroed) without view_project_commercial_values (AT-SEC-001/008).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- "Back to draft": ready_for_accounts -> draft while no invoice exists. Mirrors
-- v1_submit_client_claim_to_accounts in reverse.
-- ---------------------------------------------------------------------------
create or replace function public.v1_reopen_client_claim(
  p_project_id uuid,
  p_claim_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_payload jsonb; v_existing jsonb; v_before jsonb; v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'prepare_client_claim');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_reopen_client_claim', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_claim.status <> 'ready_for_accounts' then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_REOPENABLE' using errcode = '55000'; end if;
  if exists (
    select 1 from public.v1_accounts_client_invoices i
    where i.claim_id = p_claim_id and i.status <> 'cancelled'
  ) then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_REOPENABLE' using errcode = '55000'; end if;
  if v_claim.created_by_auth_user_id <> auth.uid()
    and public.v1_permission_exact_role(auth.uid()) <> 'admin' then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  if v_claim.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  v_before := public.v1_accounts_claim_snapshot(p_claim_id);
  update public.v1_accounts_client_claims
  set status = 'draft', record_version = record_version + 1,
    ready_for_accounts_at = null, ready_for_accounts_by_auth_user_id = null,
    updated_at = v_now
  where id = p_claim_id;
  perform public.v1_write_audit_event(
    'accounts.client_claim.reopened', 'accounts_client_claim', p_claim_id,
    p_project_id, v_before, public.v1_accounts_claim_snapshot(p_claim_id),
    btrim(p_reason), p_idempotency_key);
  v_response := jsonb_build_object('schema_version', 3, 'replayed', false,
    'project_id', p_project_id, 'entity_id', p_claim_id, 'claim_id', p_claim_id,
    'record_version', p_expected_version + 1, 'status', 'draft', 'updated_at', v_now);
  perform public.v1_complete_idempotency('v1_reopen_client_claim', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_reopen_client_claim(uuid, uuid, integer, text, uuid)
  to authenticated;

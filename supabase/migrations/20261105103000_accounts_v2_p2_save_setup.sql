-- R39 Accounts Workspace V2 — P2 (part 2): save-setup command with carry-forward
--
-- Fixes R1 ("editing the contract wipes progress"). v1_save_project_commercial_setup
-- is the V2 contract writer: it delegates the validated baseline/allocation/
-- materialize work to the existing, tested initialize/revise commands, then adds
-- the V2 layer those commands do not know about — per-stage measurement mode,
-- the stage-item catalogue, and carry-forward of confirmed/suggested progress and
-- item quantities by stable keys (building scope + stage_key [+ item_key]). A new
-- quantity below the confirmed quantity is capped and flagged needs_review, never
-- silently dropped; removed dimensions are reported.
--
-- The legacy v1_initialize/revise commands are unchanged (the V1 screens keep
-- using them). Additive and idempotent. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md section 8.3 and
-- PRODUCT_DECISIONS.md section 32 (D2). Change-detection (unchanged -> no
-- revision) and invoice settings are added in P3.

-- Allow carry-forward as a billing-progress revision action (superset; no row
-- changes).
alter table public.v1_accounts_billing_progress_revisions
  drop constraint if exists v1_accounts_billing_progress_revisions_action_check;
alter table public.v1_accounts_billing_progress_revisions
  add constraint v1_accounts_billing_progress_revisions_action_check
  check (action in ('suggested', 'confirmed', 'reviewed', 'carried_forward'));

create or replace function public.v1_save_project_commercial_setup(
  p_project_id uuid,
  p_expected_profile_version integer,
  p_setup jsonb,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text;
  v_actor_role text;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_has_profile boolean;
  v_buildings jsonb;
  v_stages jsonb;
  v_existing jsonb;
  v_derived_key uuid;
  v_base jsonb;
  v_new_baseline_id uuid;
  v_old_baseline_id uuid;
  v_old_revision integer;
  v_stage jsonb;
  v_scope uuid;
  v_need numeric;
  v_have numeric;
  v_carried integer := 0;
  v_needs_review integer := 0;
  v_removed jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  v_exact_role := public.v1_accounts_require_capability(
    p_project_id, 'configure_project_commercials'
  );
  v_actor_role := public.v1_current_role();
  if p_setup is null or jsonb_typeof(p_setup) <> 'object'
    or jsonb_typeof(p_setup -> 'buildings') <> 'array'
    or jsonb_typeof(p_setup -> 'stages') <> 'array' then
    raise exception 'R39_ACCOUNTS_SETUP_REQUIRED' using errcode = '22023';
  end if;

  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_project_commercial_setup', p_idempotency_key, p_setup
  );
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_baseline|' || p_project_id::text, 0)
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id for update;
  v_has_profile := found;

  -- Buildings and stages in the shape the delegated commands expect (no mode or
  -- items; those are the V2 layer applied afterward).
  v_buildings := p_setup -> 'buildings';
  v_stages := (
    select coalesce(jsonb_agg(jsonb_build_object(
      'stage_key', s ->> 'stage_key',
      'stage_label', s ->> 'stage_label',
      'allocation_percent', s ->> 'allocation_percent',
      'position', (s ->> 'position')::integer
    ) order by (s ->> 'position')::integer), '[]'::jsonb)
    from jsonb_array_elements(p_setup -> 'stages') s
  );

  -- Deterministic derived key so the delegated baseline command replays safely
  -- under its own idempotency namespace.
  v_derived_key := md5(p_idempotency_key::text || ':setup_baseline')::uuid;

  if not v_has_profile then
    v_base := public.v1_initialize_project_commercial_baseline(
      p_project_id, p_setup ->> 'contract_value', p_setup ->> 'currency_code',
      p_setup ->> 'vat_rate_percent',
      nullif(p_setup ->> 'payment_terms_days', '')::integer,
      nullif(p_setup ->> 'reminder_lead_days', '')::integer,
      v_buildings, v_stages,
      coalesce(p_setup -> 'management_review_policy', '{}'::jsonb),
      coalesce(nullif(btrim(p_note), ''), 'Commercial setup saved'),
      v_derived_key
    );
    v_old_baseline_id := null;
  else
    if p_expected_profile_version is null or p_expected_profile_version <= 0 then
      raise exception 'R39_ACCOUNTS_EXPECTED_VERSION_REQUIRED' using errcode = '22023';
    end if;
    v_old_baseline_id := v_profile.current_baseline_revision_id;
    select revision_number into v_old_revision
    from public.v1_accounts_baseline_revisions where id = v_old_baseline_id;
    v_base := public.v1_revise_project_commercial_baseline(
      p_project_id, p_expected_profile_version,
      p_setup ->> 'contract_value', p_setup ->> 'currency_code',
      p_setup ->> 'vat_rate_percent',
      nullif(p_setup ->> 'payment_terms_days', '')::integer,
      nullif(p_setup ->> 'reminder_lead_days', '')::integer,
      v_buildings, v_stages,
      coalesce(p_setup -> 'management_review_policy', '{}'::jsonb),
      coalesce(nullif(btrim(p_note), ''), 'Commercial setup revised'),
      v_derived_key
    );
  end if;
  v_new_baseline_id := (v_base ->> 'baseline_revision_id')::uuid;

  -- V2 layer: measurement mode + stage items for each items-mode stage, applied
  -- to every building scope (the "same items in all buildings" convenience).
  for v_stage in select value from jsonb_array_elements(p_setup -> 'stages') loop
    if coalesce(v_stage ->> 'measurement_mode', 'percent') = 'items' then
      update public.v1_accounts_baseline_stage_allocations
      set measurement_mode = 'items'
      where baseline_revision_id = v_new_baseline_id
        and stage_key = v_stage ->> 'stage_key';

      for v_scope in
        select project_scope_id from public.v1_accounts_baseline_building_allocations
        where baseline_revision_id = v_new_baseline_id
      loop
        insert into public.v1_accounts_baseline_stage_items(
          baseline_revision_id, project_id, project_scope_id, stage_key, item_key,
          item_label, display_order, quantity, unit_code, weight_percent_of_contract
        )
        select v_new_baseline_id, p_project_id, v_scope, v_stage ->> 'stage_key',
          it ->> 'item_key', it ->> 'item_label', (it ->> 'display_order')::integer,
          (it ->> 'quantity')::numeric, it ->> 'unit_code',
          (it ->> 'weight_percent_of_contract')::numeric
        from jsonb_array_elements(coalesce(v_stage -> 'items', '[]'::jsonb)) it;

        -- Items of a (scope, items-stage) must sum to building% x stage% / 100.
        select (building.allocation_percent * stage.allocation_percent / 100)
        into v_need
        from public.v1_accounts_baseline_building_allocations building
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.baseline_revision_id = v_new_baseline_id
          and stage.stage_key = v_stage ->> 'stage_key'
        where building.baseline_revision_id = v_new_baseline_id
          and building.project_scope_id = v_scope;
        select coalesce(sum(weight_percent_of_contract), 0) into v_have
        from public.v1_accounts_baseline_stage_items
        where baseline_revision_id = v_new_baseline_id
          and project_scope_id = v_scope and stage_key = v_stage ->> 'stage_key';
        if abs(v_have - v_need) > 0.000005 then
          raise exception 'R39_ACCOUNTS_INVALID_STAGE_ITEMS'
            using errcode = '23514',
            detail = jsonb_build_object('stage_key', v_stage ->> 'stage_key',
              'scope', v_scope, 'needed', v_need::text, 'have', v_have::text)::text;
        end if;
      end loop;
    end if;
  end loop;

  -- Carry forward from the superseded revision (revise path only).
  if v_old_baseline_id is not null then
    -- Percent / confirmed progress by (scope, stage_key).
    update public.v1_accounts_billing_progress np set
      suggested_percent = op.suggested_percent,
      suggested_evidence_summary = op.suggested_evidence_summary,
      suggested_evidence_document_ids = op.suggested_evidence_document_ids,
      suggested_by_auth_user_id = op.suggested_by_auth_user_id,
      suggested_by_exact_role = op.suggested_by_exact_role,
      suggested_at = op.suggested_at,
      confirmed_percent = op.confirmed_percent,
      confirmed_evidence_summary = op.confirmed_evidence_summary,
      confirmed_evidence_document_ids = op.confirmed_evidence_document_ids,
      confirmed_by_auth_user_id = op.confirmed_by_auth_user_id,
      confirmed_by_exact_role = op.confirmed_by_exact_role,
      confirmed_at = op.confirmed_at,
      updated_at = clock_timestamp()
    from public.v1_accounts_billing_progress op
    where np.baseline_revision_id = v_new_baseline_id
      and op.baseline_revision_id = v_old_baseline_id
      and op.project_scope_id = np.project_scope_id
      and op.stage_key = np.stage_key
      and (op.confirmed_percent > 0 or op.suggested_percent > 0);

    insert into public.v1_accounts_billing_progress_revisions(
      project_id, progress_entry_id, baseline_revision_id, revision_number, action,
      previous_suggested_percent, new_suggested_percent,
      previous_confirmed_percent, new_confirmed_percent,
      previous_review_status, new_review_status,
      evidence_summary, evidence_document_ids, reason,
      actor_auth_user_id, actor_role, actor_exact_role, idempotency_key
    )
    select p_project_id, np.id, v_new_baseline_id, 1, 'carried_forward',
      0, np.suggested_percent, 0, np.confirmed_percent,
      'not_required', np.review_status,
      np.confirmed_evidence_summary, np.confirmed_evidence_document_ids,
      'Carried forward from revision ' || v_old_revision,
      v_actor, v_actor_role, v_exact_role, v_derived_key
    from public.v1_accounts_billing_progress np
    where np.baseline_revision_id = v_new_baseline_id
      and (np.confirmed_percent > 0 or np.suggested_percent > 0);
    get diagnostics v_carried = row_count;

    -- Item quantities by (scope, stage_key, item_key); cap below the new
    -- quantity and flag needs_review rather than dropping.
    insert into public.v1_accounts_billing_item_progress(
      project_id, baseline_revision_id, progress_entry_id, stage_item_id,
      project_scope_id, stage_key, item_key, suggested_qty, confirmed_qty,
      confirmed_evidence, needs_review
    )
    select p_project_id, v_new_baseline_id, np.id, ni.id,
      ni.project_scope_id, ni.stage_key, ni.item_key,
      least(oip.suggested_qty, ni.quantity), least(oip.confirmed_qty, ni.quantity),
      oip.confirmed_evidence, (oip.confirmed_qty > ni.quantity)
    from public.v1_accounts_baseline_stage_items ni
    join public.v1_accounts_billing_progress np
      on np.baseline_revision_id = v_new_baseline_id
      and np.project_scope_id = ni.project_scope_id and np.stage_key = ni.stage_key
    join public.v1_accounts_baseline_stage_items oi
      on oi.baseline_revision_id = v_old_baseline_id
      and oi.project_scope_id = ni.project_scope_id
      and oi.stage_key = ni.stage_key and oi.item_key = ni.item_key
    join public.v1_accounts_billing_item_progress oip on oip.stage_item_id = oi.id
    where ni.baseline_revision_id = v_new_baseline_id
      and (oip.confirmed_qty > 0 or oip.suggested_qty > 0);

    insert into public.v1_accounts_billing_item_progress_revisions(
      project_id, item_progress_id, baseline_revision_id, revision_number, action,
      previous_suggested_qty, new_suggested_qty,
      previous_confirmed_qty, new_confirmed_qty,
      evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key
    )
    select p_project_id, ip.id, v_new_baseline_id, 1, 'carried_forward',
      0, ip.suggested_qty, 0, ip.confirmed_qty, ip.confirmed_evidence,
      'Carried forward from revision ' || v_old_revision,
      v_actor, v_exact_role, v_derived_key
    from public.v1_accounts_billing_item_progress ip
    where ip.baseline_revision_id = v_new_baseline_id;

    select count(*) into v_needs_review
    from public.v1_accounts_billing_item_progress
    where baseline_revision_id = v_new_baseline_id and needs_review;

    select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', o.project_scope_id, 'stage_key', o.stage_key)), '[]'::jsonb)
    into v_removed
    from public.v1_accounts_billing_progress o
    where o.baseline_revision_id = v_old_baseline_id
      and not exists (
        select 1 from public.v1_accounts_billing_progress n
        where n.baseline_revision_id = v_new_baseline_id
          and n.project_scope_id = o.project_scope_id and n.stage_key = o.stage_key);
  end if;

  v_response := v_base || jsonb_build_object(
    'replayed', false,
    'carried_forward_progress_rows', v_carried,
    'items_needs_review', v_needs_review,
    'removed_dimensions', v_removed
  );
  perform public.v1_complete_idempotency(
    'v1_save_project_commercial_setup', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

grant execute on function public.v1_save_project_commercial_setup(uuid, integer, jsonb, text, uuid)
  to authenticated;

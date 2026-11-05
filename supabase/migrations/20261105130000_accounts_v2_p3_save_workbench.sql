-- R39 Accounts Workspace V2 — P3 (part 2c): save claim workbench
--
-- v1_save_claim_workbench is the Progress & claims screen's one-shot write: it
-- confirms the entered to-date progress (percent rows delegate to the existing
-- v1_confirm_billing_progress; item quantities are confirmed inline against the
-- P2 item-progress tables) and then rebuilds the single open draft claim with
-- claimed = available(dimension) for every current cell with something to claim.
-- The server never trusts client arithmetic: available comes from the P1/P2
-- helpers, and the cap is re-checked by the existing create-claim path.
--
-- v1 scope: requires prepare_client_claim + view_project_commercial_values +
-- confirm_billing_progress (the Project Engineer path), document evidence, and
-- rebuilds (delete + recreate) the single draft. Deferred: the Site-Engineer
-- "record as suggestion only" fallback, the typed receipt-review/DO/note
-- evidence kinds (D5), and a separate v1_rebuild_client_claim_draft (save is the
-- rebuild). Additive, accounts-only.

create or replace function public.v1_save_claim_workbench(
  p_project_id uuid,
  p_claim_reference text,
  p_period_start date,
  p_period_end date,
  p_entries jsonb,
  p_evidence_document_ids uuid[],
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact text;
  v_baseline uuid;
  v_entry jsonb;
  v_progress public.v1_accounts_billing_progress%rowtype;
  v_item public.v1_accounts_baseline_stage_items%rowtype;
  v_ip public.v1_accounts_billing_item_progress%rowtype;
  v_cell_progress uuid;
  v_new_qty numeric(18,4);
  v_evidence jsonb;
  v_rev integer;
  v_old_pct numeric(7,4);
  v_derived numeric(7,4);
  v_prog_rev integer;
  v_confirmed integer := 0;
  v_lines jsonb;
  v_claim jsonb := null;
  v_existing jsonb; v_payload jsonb; v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  v_exact := public.v1_accounts_require_capability(p_project_id, 'prepare_client_claim');
  if not public.v1_current_user_has_capability('view_project_commercial_values', p_project_id)
    or not public.v1_current_user_has_capability('confirm_billing_progress', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id,
    'claim_reference', nullif(btrim(coalesce(p_claim_reference, '')), ''),
    'period_start', p_period_start, 'period_end', p_period_end, 'entries', p_entries);
  v_existing := public.v1_idempotency_get_or_claim('v1_save_claim_workbench', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_claim_workbench|' || p_project_id::text, 0));

  select current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if v_baseline is null then raise exception 'R39_ACCOUNTS_BASELINE_NOT_FOUND' using errcode = 'P0002'; end if;

  v_evidence := (select coalesce(jsonb_agg(jsonb_build_object('kind', 'document', 'id', d)), '[]'::jsonb)
    from unnest(coalesce(p_evidence_document_ids, '{}'::uuid[])) d);

  for v_entry in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    if v_entry ? 'progress_entry_id' then
      select * into v_progress from public.v1_accounts_billing_progress
      where id = (v_entry ->> 'progress_entry_id')::uuid and project_id = p_project_id
        and baseline_revision_id = v_baseline;
      if not found then raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      if (v_entry ->> 'confirmed_percent_to_date')::numeric(7,4) <> v_progress.confirmed_percent then
        perform public.v1_confirm_billing_progress(
          p_project_id, v_progress.id, v_progress.record_version,
          v_entry ->> 'confirmed_percent_to_date', nullif(btrim(p_reason), ''),
          coalesce(p_evidence_document_ids, '{}'::uuid[]),
          coalesce(nullif(btrim(p_reason), ''), 'Workbench confirmation'),
          md5(p_idempotency_key::text || ':c:' || v_progress.id::text)::uuid);
        v_confirmed := v_confirmed + 1;
      end if;
    elsif v_entry ? 'stage_item_id' then
      select * into v_item from public.v1_accounts_baseline_stage_items
      where id = (v_entry ->> 'stage_item_id')::uuid and project_id = p_project_id
        and baseline_revision_id = v_baseline;
      if not found then raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      v_new_qty := (v_entry ->> 'confirmed_qty_to_date')::numeric(18,4);
      if v_new_qty < 0 or v_new_qty > v_item.quantity then
        raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      select id into v_cell_progress from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline and project_scope_id = v_item.project_scope_id
        and stage_key = v_item.stage_key;
      select * into v_ip from public.v1_accounts_billing_item_progress where stage_item_id = v_item.id;
      if not found then
        if v_new_qty > 0 and coalesce(array_length(p_evidence_document_ids, 1), 0) = 0 then
          raise exception 'R39_ACCOUNTS_EVIDENCE_REQUIRED' using errcode = '23514'; end if;
        insert into public.v1_accounts_billing_item_progress(
          project_id, baseline_revision_id, progress_entry_id, stage_item_id,
          project_scope_id, stage_key, item_key, confirmed_qty, confirmed_evidence)
        values (p_project_id, v_baseline, v_cell_progress, v_item.id, v_item.project_scope_id,
          v_item.stage_key, v_item.item_key, v_new_qty, v_evidence)
        returning * into v_ip;
        insert into public.v1_accounts_billing_item_progress_revisions(
          project_id, item_progress_id, baseline_revision_id, revision_number, action,
          previous_suggested_qty, new_suggested_qty, previous_confirmed_qty, new_confirmed_qty,
          evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key)
        values (p_project_id, v_ip.id, v_baseline, 1, 'confirmed', 0, 0, 0, v_new_qty,
          v_evidence, coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, v_exact, md5(p_idempotency_key::text || ':i:' || v_item.id::text)::uuid);
        v_confirmed := v_confirmed + 1;
      elsif v_new_qty <> v_ip.confirmed_qty then
        if v_new_qty > v_ip.confirmed_qty and coalesce(array_length(p_evidence_document_ids, 1), 0) = 0 then
          raise exception 'R39_ACCOUNTS_EVIDENCE_REQUIRED' using errcode = '23514'; end if;
        select coalesce(max(revision_number), 0) + 1 into v_rev
        from public.v1_accounts_billing_item_progress_revisions where item_progress_id = v_ip.id;
        insert into public.v1_accounts_billing_item_progress_revisions(
          project_id, item_progress_id, baseline_revision_id, revision_number, action,
          previous_suggested_qty, new_suggested_qty, previous_confirmed_qty, new_confirmed_qty,
          evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key)
        values (p_project_id, v_ip.id, v_baseline, v_rev, 'confirmed', 0, 0,
          v_ip.confirmed_qty, v_new_qty, v_evidence,
          coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, v_exact, md5(p_idempotency_key::text || ':i:' || v_item.id::text)::uuid);
        update public.v1_accounts_billing_item_progress
        set confirmed_qty = v_new_qty, confirmed_evidence = v_evidence,
          record_version = record_version + 1, updated_at = v_now
        where id = v_ip.id;
        v_confirmed := v_confirmed + 1;
      end if;
      -- Keep the items-mode cell's confirmed_percent as the derived display
      -- value (eligible / stage value) so existing readers and the claim
      -- validator (confirmed_percent > 0 plus a progress revision) see the
      -- confirmation. Append a confirmed progress revision when it changes.
      select confirmed_percent into v_old_pct
      from public.v1_accounts_billing_progress where id = v_cell_progress;
      v_derived := round(
        case when public.v1_accounts_stage_value(v_cell_progress) > 0
          then public.v1_accounts_progress_eligible_amount(v_cell_progress)
            / public.v1_accounts_stage_value(v_cell_progress) * 100
          else 0 end, 4);
      if v_derived <> v_old_pct then
        select coalesce(max(revision_number), 0) + 1 into v_prog_rev
        from public.v1_accounts_billing_progress_revisions where progress_entry_id = v_cell_progress;
        insert into public.v1_accounts_billing_progress_revisions(
          project_id, progress_entry_id, baseline_revision_id, revision_number, action,
          previous_suggested_percent, new_suggested_percent,
          previous_confirmed_percent, new_confirmed_percent,
          previous_review_status, new_review_status, evidence_summary,
          evidence_document_ids, reason, actor_auth_user_id, actor_role, actor_exact_role,
          idempotency_key)
        select p_project_id, v_cell_progress, v_baseline, v_prog_rev, 'confirmed',
          bp.suggested_percent, bp.suggested_percent, v_old_pct, v_derived,
          bp.review_status, bp.review_status, nullif(btrim(p_reason), ''),
          coalesce(p_evidence_document_ids, '{}'::uuid[]),
          coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, public.v1_current_role(), v_exact,
          md5(p_idempotency_key::text || ':ip:' || v_cell_progress::text || ':' || v_prog_rev::text)::uuid
        from public.v1_accounts_billing_progress bp where bp.id = v_cell_progress;
        update public.v1_accounts_billing_progress
        set confirmed_percent = v_derived, confirmed_by_auth_user_id = v_actor,
          confirmed_by_exact_role = v_exact, confirmed_at = v_now,
          record_version = record_version + 1, updated_at = v_now
        where id = v_cell_progress;
      end if;
    else
      raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023';
    end if;
  end loop;

  -- Rebuild the single open draft claim from current availability.
  delete from public.v1_accounts_client_claims where project_id = p_project_id and status = 'draft';

  select coalesce(jsonb_agg(jsonb_build_object(
      'progress_entry_id', line.id,
      'claimed_amount', line.avail::text,
      'evidence_reference', coalesce(nullif(btrim(p_reason), ''), 'Prepared from workbench'))), '[]'::jsonb)
  into v_lines
  from (
    select bp.id,
      greatest(public.v1_accounts_progress_eligible_amount(bp.id)
        - public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null), 0) as avail
    from public.v1_accounts_billing_progress bp
    where bp.baseline_revision_id = v_baseline
  ) line
  where line.avail > 0;

  if jsonb_array_length(v_lines) > 0 then
    v_claim := public.v1_create_client_claim_draft(
      p_project_id,
      coalesce(nullif(btrim(p_claim_reference), ''), 'WB-' || to_char(v_now, 'YYYYMMDDHH24MISS')),
      p_period_start, p_period_end, v_lines, nullif(btrim(p_reason), ''),
      md5(p_idempotency_key::text || ':claim')::uuid);
  end if;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'confirmed_rows', v_confirmed, 'claim', v_claim);
  perform public.v1_complete_idempotency('v1_save_claim_workbench', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_save_claim_workbench(uuid, text, date, date, jsonb, uuid[], text, uuid)
  to authenticated;

-- R39 Accounts — restore a cancelled client invoice or a deleted claim
--
-- Owner decision of 12 November 2026 (PRODUCT_DECISIONS.md section 36): a
-- person who cancels an invoice or deletes a claim by mistake can take it back,
-- as long as nothing has happened since that would make the old record wrong.
--
--   v1_restore_client_invoice  a manually cancelled invoice returns to the
--                              status it had (draft, submitted or under
--                              certification) with its own number, dates and
--                              amounts; its claim returns to invoiced.
--   v1_restore_client_claim    a deleted (cancelled) claim that never had an
--                              invoice returns to draft or checked.
--
-- A restore is refused when:
--   * the invoice was retired by a revision (it has a successor), or a revision
--     of it is open — the revision is the live record;
--   * the contract was revised after the record was made (its figures belong to
--     an older contract version);
--   * progress it claimed has since been claimed again (the normal claim cap,
--     checked exactly as when a claim is saved);
--   * for a claim, another claim is already open (one open claim at a time).
--
-- Nothing is deleted or rewritten: the cancellation stays in the audit trail
-- (before/after snapshots of the cancel and of the restore), invoice numbers are
-- unique across cancelled invoices, so the restored number cannot clash, and
-- every command re-checks capability, record version and state under row locks
-- with an idempotency key.
--
-- Additive and repeatable: two new functions and their grants. No table,
-- constraint or existing function changes.
-- Rollback: drop the two functions (restored records stay as they are; cancel
-- them again with the existing commands if needed).

create or replace function public.v1_accounts_restore_check_claim(
  p_project_id uuid,
  p_claim_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_current uuid;
  v_line public.v1_accounts_client_claim_lines%rowtype;
  v_eligible numeric;
  v_consumed numeric;
begin
  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id;
  select profile.current_baseline_revision_id into v_current
  from public.v1_accounts_project_commercial_profiles profile
  where profile.project_id = p_project_id;
  if v_current is distinct from v_claim.baseline_revision_id then
    raise exception 'R39_ACCOUNTS_RESTORE_CONTRACT_CHANGED' using errcode = '55000';
  end if;
  -- Revision links: a claim retired by a successor, or one whose revision is
  -- open, is not the live record.
  if exists (
    select 1 from public.v1_accounts_client_claims successor
    where successor.supersedes_claim_id = p_claim_id
      and successor.status <> 'cancelled'
  ) then
    raise exception 'R39_ACCOUNTS_RESTORE_SUPERSEDED' using errcode = '55000';
  end if;
  -- The claim cap, line by line, as v1_accounts_validate_claim_lines applies
  -- it when a claim is saved (this claim is cancelled, so it is not counted).
  for v_line in
    select * from public.v1_accounts_client_claim_lines
    where claim_id = p_claim_id
    order by id
  loop
    perform 1 from public.v1_accounts_billing_progress
    where id = v_line.progress_entry_id for update;
    v_eligible := public.v1_accounts_progress_eligible_amount(v_line.progress_entry_id);
    v_consumed := public.v1_accounts_dimension_claimed_amount(
      p_project_id, v_line.project_scope_id, v_line.stage_key, p_claim_id
    );
    if v_eligible is null
      or v_line.claimed_amount > greatest(v_eligible - v_consumed, 0) then
      raise exception 'R39_ACCOUNTS_CLAIM_CAP_EXCEEDED' using errcode = '23514';
    end if;
  end loop;
end;
$$;

create or replace function public.v1_restore_client_invoice(
  p_project_id uuid,
  p_invoice_id uuid,
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
  v_invoice public.v1_accounts_client_invoices%rowtype;
  v_claim public.v1_accounts_client_claims%rowtype;
  v_payload jsonb;
  v_existing jsonb;
  v_before jsonb;
  v_claim_before jsonb;
  v_response jsonb;
  v_target text;
  v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'invoice_id', p_invoice_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim('v1_restore_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  select * into v_invoice from public.v1_accounts_client_invoices
  where id = p_invoice_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001';
  end if;
  if v_invoice.status <> 'cancelled' then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_RESTORABLE' using errcode = '55000';
  end if;
  -- Retired by a revision: the successor is the live invoice.
  if exists (
    select 1 from public.v1_accounts_client_invoices successor
    where successor.supersedes_invoice_id = p_invoice_id
  ) then
    raise exception 'R39_ACCOUNTS_RESTORE_SUPERSEDED' using errcode = '55000';
  end if;
  select * into v_claim from public.v1_accounts_client_claims
  where id = v_invoice.claim_id and project_id = p_project_id for update;
  if not found or v_claim.status <> 'cancelled' or v_claim.ready_for_accounts_at is null then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_RESTORABLE' using errcode = '55000';
  end if;
  perform public.v1_accounts_restore_check_claim(p_project_id, v_claim.id);

  -- The status it had before the cancellation, from the cancellation's own
  -- audit snapshot; an invoice can only be cancelled from these three.
  select event.before_data ->> 'status' into v_target
  from public.v1_audit_events event
  where event.entity_type = 'accounts_client_invoice'
    and event.entity_id = p_invoice_id
    and event.event_type = 'accounts.client_invoice.cancelled'
  order by event.occurred_at desc
  limit 1;
  if v_target is null or v_target not in ('draft', 'submitted', 'under_certification') then
    v_target := case when v_invoice.submitted_at is null then 'draft' else 'submitted' end;
  end if;

  v_before := public.v1_accounts_invoice_snapshot(p_invoice_id);
  v_claim_before := public.v1_accounts_claim_snapshot(v_claim.id);
  update public.v1_accounts_client_invoices
  set status = v_target, cancelled_at = null, cancelled_by_auth_user_id = null,
    cancellation_reason = null, record_version = record_version + 1, updated_at = v_now
  where id = p_invoice_id;
  update public.v1_accounts_client_claims
  set status = 'invoiced', cancelled_at = null, cancelled_by_auth_user_id = null,
    cancellation_reason = null, record_version = record_version + 1, updated_at = v_now
  where id = v_claim.id;
  perform public.v1_write_audit_event('accounts.client_invoice.restored', 'accounts_client_invoice',
    p_invoice_id, p_project_id, v_before, public.v1_accounts_invoice_snapshot(p_invoice_id),
    btrim(p_reason), p_idempotency_key);
  perform public.v1_write_audit_event('accounts.client_claim.restored', 'accounts_client_claim',
    v_claim.id, p_project_id, v_claim_before, public.v1_accounts_claim_snapshot(v_claim.id),
    btrim(p_reason), p_idempotency_key);
  v_response := jsonb_build_object('schema_version', 3, 'replayed', false, 'project_id', p_project_id,
    'entity_id', p_invoice_id, 'invoice_id', p_invoice_id, 'claim_id', v_claim.id,
    'record_version', p_expected_version + 1, 'status', v_target, 'updated_at', v_now);
  perform public.v1_complete_idempotency('v1_restore_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

create or replace function public.v1_restore_client_claim(
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
  v_cap text;
  v_payload jsonb;
  v_existing jsonb;
  v_before jsonb;
  v_response jsonb;
  v_target text;
  v_now timestamptz := clock_timestamp();
begin
  -- The same capabilities that may delete a claim may restore it.
  if public.v1_current_user_has_capability('manage_client_invoices', p_project_id) then
    v_cap := 'manage_client_invoices';
  else
    v_cap := 'prepare_client_claim';
  end if;
  perform public.v1_accounts_require_capability(p_project_id, v_cap);
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim('v1_restore_client_claim', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  -- One open claim at a time: lock the project's claims before looking.
  perform 1 from public.v1_accounts_client_claims
  where project_id = p_project_id order by id for update;
  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_claim.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001';
  end if;
  -- Only a claim that never had an invoice; an invoiced one comes back with
  -- its invoice (v1_restore_client_invoice).
  if v_claim.status <> 'cancelled' or exists (
    select 1 from public.v1_accounts_client_invoices invoice where invoice.claim_id = p_claim_id
  ) then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_RESTORABLE' using errcode = '55000';
  end if;
  if exists (
    select 1 from public.v1_accounts_client_claims other
    where other.project_id = p_project_id and other.id <> p_claim_id
      and other.status in ('draft', 'ready_for_accounts')
  ) then
    raise exception 'R39_ACCOUNTS_OPEN_CLAIM_EXISTS' using errcode = '55000';
  end if;
  -- A revision draft whose original was already revised again, or is no
  -- longer issued, has nothing left to revise.
  if v_claim.supersedes_claim_id is not null and not exists (
    select 1 from public.v1_accounts_client_claims original
    where original.id = v_claim.supersedes_claim_id and original.status = 'invoiced'
  ) then
    raise exception 'R39_ACCOUNTS_RESTORE_SUPERSEDED' using errcode = '55000';
  end if;
  perform public.v1_accounts_restore_check_claim(p_project_id, p_claim_id);

  v_target := case when v_claim.ready_for_accounts_at is null then 'draft' else 'ready_for_accounts' end;
  v_before := public.v1_accounts_claim_snapshot(p_claim_id);
  update public.v1_accounts_client_claims
  set status = v_target, cancelled_at = null, cancelled_by_auth_user_id = null,
    cancellation_reason = null, record_version = record_version + 1, updated_at = v_now
  where id = p_claim_id;
  perform public.v1_write_audit_event('accounts.client_claim.restored', 'accounts_client_claim',
    p_claim_id, p_project_id, v_before, public.v1_accounts_claim_snapshot(p_claim_id),
    btrim(p_reason), p_idempotency_key);
  v_response := jsonb_build_object('schema_version', 3, 'replayed', false, 'project_id', p_project_id,
    'entity_id', p_claim_id, 'claim_id', p_claim_id, 'record_version', p_expected_version + 1,
    'status', v_target, 'updated_at', v_now);
  perform public.v1_complete_idempotency('v1_restore_client_claim', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_accounts_restore_check_claim(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_restore_client_invoice(uuid, uuid, integer, text, uuid)
  from public, anon;
revoke all on function public.v1_restore_client_claim(uuid, uuid, integer, text, uuid)
  from public, anon;
grant execute on function public.v1_restore_client_invoice(uuid, uuid, integer, text, uuid)
  to authenticated;
grant execute on function public.v1_restore_client_claim(uuid, uuid, integer, text, uuid)
  to authenticated;

notify pgrst, 'reload schema';

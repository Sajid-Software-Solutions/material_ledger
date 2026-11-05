-- R39 Accounts Workspace V2 — P3 (part 2b): invoice revision (R.n)
--
-- Adds v1_revise_client_invoice. Revising an issued invoice (only before any
-- certification, payment or active PDC) clones its claim into a successor draft
-- claim; issuing that successor numbers it base||'R.'||n, links it to the
-- predecessor, and retires the predecessor claim and invoice.
--
-- Modelling note (refines PRODUCT_DECISIONS section 32 / D7): a superseded
-- predecessor is retired by the existing terminal `cancelled` status plus a
-- `supersedes_invoice_id` link and a "Superseded by ..." reason — not a new
-- `superseded` status value. Every commercial reader already excludes
-- `cancelled` (and v1_accounts_dimension_claimed_amount already excludes
-- cancelled claims from P1), so the predecessor stops contributing to invoiced
-- sums, open/overdue counts, reminders and claim capacity with no change to
-- those readers. The supersedes link distinguishes a supersession from a manual
-- cancellation for display. Revision is only allowed before any money fact
-- exists, which is consistent with the frozen rule that an invoice cannot be
-- cancelled after certification, payment or PDC.
--
-- Additive, accounts-only. See R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 8.6.

-- Revision-link columns (no status-value or constraint changes).
alter table public.v1_accounts_client_claims
  add column if not exists supersedes_claim_id uuid
  references public.v1_accounts_client_claims (id) on delete restrict;
alter table public.v1_accounts_client_invoices
  add column if not exists supersedes_invoice_id uuid
  references public.v1_accounts_client_invoices (id) on delete restrict;
alter table public.v1_accounts_client_invoices
  add column if not exists base_reference text;
alter table public.v1_accounts_client_invoices
  add column if not exists revision_number integer not null default 0
  check (revision_number >= 0);

-- ---------------------------------------------------------------------------
-- Revise: clone the invoice's claim into a successor draft claim.
-- ---------------------------------------------------------------------------
create or replace function public.v1_revise_client_invoice(
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
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_role();
  v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;
  v_claim public.v1_accounts_client_claims%rowtype;
  v_new_claim_id uuid := gen_random_uuid();
  v_new_reference text;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  v_exact := public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'invoice_id', p_invoice_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim('v1_revise_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  select * into v_invoice from public.v1_accounts_client_invoices
  where id = p_invoice_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;
  if v_invoice.status not in ('submitted', 'under_certification') then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_REVISABLE' using errcode = '55000'; end if;
  if exists (select 1 from public.v1_accounts_client_certifications where invoice_id = p_invoice_id)
    or public.v1_accounts_invoice_paid_amount(p_invoice_id) > 0
    or public.v1_accounts_invoice_pdc_exposure(p_invoice_id) > 0 then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_REVISABLE' using errcode = '55000'; end if;
  if exists (
    select 1 from public.v1_accounts_client_claims c
    where c.supersedes_claim_id = v_invoice.claim_id and c.status <> 'cancelled'
  ) then
    raise exception 'R39_ACCOUNTS_REVISION_ALREADY_OPEN' using errcode = '55000'; end if;

  select * into v_claim from public.v1_accounts_client_claims where id = v_invoice.claim_id for update;
  v_new_reference := v_claim.claim_reference || '-R' || (coalesce(v_invoice.revision_number, 0) + 1)::text;

  insert into public.v1_accounts_client_claims(
    id, project_id, baseline_revision_id, claim_reference, claim_period_start,
    claim_period_end, status, notes, supersedes_claim_id,
    created_by_auth_user_id, created_by_role, created_by_exact_role, idempotency_key)
  values (v_new_claim_id, p_project_id, v_claim.baseline_revision_id, v_new_reference,
    v_claim.claim_period_start, v_claim.claim_period_end, 'draft', v_claim.notes, v_claim.id,
    v_actor, v_role, v_exact, p_idempotency_key);
  insert into public.v1_accounts_client_claim_lines(
    claim_id, project_id, progress_entry_id, baseline_revision_id, progress_revision_id,
    progress_record_version, project_scope_id, stage_key, stage_value_snapshot,
    confirmed_percent_snapshot, eligible_amount_snapshot, previously_claimed_amount_snapshot,
    claimed_amount, evidence_reference)
  select v_new_claim_id, project_id, progress_entry_id, baseline_revision_id, progress_revision_id,
    progress_record_version, project_scope_id, stage_key, stage_value_snapshot,
    confirmed_percent_snapshot, eligible_amount_snapshot, previously_claimed_amount_snapshot,
    claimed_amount, evidence_reference
  from public.v1_accounts_client_claim_lines where claim_id = v_claim.id;

  perform public.v1_write_audit_event('accounts.client_invoice.revision_started',
    'accounts_client_invoice', p_invoice_id, p_project_id,
    public.v1_accounts_invoice_snapshot(p_invoice_id),
    jsonb_build_object('successor_claim_id', v_new_claim_id, 'successor_claim_reference', v_new_reference),
    btrim(p_reason), p_idempotency_key);

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false, 'project_id', p_project_id,
    'invoice_id', p_invoice_id, 'successor_claim_id', v_new_claim_id,
    'successor_claim_reference', v_new_reference, 'status', 'draft');
  perform public.v1_complete_idempotency('v1_revise_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_revise_client_invoice(uuid, uuid, integer, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Re-create issue to handle successor issuance: R.n numbering + retire the
-- predecessor (cancelled + supersedes link).
-- ---------------------------------------------------------------------------
create or replace function public.v1_issue_client_invoice(
  p_project_id uuid,
  p_claim_id uuid,
  p_expected_claim_version integer,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_claim public.v1_accounts_client_claims%rowtype;
  v_pred_claim public.v1_accounts_client_claims%rowtype;
  v_pred_invoice public.v1_accounts_client_invoices%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_reference text;
  v_base text;
  v_rev integer := 0;
  v_invoice_id uuid;
  v_draft jsonb; v_submit jsonb;
  v_document jsonb; v_sha text;
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if p_submission_date is null or p_invoice_date is null then
    raise exception 'R39_ACCOUNTS_INVOICE_DATE_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_claim_version', p_expected_claim_version, 'invoice_reference', nullif(btrim(p_invoice_reference), ''),
    'invoice_date', p_invoice_date, 'submission_date', p_submission_date);
  v_existing := public.v1_idempotency_get_or_claim('v1_issue_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_expected_claim_version is not null and v_claim.record_version <> p_expected_claim_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  if v_claim.supersedes_claim_id is not null then
    select * into v_pred_claim from public.v1_accounts_client_claims where id = v_claim.supersedes_claim_id for update;
    select * into v_pred_invoice from public.v1_accounts_client_invoices where claim_id = v_pred_claim.id for update;
    v_base := coalesce(v_pred_invoice.base_reference, v_pred_invoice.invoice_reference);
    v_rev := coalesce(v_pred_invoice.revision_number, 0) + 1;
    v_reference := coalesce(nullif(btrim(p_invoice_reference), ''), v_base || 'R.' || v_rev::text);
  elsif nullif(btrim(p_invoice_reference), '') is not null then
    v_reference := btrim(p_invoice_reference);
  else
    select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
    if not found then raise exception 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED' using errcode = '55000'; end if;
    v_reference := v_settings.invoice_prefix || lpad(v_settings.next_sequence::text, 2, '0');
    update public.v1_accounts_project_invoice_settings
    set next_sequence = next_sequence + 1, record_version = record_version + 1, updated_at = v_now
    where project_id = p_project_id;
  end if;

  v_draft := public.v1_create_client_invoice_draft(
    p_project_id, p_claim_id, v_reference, null, md5(p_idempotency_key::text || ':create')::uuid);
  v_invoice_id := (v_draft ->> 'invoice_id')::uuid;
  v_submit := public.v1_submit_client_invoice(
    p_project_id, v_invoice_id, 1, p_submission_date, null, md5(p_idempotency_key::text || ':submit')::uuid);

  if v_claim.supersedes_claim_id is not null then
    update public.v1_accounts_client_invoices
    set base_reference = v_base, revision_number = v_rev, supersedes_invoice_id = v_pred_invoice.id
    where id = v_invoice_id;
    -- Retire the predecessor: cancelled + supersedes link ("Superseded by R.n").
    update public.v1_accounts_client_invoices
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_invoice.id;
    update public.v1_accounts_client_claims
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_claim.id;
    perform public.v1_write_audit_event('accounts.client_invoice.superseded',
      'accounts_client_invoice', v_pred_invoice.id, p_project_id,
      jsonb_build_object('superseded_by_invoice_id', v_invoice_id, 'reference', v_reference),
      null, 'Superseded by ' || v_reference, p_idempotency_key);
  end if;

  v_document := public.v1_accounts_build_invoice_document(
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date, (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'revision_number', v_rev, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

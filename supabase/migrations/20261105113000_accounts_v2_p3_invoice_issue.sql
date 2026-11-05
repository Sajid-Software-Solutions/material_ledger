-- R39 Accounts Workspace V2 — P3 (part 2a): invoice numbering, issue, document
--
-- Adds per-project invoice numbering settings, the frozen printable document
-- snapshot, and v1_issue_client_invoice (allocate number, create + submit the
-- invoice via the existing commands, freeze the document model in one
-- transaction) plus preview and read of that document model. The invoice R.n
-- revision and the superseded status arrive in the next increment; the
-- company letterhead/bank settings (D9) layer into the document model later.
--
-- Additive, accounts-only. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md sections 8.6, 9.

create table if not exists public.v1_accounts_project_invoice_settings (
  project_id uuid primary key references public.v1_projects (id) on delete restrict,
  invoice_prefix text not null check (btrim(invoice_prefix) <> ''),
  next_sequence integer not null default 1 check (next_sequence > 0),
  scope_line text,
  bill_to_party_id uuid,
  attention_name text,
  record_version integer not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.v1_accounts_client_invoice_documents (
  invoice_id uuid primary key
    references public.v1_accounts_client_invoices (id) on delete restrict,
  project_id uuid not null references public.v1_projects (id) on delete restrict,
  document_snapshot jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  controlled_document_id uuid references public.v1_documents (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

alter table public.v1_accounts_project_invoice_settings enable row level security;
alter table public.v1_accounts_client_invoice_documents enable row level security;

-- ---------------------------------------------------------------------------
-- Build the printable document model from a claim (used by issue and preview).
-- It stores the exact amounts and the building x stage breakdown; amount-in-
-- words and letterhead/bank are rendered/added downstream.
-- ---------------------------------------------------------------------------
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
  v_lines jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;

  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2) into v_ex_vat
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;
  v_vat := round(v_ex_vat * v_baseline.vat_rate_percent / 100, 2);

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

  return jsonb_build_object(
    'schema_version', 1,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref, 'name', v_project.name),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text, 'vat', v_vat::text,
      'total_incl_vat', (v_ex_vat + v_vat)::text),
    'lines', v_lines
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Per-project invoice settings (prefix, scope line, attention, bill-to).
-- ---------------------------------------------------------------------------
create or replace function public.v1_save_project_invoice_settings(
  p_project_id uuid,
  p_invoice_prefix text,
  p_scope_line text,
  p_bill_to_party_id uuid,
  p_attention_name text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_row public.v1_accounts_project_invoice_settings%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if nullif(btrim(p_invoice_prefix), '') is null then
    raise exception 'R39_ACCOUNTS_INVOICE_PREFIX_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'invoice_prefix', btrim(p_invoice_prefix),
    'scope_line', nullif(btrim(p_scope_line), ''), 'bill_to_party_id', p_bill_to_party_id,
    'attention_name', nullif(btrim(p_attention_name), ''), 'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim('v1_save_project_invoice_settings', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_row from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
  if not found then
    insert into public.v1_accounts_project_invoice_settings(project_id, invoice_prefix, scope_line, bill_to_party_id, attention_name, created_by_auth_user_id)
    values (p_project_id, btrim(p_invoice_prefix), nullif(btrim(p_scope_line), ''), p_bill_to_party_id, nullif(btrim(p_attention_name), ''), v_actor)
    returning * into v_row;
  else
    if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
      raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;
    update public.v1_accounts_project_invoice_settings
    set invoice_prefix = btrim(p_invoice_prefix), scope_line = nullif(btrim(p_scope_line), ''),
      bill_to_party_id = p_bill_to_party_id, attention_name = nullif(btrim(p_attention_name), ''),
      record_version = record_version + 1, updated_at = v_now
    where project_id = p_project_id returning * into v_row;
  end if;
  v_response := jsonb_build_object('schema_version', 1, 'replayed', false, 'project_id', p_project_id,
    'invoice_prefix', v_row.invoice_prefix, 'next_sequence', v_row.next_sequence, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency('v1_save_project_invoice_settings', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_save_project_invoice_settings(uuid, text, text, uuid, text, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Issue: allocate the number, create + submit the invoice, freeze the document.
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
  v_claim public.v1_accounts_client_claims%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_reference text;
  v_invoice_id uuid;
  v_draft jsonb; v_submit jsonb;
  v_document jsonb; v_sha text;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
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

  -- Allocate the reference: explicit override, else prefix + 2-digit sequence.
  if nullif(btrim(p_invoice_reference), '') is not null then
    v_reference := btrim(p_invoice_reference);
  else
    select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
    if not found then raise exception 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED' using errcode = '55000'; end if;
    v_reference := v_settings.invoice_prefix || lpad(v_settings.next_sequence::text, 2, '0');
    update public.v1_accounts_project_invoice_settings
    set next_sequence = next_sequence + 1, record_version = record_version + 1, updated_at = clock_timestamp()
    where project_id = p_project_id;
  end if;

  v_draft := public.v1_create_client_invoice_draft(
    p_project_id, p_claim_id, v_reference, null, md5(p_idempotency_key::text || ':create')::uuid);
  v_invoice_id := (v_draft ->> 'invoice_id')::uuid;
  v_submit := public.v1_submit_client_invoice(
    p_project_id, v_invoice_id, 1, p_submission_date, null, md5(p_idempotency_key::text || ':submit')::uuid);

  v_document := public.v1_accounts_build_invoice_document(
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date,
    (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Read the frozen document; preview the live model for a ready draft claim.
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_client_invoice_document(p_project_id uuid, p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_doc public.v1_accounts_client_invoice_documents%rowtype;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  select * into v_doc from public.v1_accounts_client_invoice_documents where invoice_id = p_invoice_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_DOCUMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id, 'invoice_id', p_invoice_id,
    'snapshot_sha256', v_doc.snapshot_sha256, 'controlled_document_id', v_doc.controlled_document_id,
    'document', v_doc.document_snapshot);
end;
$$;

create or replace function public.v1_preview_client_invoice_document(p_project_id uuid, p_claim_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_claim public.v1_accounts_client_claims%rowtype; v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_prefix text; v_ref text; v_due date;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  if not public.v1_current_user_has_capability('view_project_commercial_values', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select invoice_prefix || lpad(next_sequence::text, 2, '0') into v_ref
  from public.v1_accounts_project_invoice_settings where project_id = p_project_id;
  v_due := clock_timestamp()::date + v_baseline.payment_terms_days;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id, 'preview', true,
    'document', public.v1_accounts_build_invoice_document(
      p_project_id, p_claim_id, v_ref, clock_timestamp()::date, clock_timestamp()::date, v_due));
end;
$$;

grant execute on function public.v1_get_client_invoice_document(uuid, uuid) to authenticated;
grant execute on function public.v1_preview_client_invoice_document(uuid, uuid) to authenticated;
revoke all on function public.v1_accounts_build_invoice_document(uuid, uuid, text, date, date, date) from public, anon, authenticated;

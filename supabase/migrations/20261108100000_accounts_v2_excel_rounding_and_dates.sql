-- R39 Accounts Workspace V2 — Excel rounding, business dates and the signed
-- invoice layout (owner decisions, 8 November 2026).
--
-- 1. Excel rounding. A claim's gross, VAT and total are worked out from the
--    exact (unrounded) amounts and each rounded once, as the Yorks billing
--    workbook does: gross = round(exact), VAT = round(exact x rate),
--    total = round(exact x (1 + rate)). Each claim line keeps its exact amount
--    beside the rounded one it has always stored. Lines still show fils, so a
--    column of lines can differ from its total by a fil, as on the signed
--    invoices. An invoice or certification total may then differ from
--    ex-VAT + VAT by at most 0.01 (signed YRA32202R.1: 5,983,597.45 +
--    299,179.87 = 6,282,777.33). Certifying the full invoiced amount carries
--    the invoice's own VAT and total.
-- 2. The invoice document. "Till previous" now counts every earlier invoiced
--    claim (all buildings and stages), not only the cells this claim touches;
--    the main summary carries VAT and grand-total rows per column; the header
--    carries the bill-to party (chosen party, else main contractor, else
--    client), its address, the client TRN, attention, work order and contract
--    number. A historical import may set the letterhead/bank it was signed
--    with through the transaction-local setting
--    yorks.invoice_company_override.
-- 3. Activity. Each entry carries the business date it happened on
--    (certification date, cheque action date, invoice date, payment date,
--    claim period end) and the references to name it (invoice, cheque,
--    certification, claim number); the list is ordered by that date.
-- 4. Overview. "To come" is what is invoiced and not yet paid; the progress
--    step is current while a claim is open.
--
-- Additive: one nullable column, relaxed (never tightened) total checks,
-- CREATE OR REPLACE of the affected functions. Existing rows, frozen invoice
-- documents and audit history are unchanged. Rollback: re-apply the previous
-- function definitions; the extra column and relaxed checks are harmless to
-- them (no existing row differs from ex-VAT + VAT).

alter table public.v1_accounts_client_claim_lines
  add column if not exists claimed_amount_exact numeric;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'v1_accounts_claim_lines_exact_amount_check'
      and conrelid = 'public.v1_accounts_client_claim_lines'::regclass
  ) then
    alter table public.v1_accounts_client_claim_lines
      add constraint v1_accounts_claim_lines_exact_amount_check check (
        claimed_amount_exact is null
        or (claimed_amount_exact::text <> 'NaN'
          and claimed_amount_exact > 0
          and abs(claimed_amount_exact - claimed_amount) < 0.01)
      );
  end if;

  if exists (
    select 1 from pg_constraint
    where conname = 'v1_accounts_client_invoices_check'
      and conrelid = 'public.v1_accounts_client_invoices'::regclass
  ) then
    alter table public.v1_accounts_client_invoices
      drop constraint v1_accounts_client_invoices_check;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'v1_accounts_client_invoices_total_rounding_check'
      and conrelid = 'public.v1_accounts_client_invoices'::regclass
  ) then
    alter table public.v1_accounts_client_invoices
      add constraint v1_accounts_client_invoices_total_rounding_check check (
        total_incl_vat_snapshot::text <> 'NaN'
        and abs(total_incl_vat_snapshot - (claimed_ex_vat + vat_amount_snapshot)) <= 0.01
      );
  end if;

  if exists (
    select 1 from pg_constraint
    where conname = 'v1_accounts_client_certifications_check'
      and conrelid = 'public.v1_accounts_client_certifications'::regclass
  ) then
    alter table public.v1_accounts_client_certifications
      drop constraint v1_accounts_client_certifications_check;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'v1_accounts_client_certifications_total_rounding_check'
      and conrelid = 'public.v1_accounts_client_certifications'::regclass
  ) then
    alter table public.v1_accounts_client_certifications
      add constraint v1_accounts_client_certifications_total_rounding_check check (
        certified_incl_vat::text <> 'NaN'
        and abs(certified_incl_vat - (certified_ex_vat + certified_vat)) <= 0.01
      );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Exact helpers (internal; never Data API surfaces).
-- ---------------------------------------------------------------------------

-- The eligible amount to date, unrounded. Same source as
-- v1_accounts_progress_eligible_amount, without its final round(…, 2).
create or replace function public.v1_accounts_progress_eligible_amount_exact(
  p_progress_entry_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  with cell as (
    select bp.id, bp.confirmed_percent, stage.measurement_mode
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations stage
      on stage.baseline_revision_id = bp.baseline_revision_id
      and stage.stage_key = bp.stage_key
    where bp.id = p_progress_entry_id
  )
  select case
    when (select measurement_mode from cell) = 'items' then
      coalesce((
        select sum(
          public.v1_accounts_stage_item_value(ip.stage_item_id)
            * ip.confirmed_qty / nullif(item.quantity, 0))
        from public.v1_accounts_billing_item_progress ip
        join public.v1_accounts_baseline_stage_items item on item.id = ip.stage_item_id
        where ip.progress_entry_id = p_progress_entry_id
      ), 0)
    else
      coalesce(public.v1_accounts_stage_value((select id from cell))
        * (select confirmed_percent from cell) / 100, 0)
  end;
$$;

-- Claimed on a building and stage across all revisions, exact where known.
create or replace function public.v1_accounts_dimension_claimed_amount_exact(
  p_project_id uuid,
  p_project_scope_id uuid,
  p_stage_key text,
  p_excluded_claim_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(coalesce(line.claimed_amount_exact, line.claimed_amount)), 0)
  from public.v1_accounts_client_claim_lines line
  join public.v1_accounts_client_claims claim on claim.id = line.claim_id
  where line.project_id = p_project_id
    and line.project_scope_id = p_project_scope_id
    and line.stage_key = p_stage_key
    and claim.status not in ('cancelled', 'superseded')
    and claim.id is distinct from p_excluded_claim_id;
$$;

-- A claim's exact gross: its lines' exact amounts (rounded ones for lines
-- saved before exact amounts were kept).
create or replace function public.v1_accounts_claim_exact_gross(p_claim_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(coalesce(line.claimed_amount_exact, line.claimed_amount)), 0)
  from public.v1_accounts_client_claim_lines line
  where line.claim_id = p_claim_id;
$$;

-- The Excel rule: gross, VAT and total each rounded once from the exact sum.
create or replace function public.v1_accounts_excel_amounts(
  p_exact numeric,
  p_vat_rate_percent numeric
)
returns table (ex_vat numeric(20,2), vat numeric(20,2), total numeric(20,2))
language sql
immutable
set search_path = ''
as $$
  select
    round(coalesce(p_exact, 0), 2)::numeric(20,2),
    round(coalesce(p_exact, 0) * coalesce(p_vat_rate_percent, 0) / 100, 2)::numeric(20,2),
    round(coalesce(p_exact, 0) * (1 + coalesce(p_vat_rate_percent, 0) / 100), 2)::numeric(20,2);
$$;

revoke all on function public.v1_accounts_progress_eligible_amount_exact(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_dimension_claimed_amount_exact(uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_claim_exact_gross(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_excel_amounts(numeric, numeric)
  from public, anon, authenticated;

-- Claim lines carry their exact amount.
CREATE OR REPLACE FUNCTION public.v1_accounts_validate_claim_lines(p_project_id uuid, p_baseline_revision_id uuid, p_lines jsonb, p_excluded_claim_id uuid DEFAULT NULL::uuid, p_allow_admin_exception boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_line jsonb;
  v_keys text[];
  v_progress public.v1_accounts_billing_progress%rowtype;
  v_progress_revision_id uuid;
  v_stage_value numeric;
  v_eligible numeric;
  v_consumed numeric;
  v_claim numeric;
  v_claim_exact numeric;
  v_eligible_exact numeric;
  v_consumed_exact numeric;
  v_evidence text;
  v_result jsonb := '[]'::jsonb;
  v_seen uuid[] := '{}';
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'R39_ACCOUNTS_CLAIM_LINES_REQUIRED' using errcode = '22023';
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    select coalesce(array_agg(key order by key), '{}') into v_keys
    from jsonb_object_keys(v_line) key;
    if v_keys <> array['claimed_amount','evidence_reference','progress_entry_id']::text[] then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    begin
      select * into strict v_progress from public.v1_accounts_billing_progress
      where id = (v_line ->> 'progress_entry_id')::uuid for update;
    exception when no_data_found or invalid_text_representation then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end;
    if v_progress.id = any(v_seen) or v_progress.project_id <> p_project_id
      or v_progress.baseline_revision_id <> p_baseline_revision_id
      or v_progress.confirmed_percent <= 0
      or v_progress.review_status not in ('not_required','approved') then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, v_progress.id);
    v_claim := public.v1_accounts_parse_money_text(v_line ->> 'claimed_amount');
    if v_claim <= 0 then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_AMOUNT' using errcode = '22023';
    end if;
    v_stage_value := public.v1_accounts_stage_value(v_progress.id);
    -- P1: single eligible source, and dimension-wide claimed across all revisions.
    v_eligible := public.v1_accounts_progress_eligible_amount(v_progress.id);
    v_consumed := public.v1_accounts_dimension_claimed_amount(
      v_progress.project_id, v_progress.project_scope_id, v_progress.stage_key,
      p_excluded_claim_id
    );
    -- Claiming everything still available: its exact amount is the exact
    -- eligible less the exact already claimed. A typed amount is exact as is.
    v_eligible_exact := public.v1_accounts_progress_eligible_amount_exact(v_progress.id);
    v_consumed_exact := public.v1_accounts_dimension_claimed_amount_exact(
      v_progress.project_id, v_progress.project_scope_id, v_progress.stage_key,
      p_excluded_claim_id
    );
    v_claim_exact := case when v_claim = greatest(v_eligible - v_consumed, 0)
      then greatest(v_eligible_exact - v_consumed_exact, 0) else v_claim end;
    if v_claim_exact <= 0 or abs(v_claim_exact - v_claim) >= 0.01 then
      v_claim_exact := v_claim;
    end if;
    if v_claim > greatest(v_eligible - v_consumed, 0)
      and not p_allow_admin_exception then
      raise exception 'R39_ACCOUNTS_CLAIM_CAP_EXCEEDED' using errcode = '23514';
    end if;
    select revision.id into v_progress_revision_id
    from public.v1_accounts_billing_progress_revisions revision
    where revision.progress_entry_id = v_progress.id
    order by revision.revision_number desc
    limit 1;
    if v_progress_revision_id is null then
      raise exception 'R39_ACCOUNTS_PROGRESS_SNAPSHOT_MISSING' using errcode = '55000';
    end if;
    v_evidence := nullif(btrim(v_line ->> 'evidence_reference'), '');
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'progress_entry_id', v_progress.id,
      'progress_revision_id', v_progress_revision_id,
      'progress_record_version', v_progress.record_version,
      'project_scope_id', v_progress.project_scope_id,
      'stage_key', v_progress.stage_key,
      'stage_value_snapshot', v_stage_value::text,
      'confirmed_percent_snapshot', v_progress.confirmed_percent::text,
      'eligible_amount_snapshot', v_eligible::text,
      'previously_claimed_amount_snapshot', v_consumed::text,
      'claimed_amount', v_claim::text,
      'claimed_amount_exact', v_claim_exact::text,
      'evidence_reference', v_evidence
    ));
  end loop;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_accounts_replace_claim_lines(p_claim_id uuid, p_project_id uuid, p_baseline_revision_id uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  delete from public.v1_accounts_client_claim_lines where claim_id = p_claim_id;
  insert into public.v1_accounts_client_claim_lines (
    claim_id, project_id, progress_entry_id, baseline_revision_id,
    progress_revision_id, progress_record_version, project_scope_id, stage_key,
    stage_value_snapshot, confirmed_percent_snapshot, eligible_amount_snapshot,
    previously_claimed_amount_snapshot, claimed_amount, claimed_amount_exact,
    evidence_reference
  )
  select p_claim_id, p_project_id,
    (line ->> 'progress_entry_id')::uuid, p_baseline_revision_id,
    (line ->> 'progress_revision_id')::uuid,
    (line ->> 'progress_record_version')::integer,
    (line ->> 'project_scope_id')::uuid, line ->> 'stage_key',
    (line ->> 'stage_value_snapshot')::numeric,
    (line ->> 'confirmed_percent_snapshot')::numeric,
    (line ->> 'eligible_amount_snapshot')::numeric,
    (line ->> 'previously_claimed_amount_snapshot')::numeric,
    (line ->> 'claimed_amount')::numeric,
    nullif(line ->> 'claimed_amount_exact', '')::numeric,
    nullif(line ->> 'evidence_reference','')
  from jsonb_array_elements(p_lines) line;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_revise_client_invoice(p_project_id uuid, p_invoice_id uuid, p_expected_version integer, p_reason text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    claimed_amount, claimed_amount_exact, evidence_reference)
  select v_new_claim_id, project_id, progress_entry_id, baseline_revision_id, progress_revision_id,
    progress_record_version, project_scope_id, stage_key, stage_value_snapshot,
    confirmed_percent_snapshot, eligible_amount_snapshot, previously_claimed_amount_snapshot,
    claimed_amount, claimed_amount_exact, evidence_reference
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
$function$;

-- Invoices: gross, VAT and total by the Excel rule.
CREATE OR REPLACE FUNCTION public.v1_create_client_invoice_draft(p_project_id uuid, p_claim_id uuid, p_invoice_reference text, p_notes text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_role text:=public.v1_current_role(); v_exact text;
  v_claim public.v1_accounts_client_claims%rowtype; v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_claimed numeric; v_vat numeric; v_total numeric; v_invoice_id uuid:=gen_random_uuid();
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'manage_client_invoices');
  if p_invoice_reference is null or btrim(p_invoice_reference)='' then
    raise exception 'R39_ACCOUNTS_INVOICE_REFERENCE_REQUIRED' using errcode='22023'; end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'claim_id',p_claim_id,
    'invoice_reference',btrim(p_invoice_reference),'notes',nullif(btrim(p_notes),''));
  v_existing:=public.v1_idempotency_get_or_claim('v1_create_client_invoice_draft',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true); end if;
  select * into v_claim from public.v1_accounts_client_claims where id=p_claim_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode='P0002'; end if;
  if v_claim.status<>'ready_for_accounts' or v_claim.is_stale then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_INVOICEABLE' using errcode='55000'; end if;
  if exists(select 1 from public.v1_accounts_client_invoices where claim_id=p_claim_id) then
    raise exception 'R39_ACCOUNTS_CLAIM_ALREADY_INVOICED' using errcode='23505'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id=v_claim.baseline_revision_id;
  select x.ex_vat, x.vat, x.total into v_claimed, v_vat, v_total
  from public.v1_accounts_excel_amounts(
    public.v1_accounts_claim_exact_gross(p_claim_id), v_baseline.vat_rate_percent) x;
  insert into public.v1_accounts_client_invoices(id,project_id,claim_id,invoice_reference,
    claimed_ex_vat,vat_rate_percent_snapshot,vat_amount_snapshot,total_incl_vat_snapshot,
    payment_terms_days_snapshot,reminder_lead_days_snapshot,admin_exception_reason,notes,
    created_by_auth_user_id,
    created_by_role,created_by_exact_role,idempotency_key,created_at,updated_at)
  values(v_invoice_id,p_project_id,p_claim_id,btrim(p_invoice_reference),v_claimed,
    v_baseline.vat_rate_percent,v_vat,v_total,v_baseline.payment_terms_days,
    v_baseline.reminder_lead_days,v_claim.admin_exception_reason,
    nullif(btrim(p_notes),''),v_actor,v_role,v_exact,p_idempotency_key,v_now,v_now);
  perform public.v1_write_audit_event('accounts.client_invoice.draft_created','accounts_client_invoice',v_invoice_id,p_project_id,null,public.v1_accounts_invoice_snapshot(v_invoice_id),null,p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_invoice_id,'invoice_id',v_invoice_id,'claim_id',p_claim_id,'record_version',1,'status','draft','updated_at',v_now);
  perform public.v1_complete_idempotency('v1_create_client_invoice_draft',p_idempotency_key,v_response); return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_INVOICE_REFERENCE' using errcode='23505';
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_record_client_certification(p_project_id uuid, p_invoice_id uuid, p_expected_version integer, p_certification_reference text, p_certification_date date, p_certified_ex_vat text, p_difference_reason text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_amount numeric;v_previous numeric;
  v_vat numeric;v_total numeric;v_revision integer;v_cert_id uuid:=gen_random_uuid();
  v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_certification');
  if nullif(btrim(p_certification_reference),'') is null or p_certification_date is null then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_IDENTITY_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_certified_ex_vat);
  if v_amount<0 then raise exception 'R39_ACCOUNTS_INVALID_CERTIFICATION_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'certification_reference',btrim(p_certification_reference),'certification_date',p_certification_date,
    'certified_ex_vat',v_amount::text,'difference_reason',nullif(btrim(p_difference_reason),''));
  v_existing:=public.v1_idempotency_get_or_claim('v1_record_client_certification',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.status in ('draft','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_CERTIFIABLE' using errcode='55000';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  v_previous:=public.v1_accounts_invoice_certified_ex_vat(p_invoice_id);
  if v_amount<v_previous or v_amount>v_invoice.claimed_ex_vat then raise exception 'R39_ACCOUNTS_CERTIFICATION_CAP_INVALID' using errcode='23514';end if;
  if v_amount<>v_invoice.claimed_ex_vat and nullif(btrim(p_difference_reason),'') is null then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_DIFFERENCE_REASON_REQUIRED' using errcode='22023';end if;
  select coalesce(max(revision_number),0)+1 into v_revision from public.v1_accounts_client_certifications where invoice_id=p_invoice_id;
  -- Certified in full: the invoice's own VAT and total (Excel rounding).
  if v_amount=v_invoice.claimed_ex_vat then
    v_vat:=v_invoice.vat_amount_snapshot;v_total:=v_invoice.total_incl_vat_snapshot;
  else
    v_vat:=round(v_amount*v_invoice.vat_rate_percent_snapshot/100,2);v_total:=v_amount+v_vat;
  end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_certifications(id,project_id,invoice_id,revision_number,certification_reference,
    certification_date,certified_ex_vat,certified_vat,certified_incl_vat,difference_reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_cert_id,p_project_id,p_invoice_id,v_revision,btrim(p_certification_reference),p_certification_date,
    v_amount,v_vat,v_total,nullif(btrim(p_difference_reason),''),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_certification.recorded','accounts_client_certification',v_cert_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),nullif(btrim(p_difference_reason),''),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_cert_id,
    'certification_id',v_cert_id,'invoice_id',p_invoice_id,'revision_number',v_revision,
    'invoice_record_version',p_expected_version+1,'status',v_status,'certified_ex_vat',v_amount::text,'certified_incl_vat',v_total::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_record_client_certification',p_idempotency_key,v_response);return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_correct_client_certification(p_project_id uuid, p_invoice_id uuid, p_expected_version integer, p_certification_reference text, p_certification_date date, p_certified_ex_vat text, p_reason text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_amount numeric;v_vat numeric;v_total numeric;v_revision integer;v_cert_id uuid:=gen_random_uuid();
  v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_certification');
  if nullif(btrim(p_certification_reference),'') is null or p_certification_date is null then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_IDENTITY_REQUIRED' using errcode='22023';end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_certified_ex_vat);
  if v_amount<0 then raise exception 'R39_ACCOUNTS_INVALID_CERTIFICATION_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'certification_reference',btrim(p_certification_reference),'certification_date',p_certification_date,'certified_ex_vat',v_amount::text,'reason',btrim(p_reason));
  v_existing:=public.v1_idempotency_get_or_claim('v1_correct_client_certification',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.status in ('draft','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_CERTIFIABLE' using errcode='55000';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  if not exists(select 1 from public.v1_accounts_client_certifications where invoice_id=p_invoice_id) then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_NOT_FOUND' using errcode='P0002';end if;
  if v_amount>v_invoice.claimed_ex_vat then raise exception 'R39_ACCOUNTS_CERTIFICATION_CAP_INVALID' using errcode='23514';end if;
  select coalesce(max(revision_number),0)+1 into v_revision from public.v1_accounts_client_certifications where invoice_id=p_invoice_id;
  -- Certified in full: the invoice's own VAT and total (Excel rounding).
  if v_amount=v_invoice.claimed_ex_vat then
    v_vat:=v_invoice.vat_amount_snapshot;v_total:=v_invoice.total_incl_vat_snapshot;
  else
    v_vat:=round(v_amount*v_invoice.vat_rate_percent_snapshot/100,2);v_total:=v_amount+v_vat;
  end if;
  if public.v1_accounts_invoice_paid_amount(p_invoice_id)+public.v1_accounts_invoice_pdc_exposure(p_invoice_id)>greatest(v_total-v_invoice.retention_snapshot,0) then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_BELOW_RECEIVED' using errcode='23514';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_certifications(id,project_id,invoice_id,revision_number,certification_reference,
    certification_date,certified_ex_vat,certified_vat,certified_incl_vat,difference_reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_cert_id,p_project_id,p_invoice_id,v_revision,btrim(p_certification_reference),p_certification_date,
    v_amount,v_vat,v_total,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_certification.corrected','accounts_client_certification',v_cert_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_cert_id,'certification_id',v_cert_id,'invoice_id',p_invoice_id,
    'revision_number',v_revision,'invoice_record_version',p_expected_version+1,'status',v_status,'certified_ex_vat',v_amount::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_correct_client_certification',p_idempotency_key,v_response);return v_response;
end;
$function$;

-- Claim totals: the rounded exact gross.
CREATE OR REPLACE FUNCTION public.v1_accounts_claim_snapshot(p_claim_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_claim public.v1_accounts_client_claims%rowtype; v_lines jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id=p_claim_id;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'line_id', line.id,
    'progress_entry_id', line.progress_entry_id,
    'progress_revision_id', line.progress_revision_id,
    'progress_record_version', line.progress_record_version,
    'building_scope_id', line.project_scope_id,
    'stage_key', line.stage_key,
    'stage_value_snapshot', line.stage_value_snapshot::text,
    'confirmed_percent_snapshot', line.confirmed_percent_snapshot::text,
    'eligible_amount_snapshot', line.eligible_amount_snapshot::text,
    'previously_claimed_amount_snapshot', line.previously_claimed_amount_snapshot::text,
    'claimed_amount', line.claimed_amount::text,
    'claimed_amount_exact', coalesce(line.claimed_amount_exact, line.claimed_amount)::text,
    'evidence_reference', line.evidence_reference
  ) order by line.created_at,line.id),'[]'::jsonb) into v_lines
  from public.v1_accounts_client_claim_lines line where line.claim_id=p_claim_id;
  return jsonb_build_object(
    'claim_id',v_claim.id,'project_id',v_claim.project_id,
    'baseline_revision_id',v_claim.baseline_revision_id,
    'claim_reference',v_claim.claim_reference,
    'claim_period_start',v_claim.claim_period_start,
    'claim_period_end',v_claim.claim_period_end,'status',v_claim.status,
    'admin_exception_reason',v_claim.admin_exception_reason,
    'notes',v_claim.notes,'is_stale',v_claim.is_stale,
    'stale_reason',v_claim.stale_reason,'record_version',v_claim.record_version,
    'created_by_auth_user_id',v_claim.created_by_auth_user_id,
    'created_by_role',v_claim.created_by_role,
    'created_by_exact_role',v_claim.created_by_exact_role,
    'ready_for_accounts_at',v_claim.ready_for_accounts_at,
    'cancelled_at',v_claim.cancelled_at,'cancellation_reason',v_claim.cancellation_reason,
    'claimed_ex_vat',round(public.v1_accounts_claim_exact_gross(p_claim_id),2)::text,
    'claimed_ex_vat_exact',public.v1_accounts_claim_exact_gross(p_claim_id)::text,
    'lines',v_lines,'created_at',v_claim.created_at,'updated_at',v_claim.updated_at
  );
end;
$function$;

-- An invoice carries the date printed on it (from its frozen document).
CREATE OR REPLACE FUNCTION public.v1_accounts_invoice_snapshot(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_invoice public.v1_accounts_client_invoices%rowtype;
begin
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'invoice_id',v_invoice.id,'project_id',v_invoice.project_id,
    'claim_id',v_invoice.claim_id,'invoice_reference',v_invoice.invoice_reference,
    'status',v_invoice.status,'claimed_ex_vat',v_invoice.claimed_ex_vat::text,
    'vat_rate_percent_snapshot',v_invoice.vat_rate_percent_snapshot::text,
    'vat_amount_snapshot',v_invoice.vat_amount_snapshot::text,
    'total_incl_vat_snapshot',v_invoice.total_incl_vat_snapshot::text,
    'payment_terms_days_snapshot',v_invoice.payment_terms_days_snapshot,
    'reminder_lead_days_snapshot',v_invoice.reminder_lead_days_snapshot,
    'submission_date',v_invoice.submission_date,'due_date',v_invoice.due_date,
    'invoice_date',(select nullif(d.document_snapshot->>'invoice_date','')
      from public.v1_accounts_client_invoice_documents d where d.invoice_id=v_invoice.id),
    'admin_exception_reason',v_invoice.admin_exception_reason,'notes',v_invoice.notes,
    'record_version',v_invoice.record_version,
    'certified_ex_vat',public.v1_accounts_invoice_certified_ex_vat(v_invoice.id)::text,
    'certified_incl_vat',public.v1_accounts_invoice_certified_incl_vat(v_invoice.id)::text,
    'retention_snapshot',v_invoice.retention_snapshot::text,
    'paid_amount',public.v1_accounts_invoice_paid_amount(v_invoice.id)::text,
    'amount_paid_till_date',public.v1_accounts_invoice_paid_amount(v_invoice.id)::text,
    'still_due',greatest(public.v1_accounts_invoice_certified_incl_vat(v_invoice.id)
      - v_invoice.retention_snapshot - public.v1_accounts_invoice_paid_amount(v_invoice.id),0)::text,
    'pdc_exposure',public.v1_accounts_invoice_pdc_exposure(v_invoice.id)::text,
    'created_by_auth_user_id',v_invoice.created_by_auth_user_id,
    'created_by_role',v_invoice.created_by_role,
    'created_by_exact_role',v_invoice.created_by_exact_role,
    'created_at',v_invoice.created_at,'updated_at',v_invoice.updated_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_list_client_claims(p_project_id uuid, p_status text DEFAULT NULL::text, p_before_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rows jsonb;v_next_time timestamptz;v_next_id uuid;v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  if p_status is not null and p_status not in ('draft','ready_for_accounts','invoiced','cancelled') then raise exception 'R39_ACCOUNTS_INVALID_CLAIM_STATUS' using errcode='22023';end if;
  if not (public.v1_current_user_has_capability('prepare_client_claim',p_project_id)
    and public.v1_current_user_has_capability('view_project_commercial_values',p_project_id))
    and not public.v1_current_user_has_capability('manage_client_invoices',p_project_id) then raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';end if;
  with page as (select claim.*,round(public.v1_accounts_claim_exact_gross(claim.id),2) claimed,public.v1_accounts_claim_number(claim.id) claim_number
    from public.v1_accounts_client_claims claim where claim.project_id=p_project_id and (p_status is null or claim.status=p_status)
      and (p_before_updated_at is null or (claim.updated_at,claim.id)<(p_before_updated_at,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by claim.updated_at desc,claim.id desc limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object('claim_id',id,'claim_reference',claim_reference,'claim_period_start',claim_period_start,
      'claim_period_end',claim_period_end,'status',status,'claimed_ex_vat',claimed::text,'claim_number',claim_number,'is_stale',is_stale,'record_version',record_version,
      'created_by_auth_user_id',created_by_auth_user_id,'created_by_exact_role',created_by_exact_role,'created_at',created_at,'updated_at',updated_at)
      order by updated_at desc,id desc),'[]'::jsonb),min(updated_at),
      (array_agg(id order by updated_at asc,id asc))[1] into v_rows,v_next_time,v_next_id from page;
  return jsonb_build_object('schema_version',3,'project_id',p_project_id,'claims',v_rows,
    'next_cursor',case when jsonb_array_length(v_rows)=v_limit then jsonb_build_object('before_updated_at',v_next_time,'before_id',v_next_id) else null end,
    'capabilities',public.v1_accounts_receivables_capabilities(p_project_id),
    'commands',public.v1_accounts_receivables_commands(p_project_id));
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_get_claim_workbench(p_project_id uuid, p_claim_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_can_values boolean;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_cells jsonb := '[]'::jsonb;
  v_claim jsonb := null;
  v_claim_id uuid;
  v_claim_gross numeric := 0;
  v_claim_exact numeric := 0;
  v_claim_total numeric := 0;
  v_live_invoice public.v1_accounts_client_invoices%rowtype;
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
          'available_exact', greatest(
            public.v1_accounts_progress_eligible_amount_exact(bp.id)
              - public.v1_accounts_dimension_claimed_amount_exact(
                  bp.project_id, bp.project_scope_id, bp.stage_key, null), 0)::text,
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
          'this_claim_amount_exact', coalesce((
            select sum(coalesce(line.claimed_amount_exact, line.claimed_amount))
            from public.v1_accounts_client_claim_lines line
            where line.claim_id = v_claim_id
              and line.project_scope_id = bp.project_scope_id
              and line.stage_key = bp.stage_key), 0)::text,
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
      v_claim := (v_claim - 'claimed_ex_vat' - 'claimed_ex_vat_exact') || jsonb_build_object('lines', coalesce((
        select jsonb_agg(line
          - 'stage_value_snapshot' - 'eligible_amount_snapshot'
          - 'previously_claimed_amount_snapshot' - 'claimed_amount' - 'claimed_amount_exact')
        from jsonb_array_elements(v_claim->'lines') line), '[]'::jsonb));
    end if;
    -- Payable figures: gross (ex VAT) + VAT at the baseline rate = net payable
    -- (incl VAT), plus this claim's share of the contract. Commercial only.
    if v_can_values then
      -- Excel rule from the exact gross; an invoiced claim shows its invoice.
      v_claim_exact := public.v1_accounts_claim_exact_gross(v_claim_id);
      select x.ex_vat, x.vat, x.total into v_claim_gross, v_claim_vat, v_claim_total
      from public.v1_accounts_excel_amounts(
        v_claim_exact, coalesce(v_baseline.vat_rate_percent, 0)) x;
      select * into v_live_invoice from public.v1_accounts_client_invoices i
      where i.claim_id = v_claim_id and i.status <> 'cancelled'
      order by i.created_at desc limit 1;
      if v_live_invoice.id is not null then
        v_claim_gross := v_live_invoice.claimed_ex_vat;
        v_claim_vat := v_live_invoice.vat_amount_snapshot;
        v_claim_total := v_live_invoice.total_incl_vat_snapshot;
      end if;
      -- §28 R-1 preview: retention the profile would currently withhold on this
      -- claim's gross ex-VAT, and the net payable once it is held back.
      v_claim_retention := round(
        v_claim_gross * coalesce(v_profile.retention_percent, 0) / 100, 2);
      v_claim := v_claim || jsonb_build_object(
        'claimed_ex_vat', v_claim_gross::text,
        'claimed_ex_vat_exact', v_claim_exact::text,
        'vat_amount', v_claim_vat::text,
        'net_payable', v_claim_total::text,
        'contract_value', v_baseline.contract_value::text,
        'this_claim_percent', case when v_baseline.contract_value > 0
          then round(v_claim_gross / v_baseline.contract_value * 100, 1)
          else 0 end::text,
        'retention_percent', coalesce(v_profile.retention_percent, 0)::text,
        'retention_preview', v_claim_retention::text,
        'net_payable_after_retention',
          (v_claim_total - v_claim_retention)::text,
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
$function$;

CREATE OR REPLACE FUNCTION public.v1_get_accounts_office_register(p_section text, p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_section text := lower(btrim(coalesce(p_section, '')));
  v_search text := nullif(btrim(p_search), '');
  v_status text := nullif(lower(btrim(p_status)), '');
  v_total integer;
  v_amount numeric;
  v_secondary numeric;
  v_balance numeric;
  v_action_count integer;
  v_items jsonb;
begin
  if not public.v1_accounts_portfolio_role_allowed() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if v_section not in (
    'claims', 'client_payments', 'supplier_bills',
    'due_schedule', 'documents', 'activity'
  ) then
    raise exception 'R39_ACCOUNTS_OFFICE_SECTION_INVALID'
      using errcode = '22023';
  end if;
  if p_limit not between 1 and 100 or p_offset < 0 then
    raise exception 'R39_ACCOUNTS_OFFICE_PAGE_INVALID'
      using errcode = '22023';
  end if;

  with project_context as materialized (
    select project.id,
      project.project_ref,
      project.name,
      project.project_site,
      baseline.currency_code,
      client.party_name as client_name,
      public.v1_current_user_has_capability(
        'view_project_accounts', project.id
      ) as can_view_accounts,
      public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      ) as can_view_values,
      public.v1_current_user_has_capability(
        'view_supplier_costs', project.id
      ) as can_view_supplier
    from public.v1_projects project
    left join public.v1_accounts_project_commercial_profiles profile
      on profile.project_id = project.id
    left join public.v1_accounts_baseline_revisions baseline
      on baseline.id = profile.current_baseline_revision_id
    left join lateral (
      select party.party_name
      from public.v1_project_parties party
      where party.project_id = project.id and party.party_kind = 'client'
      order by party.party_order, party.created_at, party.id
      limit 1
    ) client on true
    where project.state <> 'archived'
  ), office_rows as materialized (
    -- Claims and their latest client invoice/certification/payment position.
    select 'claims'::text as section,
      claim.id as record_id,
      claim.project_id,
      project.project_ref as project_reference,
      project.name as project_name,
      project.client_name as party,
      claim.claim_reference as reference,
      invoice.invoice_reference as secondary_reference,
      coalesce(invoice.status, claim.status) as status,
      coalesce(lines.claimed_amount, 0)::numeric as amount,
      coalesce(invoice.certified_amount, 0)::numeric as secondary_amount,
      greatest(
        coalesce(lines.claimed_amount, 0) - coalesce(invoice.certified_amount, 0),
        0
      )::numeric as balance_amount,
      claim.claim_period_end as event_date,
      invoice.due_date,
      greatest(claim.updated_at, coalesce(invoice.updated_at, claim.updated_at)) as occurred_at,
      (
        claim.status = 'ready_for_accounts'
        or coalesce(invoice.status in (
          'submitted', 'under_certification', 'partially_certified', 'returned'
        ), false)
      ) as action_required,
      'claim'::text as record_kind,
      project.currency_code,
      jsonb_build_object(
        'claim_period_start', claim.claim_period_start,
        'claim_period_end', claim.claim_period_end,
        'is_stale', claim.is_stale,
        'record_version', claim.record_version
      ) as metadata
    from public.v1_accounts_client_claims claim
    join project_context project on project.id = claim.project_id
    left join lateral (
      select round(sum(coalesce(line.claimed_amount_exact, line.claimed_amount)), 2) as claimed_amount
      from public.v1_accounts_client_claim_lines line
      where line.claim_id = claim.id
    ) lines on true
    left join lateral (
      select string_agg(item.invoice_reference, ', ' order by item.created_at) as invoice_reference,
        (array_agg(item.status order by item.updated_at desc, item.id desc))[1] as status,
        sum(public.v1_accounts_invoice_certified_incl_vat(item.id)) as certified_amount,
        max(item.due_date) as due_date,
        max(item.updated_at) as updated_at
      from public.v1_accounts_client_invoices item
      where item.claim_id = claim.id and item.status <> 'cancelled'
    ) invoice on true
    where v_section = 'claims'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Append-only client receipts.
    select 'client_payments', payment.id, payment.project_id,
      project.project_ref, project.name, project.client_name,
      payment.payment_reference,
      invoice.invoice_reference,
      case when payment.entry_kind = 'reversal' then 'reversed' else 'received' end,
      payment.amount,
      null::numeric,
      null::numeric,
      payment.payment_date,
      null::date,
      payment.created_at,
      false,
      'client_payment',
      project.currency_code,
      jsonb_build_object(
        'entry_kind', payment.entry_kind,
        'payment_method', payment.payment_method,
        'reason', payment.reason
      )
    from public.v1_accounts_client_payments payment
    join project_context project on project.id = payment.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = payment.invoice_id
    where v_section = 'client_payments'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Post-dated cheque register; this is not a bank-reconciliation ledger.
    select 'client_payments', pdc.id, pdc.project_id,
      project.project_ref, project.name, project.client_name,
      pdc.cheque_number,
      invoice.invoice_reference,
      pdc.status,
      pdc.amount,
      null::numeric,
      null::numeric,
      pdc.received_date,
      pdc.cheque_date,
      pdc.updated_at,
      pdc.action_required,
      'pdc',
      project.currency_code,
      jsonb_build_object(
        'bank_name', pdc.bank_name,
        'last_action_reason', pdc.last_action_reason,
        'record_version', pdc.record_version
      )
    from public.v1_accounts_client_pdcs pdc
    join project_context project on project.id = pdc.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = pdc.invoice_id
    where v_section = 'client_payments'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Supplier bills require both Accounts admission and the distinct
    -- supplier-cost capability for this same project.
    select 'supplier_bills', bill.id, bill.project_id,
      project.project_ref, project.name, bill.supplier_name_snapshot,
      bill.supplier_invoice_reference,
      coalesce(bill.po_lpo_reference, bill.accepted_delivery_reference),
      case
        when bill.status = 'cancelled' then 'cancelled'
        when public.v1_accounts_supplier_paid_amount(bill.id) >= bill.total_incl_vat then 'paid'
        when public.v1_accounts_supplier_paid_amount(bill.id) > 0 then 'partially_paid'
        when bill.status = 'approved' then 'approved'
        when bill.explicit_mismatch_reason is not null then 'review'
        else 'draft'
      end,
      bill.total_incl_vat,
      public.v1_accounts_supplier_paid_amount(bill.id),
      greatest(
        bill.total_incl_vat - public.v1_accounts_supplier_paid_amount(bill.id),
        0
      ),
      bill.invoice_date,
      bill.due_date,
      bill.updated_at,
      (
        bill.status <> 'cancelled'
        and (
          bill.status <> 'approved'
          or public.v1_accounts_supplier_paid_amount(bill.id) < bill.total_incl_vat
            and bill.due_date <= current_date + 7
        )
      ),
      'supplier_bill',
      project.currency_code,
      jsonb_build_object(
        'match_status', public.v1_accounts_supplier_match_status(bill.id),
        'vat_amount', bill.vat_amount::text,
        'record_version', bill.record_version
      )
    from public.v1_accounts_supplier_bills bill
    join project_context project on project.id = bill.project_id
    where v_section = 'supplier_bills'
      and project.can_view_accounts
      and project.can_view_supplier

    union all

    -- Client receivable due facts.
    select 'due_schedule', invoice.id, invoice.project_id,
      project.project_ref, project.name, project.client_name,
      invoice.invoice_reference,
      claim.claim_reference,
      case
        when invoice.due_date < current_date then 'overdue'
        when invoice.due_date = current_date then 'due_today'
        when invoice.due_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      public.v1_accounts_invoice_certified_incl_vat(invoice.id),
      public.v1_accounts_invoice_paid_amount(invoice.id),
      greatest(
        public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id),
        0
      ),
      invoice.submission_date,
      invoice.due_date,
      invoice.updated_at,
      invoice.due_date <= current_date + invoice.reminder_lead_days_snapshot,
      'client_invoice_due',
      project.currency_code,
      jsonb_build_object('invoice_status', invoice.status)
    from public.v1_accounts_client_invoices invoice
    join project_context project on project.id = invoice.project_id
    join public.v1_accounts_client_claims claim on claim.id = invoice.claim_id
    where v_section = 'due_schedule'
      and invoice.status not in ('draft', 'returned', 'cancelled', 'paid')
      and invoice.due_date is not null
      and public.v1_accounts_invoice_certified_incl_vat(invoice.id)
        - public.v1_accounts_invoice_retention(invoice.id)
        > public.v1_accounts_invoice_paid_amount(invoice.id)
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- PDC maturity due facts.
    select 'due_schedule', pdc.id, pdc.project_id,
      project.project_ref, project.name, project.client_name,
      pdc.cheque_number,
      invoice.invoice_reference,
      case
        when pdc.cheque_date < current_date then 'overdue'
        when pdc.cheque_date = current_date then 'due_today'
        when pdc.cheque_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      pdc.amount,
      null::numeric,
      pdc.amount,
      pdc.received_date,
      pdc.cheque_date,
      pdc.updated_at,
      pdc.action_required or pdc.cheque_date <= current_date + 7,
      'pdc_due',
      project.currency_code,
      jsonb_build_object('pdc_status', pdc.status, 'bank_name', pdc.bank_name)
    from public.v1_accounts_client_pdcs pdc
    join project_context project on project.id = pdc.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = pdc.invoice_id
    where v_section = 'due_schedule'
      and pdc.status in ('expected', 'received', 'deposited')
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Supplier payable due facts require the same project's Accounts and
    -- supplier-cost capabilities.
    select 'due_schedule', bill.id, bill.project_id,
      project.project_ref, project.name, bill.supplier_name_snapshot,
      bill.supplier_invoice_reference,
      coalesce(bill.po_lpo_reference, bill.accepted_delivery_reference),
      case
        when bill.due_date < current_date then 'overdue'
        when bill.due_date = current_date then 'due_today'
        when bill.due_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      bill.total_incl_vat,
      public.v1_accounts_supplier_paid_amount(bill.id),
      greatest(
        bill.total_incl_vat - public.v1_accounts_supplier_paid_amount(bill.id),
        0
      ),
      bill.invoice_date,
      bill.due_date,
      bill.updated_at,
      bill.due_date <= current_date + 7,
      'supplier_bill_due',
      project.currency_code,
      jsonb_build_object('bill_status', bill.status)
    from public.v1_accounts_supplier_bills bill
    join project_context project on project.id = bill.project_id
    where v_section = 'due_schedule'
      and bill.status <> 'cancelled'
      and bill.due_date is not null
      and bill.total_incl_vat > public.v1_accounts_supplier_paid_amount(bill.id)
      and project.can_view_accounts
      and project.can_view_supplier

    union all

    -- Controlled Accounts documents. v1_document_readable repeats storage
    -- classification and entity-access checks for every row.
    select 'documents', document.id, link.project_id,
      project.project_ref, project.name, project.client_name,
      version.original_file_name,
      metadata.document_type,
      case when metadata.archived_at is null then 'active' else 'archived' end,
      null::numeric,
      null::numeric,
      null::numeric,
      version.uploaded_at::date,
      null::date,
      version.uploaded_at,
      false,
      'document',
      project.currency_code,
      jsonb_build_object(
        'classification', document.classification,
        'mime_type', version.mime_type,
        'byte_size', version.byte_size,
        'revision_number', version.revision_number,
        'entity_type', link.entity_type,
        'entity_id', link.entity_id,
        'uploader', public.v1_safe_profile_display_name(
          uploader.display_name, uploader.auth_user_id
        )
      )
    from public.v1_accounts_document_metadata metadata
    join public.v1_documents document on document.id = metadata.document_id
    join public.v1_document_versions version on version.id = document.current_version_id
    join lateral (
      select distinct on (candidate.project_id)
        candidate.project_id,
        candidate.entity_type,
        candidate.entity_id
      from public.v1_document_links candidate
      where candidate.document_id = document.id
        and candidate.removed_at is null
        and candidate.project_id is not null
      order by
        candidate.project_id,
        candidate.linked_at,
        candidate.id
    ) link on true
    join project_context project on project.id = link.project_id
    join public.v1_profiles uploader
      on uploader.auth_user_id = version.uploaded_by_auth_user_id
    where v_section = 'documents'
      and project.can_view_accounts
      and public.v1_document_readable(document.id)

    union all

    -- Portfolio-wide append-only Accounts activity. Commercial before/after
    -- payloads deliberately remain in the existing project-scoped inspector.
    select 'activity', audit.id, audit.project_id,
      project.project_ref, project.name,
      public.v1_safe_profile_display_name(actor.display_name, actor.auth_user_id),
      audit.event_type,
      audit.entity_type,
      'recorded',
      null::numeric,
      null::numeric,
      null::numeric,
      audit.occurred_at::date,
      null::date,
      audit.occurred_at,
      false,
      'activity',
      project.currency_code,
      jsonb_build_object(
        'actor_exact_role', coalesce(audit.actor_exact_role, audit.actor_role),
        'reason', audit.reason,
        'entity_id', audit.entity_id
      )
    from public.v1_audit_events audit
    join project_context project on project.id = audit.project_id
    join public.v1_profiles actor on actor.auth_user_id = audit.actor_auth_user_id
    where v_section = 'activity'
      and (audit.event_type like 'accounts.%' or audit.entity_type like 'accounts_%')
      and project.can_view_accounts
      and (
        audit.entity_type not in ('accounts_supplier_bill', 'accounts_supplier_payment')
        or project.can_view_supplier
      )
  ), filtered as materialized (
    select *
    from office_rows row_item
    where (v_status is null or lower(row_item.status) = v_status)
      and (
        v_search is null
        or row_item.project_reference ilike '%' || v_search || '%'
        or row_item.project_name ilike '%' || v_search || '%'
        or coalesce(row_item.party, '') ilike '%' || v_search || '%'
        or row_item.reference ilike '%' || v_search || '%'
        or coalesce(row_item.secondary_reference, '') ilike '%' || v_search || '%'
      )
  ), page as (
    select *
    from filtered
    order by
      case when v_section = 'due_schedule' then due_date end asc nulls last,
      occurred_at desc,
      record_id desc
    limit p_limit offset p_offset
  )
  select
    (select count(*) from filtered),
    -- With no status filter, Receipts & PDC lists a cleared cheque beside the
    -- receipt it became, and a reversal beside the payment it undoes. Count each
    -- sum of money once. A filtered list is one kind of row, so it simply adds up.
    (select coalesce(sum(case
        when v_section <> 'client_payments' or v_status is not null then amount
        when status = 'reversed' then -amount
        when status in ('cleared', 'replaced', 'returned', 'bounced', 'cancelled') then 0
        else amount
      end), 0) from filtered),
    (select coalesce(sum(secondary_amount), 0) from filtered),
    (select coalesce(sum(balance_amount), 0) from filtered),
    (select count(*) from filtered where action_required),
    coalesce(jsonb_agg(jsonb_build_object(
      'record_id', page.record_id,
      'project_id', page.project_id,
      'project_reference', page.project_reference,
      'project_name', page.project_name,
      'party', page.party,
      'reference', page.reference,
      'secondary_reference', page.secondary_reference,
      'status', page.status,
      'amount', case when page.amount is null then null else page.amount::text end,
      'secondary_amount', case
        when page.secondary_amount is null then null
        else page.secondary_amount::text
      end,
      'balance_amount', case
        when page.balance_amount is null then null
        else page.balance_amount::text
      end,
      'event_date', page.event_date,
      'due_date', page.due_date,
      'occurred_at', page.occurred_at,
      'action_required', page.action_required,
      'record_kind', page.record_kind,
      'currency_code', coalesce(page.currency_code, 'AED'),
      'metadata', page.metadata
    ) order by
      case when v_section = 'due_schedule' then page.due_date end asc nulls last,
      page.occurred_at desc,
      page.record_id desc), '[]'::jsonb)
  into v_total, v_amount, v_secondary, v_balance, v_action_count, v_items
  from page;

  return jsonb_build_object(
    'schema_version', 8,
    'section', v_section,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'summary', jsonb_build_object(
      'amount', v_amount::text,
      'secondary_amount', v_secondary::text,
      'balance_amount', v_balance::text,
      'action_count', v_action_count
    ),
    'items', v_items
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_get_accounts_export(p_export_kind text, p_project_id uuid DEFAULT NULL::uuid, p_idempotency_key uuid DEFAULT gen_random_uuid())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_permission_exact_role(auth.uid());
  v_project public.v1_projects%rowtype;
  v_columns jsonb;
  v_rows jsonb;
  v_result jsonb;
  v_existing jsonb;
  v_payload jsonb;
begin
  if p_export_kind not in (
    'portfolio', 'project_summary', 'commercial_baseline',
    'building_allocations', 'stage_allocations', 'billing_progress',
    'progress_history', 'client_claims', 'claim_lines', 'client_invoices',
    'certifications', 'client_receipts', 'pdc_register', 'pdc_events',
    'supplier_bills', 'supplier_payments', 'accounts_documents',
    'accounts_activity'
  ) then
    raise exception 'R39_ACCOUNTS_EXPORT_KIND_INVALID' using errcode = '22023';
  end if;

  if p_export_kind = 'portfolio' then
    if v_role not in (
      'accountant', 'admin', 'senior_mechanical_engineer', 'project_manager'
    ) then
      raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
    end if;
  elsif p_project_id is null or not public.v1_current_user_has_capability(
    'export_accounts_registers', p_project_id
  ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  if p_export_kind in (
    'project_summary', 'commercial_baseline', 'building_allocations',
    'stage_allocations', 'progress_history', 'client_claims', 'claim_lines',
    'client_invoices', 'certifications', 'client_receipts', 'pdc_register',
    'pdc_events', 'accounts_documents', 'accounts_activity'
  ) and not public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  if p_export_kind in ('supplier_bills', 'supplier_payments')
    and not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  v_payload := jsonb_build_object(
    'export_kind', p_export_kind,
    'project_id', p_project_id
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_get_accounts_export', p_idempotency_key, v_payload
  );
  if v_existing is not null then
    return v_existing;
  end if;

  if p_project_id is not null then
    select * into v_project
    from public.v1_projects
    where id = p_project_id;
    if not found then
      raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  case p_export_kind
    when 'portfolio' then
      v_columns := '["Project","Client","Contract","Confirmed work","Claimed","Certified","Paid","Still due","Progress %"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        project.project_ref,
        coalesce(client.party_name, ''),
        baseline.contract_value::text,
        coalesce(progress.confirmed, 0)::text,
        coalesce(invoice.claimed, 0)::text,
        coalesce(invoice.certified, 0)::text,
        coalesce(invoice.paid, 0)::text,
        greatest(
          coalesce(invoice.certified, 0)
          - coalesce(invoice.retention, 0)
          - coalesce(invoice.paid, 0), 0
        )::text,
        coalesce(progress.percent, 0)::text
      ) order by project.project_ref), '[]'::jsonb)
      into v_rows
      from public.v1_projects project
      join public.v1_accounts_project_commercial_profiles profile
        on profile.project_id = project.id
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = profile.current_baseline_revision_id
      left join lateral (
        select party_name
        from public.v1_project_parties
        where project_id = project.id and party_kind = 'client'
        order by created_at, id
        limit 1
      ) client on true
      left join lateral (
        select
          coalesce(sum(round(
            baseline.contract_value * building.allocation_percent / 100
            * stage.allocation_percent / 100
            * progress_entry.confirmed_percent / 100, 2
          )), 0) confirmed,
          case
            when coalesce(sum(
              building.allocation_percent * stage.allocation_percent
            ), 0) = 0 then 0
            else round(sum(
              building.allocation_percent * stage.allocation_percent
              * progress_entry.confirmed_percent
            ) / sum(
              building.allocation_percent * stage.allocation_percent
            ), 2)
          end percent
        from public.v1_accounts_billing_progress progress_entry
        join public.v1_accounts_baseline_building_allocations building
          on building.id = progress_entry.building_allocation_id
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.id = progress_entry.stage_allocation_id
        where progress_entry.project_id = project.id
          and progress_entry.review_status <> 'returned'
      ) progress on true
      left join lateral (
        select
          coalesce(sum(invoice_record.claimed_ex_vat), 0) claimed,
          coalesce(sum(
            public.v1_accounts_invoice_certified_incl_vat(invoice_record.id)
          ), 0) certified,
          coalesce(sum(
            public.v1_accounts_invoice_paid_amount(invoice_record.id)
          ), 0) paid,
          coalesce(sum(
            public.v1_accounts_invoice_retention(invoice_record.id)
          ), 0) retention
        from public.v1_accounts_client_invoices invoice_record
        where invoice_record.project_id = project.id
          and invoice_record.status <> 'cancelled'
      ) invoice on true
      where public.v1_current_user_has_capability(
        'export_accounts_registers', project.id
      ) and public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      );

    when 'project_summary' then
      v_columns := '["Project Reference","Project Name","Site","Client","Contract Value","Confirmed Eligible","Available to Claim","Claimed","Certified","Paid","Still Due","Active PDC","Commercial Progress %"]'::jsonb;
      select jsonb_agg(jsonb_build_array(
        v_project.project_ref,
        v_project.name,
        v_project.project_site,
        coalesce(client.party_name, ''),
        baseline.contract_value::text,
        coalesce(progress.confirmed, 0)::text,
        greatest(
          coalesce(progress.confirmed, 0) - coalesce(claims.claimed, 0), 0
        )::text,
        coalesce(invoice.claimed, 0)::text,
        coalesce(invoice.certified, 0)::text,
        coalesce(invoice.paid, 0)::text,
        greatest(
          coalesce(invoice.certified, 0)
          - coalesce(invoice.retention, 0)
          - coalesce(invoice.paid, 0), 0
        )::text,
        coalesce(pdc.exposure, 0)::text,
        coalesce(progress.percent, 0)::text
      ))
      into v_rows
      from public.v1_accounts_project_commercial_profiles profile
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = profile.current_baseline_revision_id
      left join lateral (
        select party_name
        from public.v1_project_parties
        where project_id = p_project_id and party_kind = 'client'
        order by created_at, id
        limit 1
      ) client on true
      left join lateral (
        select
          coalesce(sum(round(
            baseline.contract_value * building.allocation_percent / 100
            * stage.allocation_percent / 100
            * progress_entry.confirmed_percent / 100, 2
          )), 0) confirmed,
          case
            when coalesce(sum(
              building.allocation_percent * stage.allocation_percent
            ), 0) = 0 then 0
            else round(sum(
              building.allocation_percent * stage.allocation_percent
              * progress_entry.confirmed_percent
            ) / sum(
              building.allocation_percent * stage.allocation_percent
            ), 2)
          end percent
        from public.v1_accounts_billing_progress progress_entry
        join public.v1_accounts_baseline_building_allocations building
          on building.id = progress_entry.building_allocation_id
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.id = progress_entry.stage_allocation_id
        where progress_entry.project_id = p_project_id
          and progress_entry.review_status <> 'returned'
      ) progress on true
      left join lateral (
        select coalesce(sum(line.claimed_amount), 0) claimed
        from public.v1_accounts_client_claim_lines line
        join public.v1_accounts_client_claims claim on claim.id = line.claim_id
        where claim.project_id = p_project_id and claim.status <> 'cancelled'
      ) claims on true
      left join lateral (
        select
          coalesce(sum(invoice_record.claimed_ex_vat), 0) claimed,
          coalesce(sum(
            public.v1_accounts_invoice_certified_incl_vat(invoice_record.id)
          ), 0) certified,
          coalesce(sum(
            public.v1_accounts_invoice_paid_amount(invoice_record.id)
          ), 0) paid,
          coalesce(sum(
            public.v1_accounts_invoice_retention(invoice_record.id)
          ), 0) retention
        from public.v1_accounts_client_invoices invoice_record
        where invoice_record.project_id = p_project_id
          and invoice_record.status <> 'cancelled'
      ) invoice on true
      left join lateral (
        select coalesce(sum(pdc_record.amount), 0) exposure
        from public.v1_accounts_client_pdcs pdc_record
        where pdc_record.project_id = p_project_id
          and pdc_record.status in ('expected', 'received', 'deposited')
      ) pdc on true
      where profile.project_id = p_project_id;

    when 'commercial_baseline' then
      v_columns := '["Revision","Status","Contract Value","Currency","VAT %","Payment Terms Days","Reminder Lead Days","Effective At","Reason","Approved By","Approved Role"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        baseline.contract_value::text,
        baseline.currency_code,
        baseline.vat_rate_percent::text,
        baseline.payment_terms_days::text,
        baseline.reminder_lead_days::text,
        baseline.effective_at::text,
        baseline.reason,
        public.v1_safe_profile_display_name(
          approver.display_name, approver.auth_user_id
        ),
        baseline.approved_by_exact_role
      ) order by baseline.revision_number desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_revisions baseline
      join public.v1_profiles approver
        on approver.auth_user_id = baseline.approved_by_auth_user_id
      where baseline.project_id = p_project_id;

    when 'building_allocations' then
      v_columns := '["Baseline Revision","Baseline Status","Building Code","Building","Allocation %","Allocated Value"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        scope.scope_code,
        scope.name,
        allocation.allocation_percent::text,
        round(
          baseline.contract_value * allocation.allocation_percent / 100, 2
        )::text
      ) order by baseline.revision_number desc, scope.scope_code), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_building_allocations allocation
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = allocation.baseline_revision_id
      join public.v1_project_scopes scope
        on scope.id = allocation.project_scope_id
      where allocation.project_id = p_project_id;

    when 'stage_allocations' then
      v_columns := '["Baseline Revision","Baseline Status","Stage Key","Stage","Display Order","Contract %","Contract Value"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        stage.stage_key,
        stage.stage_name,
        stage.display_order::text,
        stage.allocation_percent::text,
        round(
          baseline.contract_value * stage.allocation_percent / 100, 2
        )::text
      ) order by baseline.revision_number desc, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_stage_allocations stage
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = stage.baseline_revision_id
      where stage.project_id = p_project_id;

    when 'billing_progress' then
      v_columns := '["Building","Stage","Building Allocation %","Stage Allocation %","Stage Value","Suggested %","Confirmed %","Eligible Amount","Review Status","Suggested Evidence","Confirmed Evidence","Evidence Files","Suggested By","Suggested At","Confirmed By","Confirmed At","Reviewed By","Reviewed At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        scope.name,
        stage.stage_name,
        building.allocation_percent::text,
        stage.allocation_percent::text,
        round(
          baseline.contract_value * building.allocation_percent / 100
          * stage.allocation_percent / 100, 2
        )::text,
        entry.suggested_percent::text,
        entry.confirmed_percent::text,
        round(
          baseline.contract_value * building.allocation_percent / 100
          * stage.allocation_percent / 100
          * entry.confirmed_percent / 100, 2
        )::text,
        entry.review_status,
        coalesce(entry.suggested_evidence_summary, ''),
        coalesce(entry.confirmed_evidence_summary, ''),
        (
          cardinality(entry.suggested_evidence_document_ids)
          + cardinality(entry.confirmed_evidence_document_ids)
        )::text,
        case when suggested.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            suggested.display_name, suggested.auth_user_id
          ) end,
        coalesce(entry.suggested_at::text, ''),
        case when confirmed.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            confirmed.display_name, confirmed.auth_user_id
          ) end,
        coalesce(entry.confirmed_at::text, ''),
        case when reviewed.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            reviewed.display_name, reviewed.auth_user_id
          ) end,
        coalesce(entry.reviewed_at::text, ''),
        entry.updated_at::text,
        entry.record_version::text
      ) order by scope.scope_kind, scope.scope_code, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_billing_progress entry
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = entry.baseline_revision_id
      join public.v1_accounts_baseline_building_allocations building
        on building.id = entry.building_allocation_id
      join public.v1_project_scopes scope on scope.id = entry.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = entry.stage_allocation_id
      left join public.v1_profiles suggested
        on suggested.auth_user_id = entry.suggested_by_auth_user_id
      left join public.v1_profiles confirmed
        on confirmed.auth_user_id = entry.confirmed_by_auth_user_id
      left join public.v1_profiles reviewed
        on reviewed.auth_user_id = entry.reviewed_by_auth_user_id
      where entry.project_id = p_project_id;

    when 'progress_history' then
      v_columns := '["Building","Stage","Revision","Action","Previous Suggested %","New Suggested %","Previous Confirmed %","New Confirmed %","Previous Review","New Review","Evidence","Evidence Files","Reason","Actor","Role","Occurred At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        scope.name,
        stage.stage_name,
        revision.revision_number::text,
        revision.action,
        revision.previous_suggested_percent::text,
        revision.new_suggested_percent::text,
        revision.previous_confirmed_percent::text,
        revision.new_confirmed_percent::text,
        revision.previous_review_status,
        revision.new_review_status,
        coalesce(revision.evidence_summary, ''),
        cardinality(revision.evidence_document_ids)::text,
        revision.reason,
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        revision.actor_exact_role,
        revision.occurred_at::text
      ) order by revision.occurred_at desc, revision.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_billing_progress_revisions revision
      join public.v1_accounts_billing_progress progress
        on progress.id = revision.progress_entry_id
      join public.v1_project_scopes scope
        on scope.id = progress.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = progress.stage_allocation_id
      join public.v1_profiles actor
        on actor.auth_user_id = revision.actor_auth_user_id
      where revision.project_id = p_project_id;

    when 'client_claims' then
      v_columns := '["Claim","Status","Period Start","Period End","Baseline Revision","Claimed Amount","Line Count","Stale","Stale Reason","Notes","Created By","Created Role","Created At","Ready For Accounts At","Cancelled At","Cancellation Reason","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        claim.claim_reference,
        claim.status,
        claim.claim_period_start::text,
        claim.claim_period_end::text,
        baseline.revision_number::text,
        coalesce(lines.amount, 0)::text,
        coalesce(lines.line_count, 0)::text,
        claim.is_stale::text,
        coalesce(claim.stale_reason, ''),
        coalesce(claim.notes, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        claim.created_by_exact_role,
        claim.created_at::text,
        coalesce(claim.ready_for_accounts_at::text, ''),
        coalesce(claim.cancelled_at::text, ''),
        coalesce(claim.cancellation_reason, ''),
        claim.record_version::text
      ) order by claim.updated_at desc, claim.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_claims claim
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = claim.baseline_revision_id
      join public.v1_profiles creator
        on creator.auth_user_id = claim.created_by_auth_user_id
      left join lateral (
        select round(sum(coalesce(line.claimed_amount_exact, line.claimed_amount)), 2) amount,
          count(*) line_count
        from public.v1_accounts_client_claim_lines line
        where line.claim_id = claim.id
      ) lines on true
      where claim.project_id = p_project_id;

    when 'claim_lines' then
      v_columns := '["Claim","Claim Status","Building","Stage","Stage Value","Confirmed %","Eligible Amount","Previously Claimed","This Claim","Evidence Reference","Progress Revision","Progress Version","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        claim.claim_reference,
        claim.status,
        scope.name,
        stage.stage_name,
        line.stage_value_snapshot::text,
        line.confirmed_percent_snapshot::text,
        line.eligible_amount_snapshot::text,
        line.previously_claimed_amount_snapshot::text,
        line.claimed_amount::text,
        coalesce(line.evidence_reference, ''),
        progress_revision.revision_number::text,
        line.progress_record_version::text,
        line.created_at::text
      ) order by claim.claim_reference, scope.scope_code, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_claim_lines line
      join public.v1_accounts_client_claims claim on claim.id = line.claim_id
      join public.v1_project_scopes scope on scope.id = line.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.baseline_revision_id = line.baseline_revision_id
        and stage.stage_key = line.stage_key
      join public.v1_accounts_billing_progress_revisions progress_revision
        on progress_revision.id = line.progress_revision_id
      where line.project_id = p_project_id;

    when 'client_invoices' then
      v_columns := '["Invoice","Claim","Status","Claimed ex VAT","VAT %","VAT Amount","Total incl VAT","Certified incl VAT","Paid","Still Due","Payment Terms Days","Reminder Lead Days","Submitted","Due","Returned At","Return Reason","Cancelled At","Cancellation Reason","Notes","Created By","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        invoice.invoice_reference,
        claim.claim_reference,
        invoice.status,
        invoice.claimed_ex_vat::text,
        invoice.vat_rate_percent_snapshot::text,
        invoice.vat_amount_snapshot::text,
        invoice.total_incl_vat_snapshot::text,
        public.v1_accounts_invoice_certified_incl_vat(invoice.id)::text,
        public.v1_accounts_invoice_paid_amount(invoice.id)::text,
        greatest(
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id), 0
        )::text,
        invoice.payment_terms_days_snapshot::text,
        invoice.reminder_lead_days_snapshot::text,
        coalesce(invoice.submission_date::text, ''),
        coalesce(invoice.due_date::text, ''),
        coalesce(invoice.returned_at::text, ''),
        coalesce(invoice.return_reason, ''),
        coalesce(invoice.cancelled_at::text, ''),
        coalesce(invoice.cancellation_reason, ''),
        coalesce(invoice.notes, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        invoice.created_at::text,
        invoice.updated_at::text,
        invoice.record_version::text
      ) order by invoice.updated_at desc, invoice.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_invoices invoice
      join public.v1_accounts_client_claims claim on claim.id = invoice.claim_id
      join public.v1_profiles creator
        on creator.auth_user_id = invoice.created_by_auth_user_id
      where invoice.project_id = p_project_id;

    when 'certifications' then
      v_columns := '["Certification","Invoice","Revision","Certification Date","Certified ex VAT","Certified VAT","Certified incl VAT","Difference Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        certification.certification_reference,
        invoice.invoice_reference,
        certification.revision_number::text,
        certification.certification_date::text,
        certification.certified_ex_vat::text,
        certification.certified_vat::text,
        certification.certified_incl_vat::text,
        coalesce(certification.difference_reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        certification.actor_exact_role,
        certification.created_at::text
      ) order by certification.certification_date desc,
          certification.created_at desc, certification.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_certifications certification
      join public.v1_accounts_client_invoices invoice
        on invoice.id = certification.invoice_id
      join public.v1_profiles actor
        on actor.auth_user_id = certification.actor_auth_user_id
      where certification.project_id = p_project_id;

    when 'client_receipts' then
      v_columns := '["Payment Reference","Invoice","Entry Kind","Original Reference","PDC Cheque","Payment Date","Payment Method","Amount","Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        payment.payment_reference,
        invoice.invoice_reference,
        payment.entry_kind,
        coalesce(original.payment_reference, ''),
        coalesce(pdc.cheque_number, ''),
        payment.payment_date::text,
        payment.payment_method,
        payment.amount::text,
        coalesce(payment.reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        payment.actor_exact_role,
        payment.created_at::text
      ) order by payment.payment_date desc, payment.created_at desc,
          payment.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_payments payment
      join public.v1_accounts_client_invoices invoice
        on invoice.id = payment.invoice_id
      left join public.v1_accounts_client_payments original
        on original.id = payment.original_payment_id
      left join public.v1_accounts_client_pdcs pdc on pdc.id = payment.pdc_id
      join public.v1_profiles actor
        on actor.auth_user_id = payment.actor_auth_user_id
      where payment.project_id = p_project_id;

    when 'pdc_register' then
      v_columns := '["Cheque","Invoice","Bank","Cheque Date","Received Date","Amount","Status","Replaces Cheque","Replaced By Cheque","Action Required","Last Action Reason","Created By","Created Role","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        pdc.cheque_number,
        invoice.invoice_reference,
        coalesce(pdc.bank_name, ''),
        pdc.cheque_date::text,
        coalesce(pdc.received_date::text, ''),
        pdc.amount::text,
        pdc.status,
        coalesce(replaces.cheque_number, ''),
        coalesce(replaced_by.cheque_number, ''),
        pdc.action_required::text,
        coalesce(pdc.last_action_reason, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        pdc.created_by_exact_role,
        pdc.created_at::text,
        pdc.updated_at::text,
        pdc.record_version::text
      ) order by pdc.cheque_date, pdc.id), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_pdcs pdc
      join public.v1_accounts_client_invoices invoice
        on invoice.id = pdc.invoice_id
      left join public.v1_accounts_client_pdcs replaces
        on replaces.id = pdc.replaces_pdc_id
      left join public.v1_accounts_client_pdcs replaced_by
        on replaced_by.id = pdc.replaced_by_pdc_id
      join public.v1_profiles creator
        on creator.auth_user_id = pdc.created_by_auth_user_id
      where pdc.project_id = p_project_id;

    when 'pdc_events' then
      v_columns := '["Cheque","Invoice","Sequence","From Status","To Status","Action Date","Linked Receipt","Reason","Actor","Role","Occurred At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        pdc.cheque_number,
        invoice.invoice_reference,
        event.sequence_number::text,
        coalesce(event.from_status, ''),
        event.to_status,
        event.action_date::text,
        coalesce(payment.payment_reference, ''),
        coalesce(event.reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        event.actor_exact_role,
        event.occurred_at::text
      ) order by event.occurred_at desc, event.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_pdc_events event
      join public.v1_accounts_client_pdcs pdc on pdc.id = event.pdc_id
      join public.v1_accounts_client_invoices invoice
        on invoice.id = event.invoice_id
      left join public.v1_accounts_client_payments payment
        on payment.id = event.linked_payment_id
      join public.v1_profiles actor
        on actor.auth_user_id = event.actor_auth_user_id
      where event.project_id = p_project_id;

    when 'supplier_bills' then
      v_columns := '["Supplier Invoice","Supplier","Bill Status","Match Status","Payment Status","PO/LPO","Invoice Date","Due Date","Ex VAT","VAT %","VAT Amount","Total incl VAT","Paid","Outstanding","Delivery Reference","Mismatch Reason","Admin Approval Reason","Notes","Approved At","Approved By","Cancelled At","Cancellation Reason","Created By","Created Role","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        bill.supplier_invoice_reference,
        bill.supplier_name_snapshot,
        bill.status,
        public.v1_accounts_supplier_match_status(bill.id),
        public.v1_accounts_supplier_payment_status(bill.id),
        coalesce(bill.po_lpo_reference, ''),
        bill.invoice_date::text,
        bill.due_date::text,
        bill.ex_vat_amount::text,
        bill.vat_rate_percent::text,
        bill.vat_amount::text,
        bill.total_incl_vat::text,
        public.v1_accounts_supplier_paid_amount(bill.id)::text,
        greatest(
          bill.total_incl_vat
          - public.v1_accounts_supplier_paid_amount(bill.id), 0
        )::text,
        coalesce(bill.accepted_delivery_reference, ''),
        coalesce(bill.explicit_mismatch_reason, ''),
        coalesce(bill.approval_admin_exception_reason, ''),
        coalesce(bill.notes, ''),
        coalesce(bill.approved_at::text, ''),
        case when approver.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            approver.display_name, approver.auth_user_id
          ) end,
        coalesce(bill.cancelled_at::text, ''),
        coalesce(bill.cancellation_reason, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        bill.created_by_exact_role,
        bill.created_at::text,
        bill.updated_at::text,
        bill.record_version::text
      ) order by bill.updated_at desc, bill.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_supplier_bills bill
      join public.v1_profiles creator
        on creator.auth_user_id = bill.created_by_auth_user_id
      left join public.v1_profiles approver
        on approver.auth_user_id = bill.approved_by_auth_user_id
      where bill.project_id = p_project_id;

    when 'supplier_payments' then
      v_columns := '["Payment Reference","Supplier Invoice","Supplier","Entry Kind","Original Reference","Payment Date","Payment Method","Amount","Reason","Admin Exception Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        payment.payment_reference,
        bill.supplier_invoice_reference,
        bill.supplier_name_snapshot,
        payment.entry_kind,
        coalesce(original.payment_reference, ''),
        payment.payment_date::text,
        payment.payment_method,
        payment.amount::text,
        coalesce(payment.reason, ''),
        coalesce(payment.admin_exception_reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        payment.actor_exact_role,
        payment.created_at::text
      ) order by payment.payment_date desc, payment.created_at desc,
          payment.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_supplier_payments payment
      join public.v1_accounts_supplier_bills bill
        on bill.id = payment.supplier_bill_id
      left join public.v1_accounts_supplier_payments original
        on original.id = payment.original_payment_id
      join public.v1_profiles actor
        on actor.auth_user_id = payment.actor_auth_user_id
      where payment.project_id = p_project_id;

    when 'accounts_documents' then
      v_columns := '["Document Type","File Name","Classification","Revision","MIME Type","Size Bytes","SHA256","Origin","Source Entity Type","Source Entity ID","Linked Records","Archived","Created At","Uploaded At","Uploaded By","Uploaded Role"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        metadata.document_type,
        version_record.original_file_name,
        document_record.classification,
        version_record.revision_number::text,
        version_record.mime_type,
        version_record.byte_size::text,
        version_record.sha256,
        version_record.origin,
        coalesce(version_record.source_entity_type, ''),
        coalesce(version_record.source_entity_id::text, ''),
        coalesce(links.targets, ''),
        (metadata.archived_at is not null)::text,
        document_record.created_at::text,
        version_record.uploaded_at::text,
        public.v1_safe_profile_display_name(
          uploader.display_name, uploader.auth_user_id
        ),
        version_record.uploaded_by_role
      ) order by version_record.uploaded_at desc, document_record.id), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_document_metadata metadata
      join public.v1_documents document_record
        on document_record.id = metadata.document_id
      join public.v1_document_versions version_record
        on version_record.document_id = document_record.id
      join public.v1_profiles uploader
        on uploader.auth_user_id = version_record.uploaded_by_auth_user_id
      left join lateral (
        select string_agg(
          link.entity_type || ':' || link.entity_id::text, ', '
          order by link.linked_at, link.id
        ) targets
        from public.v1_document_links link
        where link.document_id = document_record.id
          and link.project_id = p_project_id
          and link.removed_at is null
      ) links on true
      where exists (
        select 1
        from public.v1_document_links project_link
        where project_link.document_id = document_record.id
          and project_link.project_id = p_project_id
          and project_link.removed_at is null
      ) and public.v1_document_readable(document_record.id);

    when 'accounts_activity' then
      v_columns := '["Occurred At","Event","Entity Type","Entity ID","Actor","Role","Reason","Idempotency Key","Before","After"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        audit.occurred_at::text,
        audit.event_type,
        audit.entity_type,
        audit.entity_id::text,
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        coalesce(audit.actor_exact_role, audit.actor_role),
        coalesce(audit.reason, ''),
        coalesce(audit.idempotency_key::text, ''),
        coalesce(audit.before_data::text, ''),
        coalesce(audit.after_data::text, '')
      ) order by audit.occurred_at desc, audit.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_audit_events audit
      join public.v1_profiles actor
        on actor.auth_user_id = audit.actor_auth_user_id
      where audit.project_id = p_project_id
        and (
          audit.event_type like 'accounts.%'
          or audit.entity_type like 'accounts_%'
        );
  end case;

  v_result := jsonb_build_object(
    'schema_version', 7,
    'report_kind', p_export_kind,
    'project_id', p_project_id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'currency', 'AED',
    'access_context', v_role,
    'generated_at', clock_timestamp(),
    'generated_by_auth_user_id', v_actor,
    'generated_by_display_name', (
      select public.v1_safe_profile_display_name(
        profile.display_name, profile.auth_user_id
      )
      from public.v1_profiles profile
      where profile.auth_user_id = v_actor
    ),
    'columns', v_columns,
    'rows', coalesce(v_rows, '[]'::jsonb)
  );

  perform public.v1_write_audit_event(
    'accounts.export.generated',
    'accounts_export',
    p_idempotency_key,
    p_project_id,
    null,
    jsonb_build_object(
      'report_kind', p_export_kind,
      'row_count', jsonb_array_length(coalesce(v_rows, '[]'::jsonb))
    ),
    null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_get_accounts_export', p_idempotency_key, v_result
  );
  return v_result;
end;
$function$;

-- Contract parties carry their id, so the bill-to party can be chosen.
CREATE OR REPLACE FUNCTION public.v1_get_project_commercial_setup(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
            'party_id', id,
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
$function$;

-- Overview: claim figures by the Excel rule; 'to come' is invoiced and
-- not yet paid; progress is the current step while a claim is open.
CREATE OR REPLACE FUNCTION public.v1_get_project_accounts_workspace(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_open_claim_ref text;
  v_open_claim_gross numeric := 0;
  v_to_come numeric := 0;
  v_open_claim_status text;
  v_can_prepare boolean := false;
  v_can_confirm boolean := false;
  v_suggestions integer := 0;
  v_building_count integer := 0;
  v_stage_count integer := 0;
  v_invoice_count integer := 0;
  v_latest_invoice_ref text;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_setup_state text;
  v_progress_state text;
  v_invoice_state text;
  v_paid_state text;
  v_steps jsonb;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  v_can_prepare := public.v1_current_user_has_capability('prepare_client_claim', p_project_id);
  v_can_confirm := public.v1_current_user_has_capability('confirm_billing_progress', p_project_id);
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
    select count(distinct project_scope_id), count(distinct stage_key)
      into v_building_count, v_stage_count
    from public.v1_accounts_billing_progress where baseline_revision_id = v_baseline.id;
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - i.retention_snapshot - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled')),
         count(*) filter (where i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any, v_invoice_count
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);
  v_invoice_count := coalesce(v_invoice_count, 0);

  select i.invoice_reference into v_latest_invoice_ref
  from public.v1_accounts_client_invoices i
  where i.project_id = p_project_id and i.status not in ('draft','cancelled')
  order by i.created_at desc limit 1;

  select coalesce(sum(round(public.v1_accounts_claim_exact_gross(c.id), 2)), 0) into v_draft
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  -- Invoiced and not yet paid: the certified amount once certified, else the
  -- invoice total, less retention held and money received.
  select coalesce(sum(greatest(
      case when public.v1_accounts_invoice_certified_incl_vat(i.id) > 0
        then public.v1_accounts_invoice_certified_incl_vat(i.id)
        else i.total_incl_vat_snapshot end
      - i.retention_snapshot - public.v1_accounts_invoice_paid_amount(i.id), 0)), 0)
    into v_to_come
  from public.v1_accounts_client_invoices i
  where i.project_id = p_project_id and i.status not in ('draft', 'returned', 'cancelled');

  -- The claim in hand: a checked claim waiting for its invoice comes first.
  select c.id, c.claim_reference, c.status,
         round(public.v1_accounts_claim_exact_gross(c.id), 2)
    into v_open_claim_id, v_open_claim_ref, v_open_claim_status, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts')
  order by (c.status = 'ready_for_accounts') desc, c.updated_at desc limit 1;

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
    if v_open_claim_status = 'ready_for_accounts' then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_draft',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null and v_can_prepare then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is null and v_contract > v_invoiced and v_can_prepare then
      -- Only someone who can start a claim is asked to start one.
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_can_confirm then
      select count(*) into v_suggestions
      from public.v1_accounts_billing_progress bp
      where bp.baseline_revision_id = v_baseline.id
        and bp.suggested_percent > bp.confirmed_percent;
      if v_suggestions > 0 then
        v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','progress_suggested',
          'action_key','open_claim','target_type','project','target_id',p_project_id,
          'params', jsonb_build_object('count', v_suggestions)));
      end if;
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

  v_setup_state := case when v_baseline.id is not null then 'done' else 'current' end;
  v_progress_state := case when v_open_claim_id is not null then 'current'
    when v_progress_any or v_invoice_any then 'done'
    when v_baseline.id is not null then 'current' else '' end;
  v_invoice_state := case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end;
  v_paid_state := case when v_invoice_any and v_to_come <= 0 then 'done' when v_invoice_any then 'current' else '' end;

  -- Steps. Monetary figures (`detail`) only with commercial access; the
  -- state/label shape is identical for every actor.
  if v_can_values then
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state,'detail',
        jsonb_build_object('contract_value', v_contract::text,
          'building_count', v_building_count, 'stage_count', v_stage_count)),
      jsonb_build_object('key','progress','state',v_progress_state,'detail',
        case when v_open_claim_id is not null
          then jsonb_build_object('claim_reference', v_open_claim_ref, 'claim_gross', v_open_claim_gross::text)
          else null end),
      jsonb_build_object('key','invoice','state',v_invoice_state,'detail',
        case when v_invoice_count > 0
          then jsonb_build_object('issued_count', v_invoice_count, 'latest_reference', v_latest_invoice_ref)
          else null end),
      jsonb_build_object('key','paid','state',v_paid_state,'detail',
        jsonb_build_object('received', v_received::text,
          'to_come', v_to_come::text)));
  else
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state),
      jsonb_build_object('key','progress','state',v_progress_state),
      jsonb_build_object('key','invoice','state',v_invoice_state),
      jsonb_build_object('key','paid','state',v_paid_state));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', v_steps,
    'badges', jsonb_build_object(
      'claims_draft', coalesce(v_open_claim_status = 'draft', false),
      'supplier_count', case when v_can_supplier then v_bills_overdue else null end),
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
$function$;

-- ---------------------------------------------------------------------------
-- The invoice document, laid out as the signed Yorks invoices (schema 3).
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
as $function$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_invoice public.v1_accounts_client_invoices%rowtype;
  v_rate numeric;
  v_this_exact numeric;
  v_prev_exact numeric;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_total numeric(20,2);
  v_prev_ex numeric(20,2); v_prev_vat numeric(20,2); v_prev_total numeric(20,2);
  v_cum_ex numeric(20,2); v_cum_vat numeric(20,2); v_cum_total numeric(20,2);
  v_con_ex numeric(20,2); v_con_vat numeric(20,2); v_con_total numeric(20,2);
  v_lines jsonb;
  v_company jsonb;
  v_override jsonb;
  v_bill_to jsonb;
  v_summary_stages jsonb;
  v_buildings jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  v_rate := coalesce(v_baseline.vat_rate_percent, 0);

  -- Once the claim is invoiced, the invoice's frozen amounts are the document's.
  select * into v_invoice from public.v1_accounts_client_invoices i
  where i.claim_id = p_claim_id and i.status <> 'cancelled'
  order by i.created_at desc limit 1;

  v_this_exact := public.v1_accounts_claim_exact_gross(p_claim_id);
  if v_invoice.id is not null then
    v_ex_vat := v_invoice.claimed_ex_vat;
    v_vat := v_invoice.vat_amount_snapshot;
    v_total := v_invoice.total_incl_vat_snapshot;
  else
    select x.ex_vat, x.vat, x.total into v_ex_vat, v_vat, v_total
    from public.v1_accounts_excel_amounts(v_this_exact, v_rate) x;
  end if;

  -- Till previous: every claim invoiced before this one, on every building and
  -- stage. A revision's predecessor is the same claim, so it is not previous.
  select coalesce(sum(coalesce(l.claimed_amount_exact, l.claimed_amount)), 0)
  into v_prev_exact
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id
    and c.id <> p_claim_id
    and c.id is distinct from v_claim.supersedes_claim_id
    and c.status = 'invoiced'
    and (c.created_at, c.id) < (v_claim.created_at, v_claim.id);

  select x.ex_vat, x.vat, x.total into v_prev_ex, v_prev_vat, v_prev_total
  from public.v1_accounts_excel_amounts(v_prev_exact, v_rate) x;
  select x.ex_vat, x.vat, x.total into v_cum_ex, v_cum_vat, v_cum_total
  from public.v1_accounts_excel_amounts(v_prev_exact + v_this_exact, v_rate) x;
  select x.ex_vat, x.vat, x.total into v_con_ex, v_con_vat, v_con_total
  from public.v1_accounts_excel_amounts(v_baseline.contract_value, v_rate) x;

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

  -- Full building x stage grid for the claim's baseline: contract value, till
  -- previous (all earlier invoiced claims) and this invoice, per cell.
  -- Amounts stay exact through the grid and are rounded once at each level
  -- (cell, stage, building), as the workbook does.
  with prior as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    join public.v1_accounts_client_claims c on c.id = l.claim_id
    where c.project_id = p_project_id
      and c.id <> p_claim_id
      and c.id is distinct from v_claim.supersedes_claim_id
      and c.status = 'invoiced'
      and (c.created_at, c.id) < (v_claim.created_at, v_claim.id)
    group by l.project_scope_id, l.stage_key
  ), this_claim as (
    select l.project_scope_id, l.stage_key,
      sum(coalesce(l.claimed_amount_exact, l.claimed_amount)) as amount
    from public.v1_accounts_client_claim_lines l
    where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ), grid as (
    select
      bp.project_scope_id,
      scope.name as building_name,
      ba.allocation_percent as building_pct,
      bp.stage_key,
      sa.stage_name,
      sa.display_order,
      sa.allocation_percent as stage_pct,
      public.v1_accounts_stage_value(bp.id)::numeric(20,2) as stage_value,
      coalesce(pr.amount, 0) as prev_amt,
      coalesce(tc.amount, 0) as this_amt
    from public.v1_accounts_billing_progress bp
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    join public.v1_accounts_baseline_building_allocations ba
      on ba.baseline_revision_id = bp.baseline_revision_id
      and ba.project_scope_id = bp.project_scope_id
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id
      and sa.stage_key = bp.stage_key
    left join prior pr
      on pr.project_scope_id = bp.project_scope_id and pr.stage_key = bp.stage_key
    left join this_claim tc
      on tc.project_scope_id = bp.project_scope_id and tc.stage_key = bp.stage_key
    where bp.baseline_revision_id = v_claim.baseline_revision_id
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'stage_key', s.stage_key,
          'stage_label', s.stage_name,
          'contract_percent', s.stage_pct::text,
          'contract_amount', s.cval::text,
          'previous_amount', round(s.prev, 2)::text,
          'this_amount', round(s.this, 2)::text,
          'total_amount', round(s.prev + s.this, 2)::text
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
          'previous_amount', round(b.prev, 2)::text,
          'this_amount', round(b.this, 2)::text,
          'total_amount', round(b.prev + b.this, 2)::text,
          'stages', b.stages
        ) order by b.building_name), '[]'::jsonb)
      from (
        select g.project_scope_id, g.building_name, g.building_pct,
          sum(g.stage_value) as bval, sum(g.prev_amt) as prev, sum(g.this_amt) as this,
          jsonb_agg(jsonb_build_object(
            'stage_key', g.stage_key,
            'stage_label', g.stage_name,
            'stage_value', g.stage_value::text,
            'previous_amount', round(g.prev_amt, 2)::text,
            'this_amount', round(g.this_amt, 2)::text,
            'total_amount', round(g.prev_amt + g.this_amt, 2)::text
          ) order by g.display_order) as stages
        from grid g
        group by g.project_scope_id, g.building_name, g.building_pct
      ) b
    )
  into v_summary_stages, v_buildings;

  -- Who is billed: the chosen party, else the main contractor, else the client.
  -- A chosen party that no longer exists (project parties are replaced when a
  -- project is edited) falls back the same way.
  select jsonb_build_object('party_id', pp.id, 'kind', pp.party_kind,
      'name', pp.party_name, 'address', pp.address)
  into v_bill_to
  from public.v1_project_parties pp
  where pp.project_id = p_project_id
    and (pp.id = v_settings.bill_to_party_id
      or pp.party_kind in ('main_contractor', 'client'))
  order by (pp.id = v_settings.bill_to_party_id) desc nulls last,
    (pp.party_kind = 'main_contractor') desc, pp.party_order
  limit 1;

  -- Published company letterhead/bank block, frozen with the invoice. A
  -- historical import may set the letterhead/bank the paper copy carried.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';
  begin
    v_override := nullif(current_setting('yorks.invoice_company_override', true), '')::jsonb;
  exception when others then
    v_override := null;
  end;
  if jsonb_typeof(v_override) = 'object' then
    v_company := v_company || v_override;
  end if;

  return jsonb_build_object(
    'schema_version', 3,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref,
      'name', v_project.name, 'contract_reference', v_project.job_contract_reference),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'bill_to', v_bill_to,
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', coalesce(v_profile.contract_number, v_project.job_contract_reference)),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_rate::text, 'vat', v_vat::text,
      'total_incl_vat', v_total::text),
    'contract_value', v_baseline.contract_value::text,
    'summary', jsonb_build_object(
      'contract_total', v_baseline.contract_value::text,
      'previous_total', v_prev_ex::text,
      'this_total', v_ex_vat::text,
      'total_total', v_cum_ex::text,
      'contract_vat', v_con_vat::text,
      'contract_grand', v_con_total::text,
      'previous_vat', v_prev_vat::text,
      'previous_grand', v_prev_total::text,
      'this_vat', v_vat::text,
      'this_grand', v_total::text,
      'total_vat', v_cum_vat::text,
      'total_grand', v_cum_total::text,
      'stages', coalesce(v_summary_stages, '[]'::jsonb)
    ),
    'buildings', coalesce(v_buildings, '[]'::jsonb),
    'lines', v_lines
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Activity with business dates and references (schema 7).
-- ---------------------------------------------------------------------------

-- A claim's number (#01, #02 …): its place among the project's live claims,
-- oldest first. A revision keeps its predecessor's number.
create or replace function public.v1_accounts_claim_number(p_claim_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with recursive origin as (
    select c.id, c.supersedes_claim_id from public.v1_accounts_client_claims c where c.id = p_claim_id
    union all
    select c.id, c.supersedes_claim_id
    from public.v1_accounts_client_claims c join origin o on c.id = o.supersedes_claim_id
  ), root as (
    select c.* from public.v1_accounts_client_claims c
    where c.id = (select o.id from origin o where o.supersedes_claim_id is null limit 1)
  )
  -- Original claims that are live, or were replaced by a revision, count; a
  -- claim simply cancelled does not (it still shows its own place).
  select count(*)::integer
  from public.v1_accounts_client_claims c, root r
  where c.project_id = r.project_id
    and c.supersedes_claim_id is null
    and (c.status <> 'cancelled' or c.id = r.id
      or coalesce(c.cancellation_reason, '') like 'Superseded by %')
    and (c.created_at, c.id) <= (r.created_at, r.id);
$$;

-- What an audit entry is about, read from the record it touched: the date it
-- happened on and the references that name it. Money only with values.
create or replace function public.v1_accounts_activity_context(
  p_event_type text,
  p_entity_id uuid,
  p_idempotency_key uuid,
  p_after_data jsonb,
  p_can_values boolean,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb := null;
  v_claim_id uuid;
begin
  if p_event_type in ('accounts.client_certification.recorded', 'accounts.client_certification.corrected') then
    select jsonb_build_object(
        'business_date', c.certification_date,
        'certification_reference', c.certification_reference,
        'invoice_reference', i.invoice_reference,
        'claim_number', public.v1_accounts_claim_number(i.claim_id),
        'bill_to', d.document_snapshot -> 'bill_to' ->> 'name')
      || case when p_can_values then jsonb_build_object(
          'certified_ex_vat', c.certified_ex_vat::text,
          'invoiced_ex_vat', i.claimed_ex_vat::text) else '{}'::jsonb end
    into v_ctx
    from public.v1_accounts_client_certifications c
    join public.v1_accounts_client_invoices i on i.id = c.invoice_id
    left join public.v1_accounts_client_invoice_documents d on d.invoice_id = i.id
    where c.id = p_entity_id or c.idempotency_key = p_idempotency_key
    order by (c.id = p_entity_id) desc limit 1;
  elsif p_event_type like 'accounts.client_pdc.%' then
    select jsonb_build_object(
        -- The day the cheque moved (received, deposited, cleared …); a cheque
        -- added already in hand dates from when it was received.
        'business_date', case when p_event_type = 'accounts.client_pdc.created'
          then p.received_date else coalesce(ev.action_date, p.received_date) end,
        'cheque_number', p.cheque_number,
        'cheque_date', p.cheque_date,
        'bank_name', p.bank_name,
        'to_status', coalesce(ev.to_status, p.status),
        'invoice_reference', i.invoice_reference)
      || case when p_can_values then jsonb_build_object('amount', p.amount::text) else '{}'::jsonb end
    into v_ctx
    from public.v1_accounts_client_pdcs p
    join public.v1_accounts_client_invoices i on i.id = p.invoice_id
    left join public.v1_accounts_client_pdc_events ev
      on ev.id = nullif(p_after_data ->> 'event_id', '')::uuid
    where p.id = coalesce(nullif(p_after_data ->> 'pdc_id', '')::uuid, p_entity_id)
    limit 1;
  elsif p_event_type like 'accounts.client_payment.%' then
    select jsonb_build_object(
        'business_date', pay.payment_date,
        'payment_method', pay.payment_method,
        'payment_reference', pay.payment_reference,
        'invoice_reference', i.invoice_reference)
      || case when p_can_values then jsonb_build_object('amount', pay.amount::text) else '{}'::jsonb end
    into v_ctx
    from public.v1_accounts_client_payments pay
    join public.v1_accounts_client_invoices i on i.id = pay.invoice_id
    where pay.id = p_entity_id or pay.idempotency_key = p_idempotency_key
    order by (pay.id = p_entity_id) desc limit 1;
  elsif p_event_type like 'accounts.client_invoice.%' then
    select jsonb_build_object(
        'business_date', coalesce(nullif(d.document_snapshot ->> 'invoice_date', '')::date,
          i.submission_date, i.created_at::date),
        'invoice_reference', i.invoice_reference,
        'invoice_date', nullif(d.document_snapshot ->> 'invoice_date', ''),
        'submission_date', i.submission_date,
        'claim_number', public.v1_accounts_claim_number(i.claim_id),
        'supersedes_reference', prev.invoice_reference,
        'bill_to', d.document_snapshot -> 'bill_to' ->> 'name')
      || case when p_can_values then jsonb_build_object(
          'claimed_ex_vat', i.claimed_ex_vat::text,
          'total_incl_vat', i.total_incl_vat_snapshot::text) else '{}'::jsonb end
    into v_ctx
    from public.v1_accounts_client_invoices i
    left join public.v1_accounts_client_invoice_documents d on d.invoice_id = i.id
    left join public.v1_accounts_client_invoices prev on prev.id = i.supersedes_invoice_id
    where i.id = p_entity_id;
  elsif p_event_type like 'accounts.client_claim.%' then
    select jsonb_build_object(
        'business_date', coalesce(c.claim_period_end, c.created_at::date),
        'claim_number', public.v1_accounts_claim_number(c.id),
        'period_start', c.claim_period_start,
        'period_end', c.claim_period_end,
        'stages', (select coalesce(jsonb_agg(distinct sa.stage_name), '[]'::jsonb)
          from public.v1_accounts_client_claim_lines l
          join public.v1_accounts_baseline_stage_allocations sa
            on sa.baseline_revision_id = l.baseline_revision_id and sa.stage_key = l.stage_key
          where l.claim_id = c.id))
      || case when p_can_values then jsonb_build_object(
          'claimed_ex_vat', round(public.v1_accounts_claim_exact_gross(c.id), 2)::text)
        else '{}'::jsonb end
    into v_ctx
    from public.v1_accounts_client_claims c
    where c.id = p_entity_id;
  elsif p_event_type in ('accounts_progress_confirmed', 'accounts.progress.imported') then
    -- Progress saved with a claim (the workbench, or a historical import, saves
    -- both together) takes the date of the claim that carried it.
    select c.id into v_claim_id
    from public.v1_accounts_client_claim_lines l
    join public.v1_accounts_client_claims c on c.id = l.claim_id
    where l.progress_entry_id = p_entity_id
      and c.status <> 'cancelled'
      and c.created_at >= p_occurred_at
      and c.created_at < p_occurred_at + interval '10 minutes'
    order by c.created_at limit 1;
    if v_claim_id is not null then
      select jsonb_build_object(
          'business_date', coalesce(c.claim_period_end, c.created_at::date),
          'claim_number', public.v1_accounts_claim_number(c.id))
      into v_ctx from public.v1_accounts_client_claims c where c.id = v_claim_id;
    end if;
  end if;
  return v_ctx;
end;
$$;

revoke all on function public.v1_accounts_claim_number(uuid) from public, anon, authenticated;
revoke all on function public.v1_accounts_activity_context(text, uuid, uuid, jsonb, boolean, timestamptz)
  from public, anon, authenticated;

create or replace function public.v1_get_accounts_activity(
  p_project_id uuid,
  p_entity_type text default null,
  p_action text default null,
  p_actor_auth_user_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_can_values boolean;
  v_can_supplier boolean;
  v_total integer;
  v_entries jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id,'view_project_accounts');
  if p_limit not between 1 and 100 or p_offset<0 or (p_from is not null and p_to is not null and p_from>p_to) then
    raise exception 'R39_ACCOUNTS_ACTIVITY_FILTER_INVALID' using errcode='22023';
  end if;
  v_can_values:=public.v1_current_user_has_capability(
    'view_project_commercial_values',p_project_id
  );
  v_can_supplier:=public.v1_current_user_has_capability('view_supplier_costs',p_project_id);
  with filtered as materialized (
    select audit.*,profile.display_name,
      public.v1_accounts_activity_context(audit.event_type, audit.entity_id,
        audit.idempotency_key, audit.after_data, v_can_values, audit.occurred_at) as ctx
    from public.v1_audit_events audit
    join public.v1_profiles profile on profile.auth_user_id=audit.actor_auth_user_id
    where audit.project_id=p_project_id
      and (audit.event_type like 'accounts.%' or audit.entity_type like 'accounts_%')
      and (v_can_supplier or audit.entity_type not in ('accounts_supplier_bill','accounts_supplier_payment'))
      and (p_entity_type is null or audit.entity_type=p_entity_type)
      and (p_action is null or audit.event_type=p_action)
      and (p_actor_auth_user_id is null or audit.actor_auth_user_id=p_actor_auth_user_id)
      and (p_from is null or audit.occurred_at>=p_from)
      and (p_to is null or audit.occurred_at<=p_to)
  ), dated as (
    select f.*, coalesce(nullif(f.ctx ->> 'business_date', '')::date,
      (f.occurred_at at time zone 'Asia/Dubai')::date) as business_date
    from filtered f
  ), page as (
    select * from dated order by business_date desc, occurred_at desc, id desc
    limit p_limit offset p_offset
  )
  select (select count(*) from filtered),coalesce(jsonb_agg(jsonb_build_object(
    'id',page.id,'event_type',page.event_type,'entity_type',page.entity_type,
    'entity_id',page.entity_id,'project_id',page.project_id,
    'actor_auth_user_id',page.actor_auth_user_id,
    'actor_display_name',public.v1_safe_profile_display_name(page.display_name,page.actor_auth_user_id),
    'actor_exact_role',coalesce(page.actor_exact_role,page.actor_role),
    'occurred_at',page.occurred_at,'reason',page.reason,
    'idempotency_key',page.idempotency_key,
    'business_date',page.business_date,
    'context',page.ctx,
    'before_data',case when v_can_values then page.before_data else null end,
    'after_data',case when v_can_values then page.after_data else null end
  ) order by page.business_date desc,page.occurred_at desc,page.id desc),'[]'::jsonb)
  into v_total,v_entries from page;
  return jsonb_build_object(
    'schema_version',7,'project_id',p_project_id,'total',v_total,
    'limit',p_limit,'offset',p_offset,'entries',v_entries
  );
end;
$function$;

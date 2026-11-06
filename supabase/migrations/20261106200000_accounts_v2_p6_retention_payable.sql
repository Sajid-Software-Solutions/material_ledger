-- R39 Accounts Workspace V2 — P6 (part f): retention hold-back on payable
--
-- Implements PRODUCT_DECISIONS.md section 28 (RESOLVED 2026-11-06): retention
-- reduces what the client still owes. Owner choice: only invoices issued AFTER
-- the rule is set are affected, via a per-invoice `retention_snapshot` frozen at
-- issue from the profile's retention %. Existing invoices keep retention 0, so
-- their due is unchanged. Release of retention is out of scope.
--
-- Invariant: still_due = max(certified_incl_vat - retention_snapshot - paid, 0),
-- everywhere, through the per-invoice snapshot. The payment cap uses the same
-- reduced due. Additive: ADD COLUMN IF NOT EXISTS (default 0) + CREATE OR
-- REPLACE of the receivables readers, the payment command and the issue command.
-- The Accountant office (t05) and exports (t06) still read certified - paid; they
-- are out of the V2 scope and, with retention 0 on existing invoices, show no
-- regression — they move to the retention figure when the office is next revised.

alter table public.v1_accounts_client_invoices
  add column if not exists retention_snapshot numeric(20,2) not null default 0
  check (retention_snapshot >= 0);

-- The frozen retention held back on an invoice (0 for pre-rule invoices).
create or replace function public.v1_accounts_invoice_retention(p_invoice_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select retention_snapshot
    from public.v1_accounts_client_invoices where id = p_invoice_id), 0);
$$;

-- Invoice snapshot: add retention and reduce still_due by it.
create or replace function public.v1_accounts_invoice_snapshot(
  p_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

-- Record payment: the cap and the returned still_due use the retention-reduced due.
create or replace function public.v1_record_client_payment(
  p_project_id uuid,p_invoice_id uuid,p_expected_version integer,p_payment_date date,
  p_payment_method text,p_payment_reference text,p_amount text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_amount numeric;v_certified numeric;v_paid numeric;v_retention numeric;
  v_payment_id uuid:=gen_random_uuid();v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_payment');
  if p_payment_date is null or nullif(btrim(p_payment_method),'') is null or nullif(btrim(p_payment_reference),'') is null then
    raise exception 'R39_ACCOUNTS_PAYMENT_IDENTITY_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_amount);if v_amount<=0 then raise exception 'R39_ACCOUNTS_INVALID_PAYMENT_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'payment_date',p_payment_date,'payment_method',btrim(p_payment_method),'payment_reference',btrim(p_payment_reference),
    'amount',v_amount::text,'reason',nullif(btrim(p_reason),''));
  v_existing:=public.v1_idempotency_get_or_claim('v1_record_client_payment',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.status in ('draft','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_PAYABLE' using errcode='55000';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  v_certified:=public.v1_accounts_invoice_certified_incl_vat(p_invoice_id);v_paid:=public.v1_accounts_invoice_paid_amount(p_invoice_id);
  v_retention:=v_invoice.retention_snapshot;
  if v_certified<=0 or v_paid+v_amount>v_certified-v_retention then raise exception 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED' using errcode='23514';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,payment_date,payment_method,payment_reference,amount,reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_payment_id,p_project_id,p_invoice_id,'receipt',p_payment_date,btrim(p_payment_method),btrim(p_payment_reference),v_amount,
    nullif(btrim(p_reason),''),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_payment.recorded','accounts_client_payment',v_payment_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),nullif(btrim(p_reason),''),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_payment_id,'payment_id',v_payment_id,
    'invoice_id',p_invoice_id,'invoice_record_version',p_expected_version+1,'status',v_status,'amount',v_amount::text,
    'amount_paid_till_date',(v_paid+v_amount)::text,'still_due',greatest(v_certified-v_retention-v_paid-v_amount,0)::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_record_client_payment',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE' using errcode='23505';
end;
$$;

-- Invoice list: still_due subtracts retention.
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
    'submission_date',submission_date,'due_date',due_date,'due_state',due_state,'record_version',record_version,'updated_at',updated_at)
    order by updated_at desc,id desc),'[]'::jsonb),min(updated_at),(array_agg(id order by updated_at asc,id asc))[1]
  into v_rows,v_next_time,v_next_id from page;
  return jsonb_build_object('schema_version',3,'project_id',p_project_id,'invoices',v_rows,
    'next_cursor',case when jsonb_array_length(v_rows)=v_limit then jsonb_build_object('before_updated_at',v_next_time,'before_id',v_next_id) else null end,
    'capabilities',public.v1_accounts_receivables_capabilities(p_project_id),
    'commands',public.v1_accounts_receivables_commands(p_project_id));
end;
$$;

-- Issue: freeze the retention held back on the new invoice from the profile %.
-- NOTE: this recreation preserves the full supersession behaviour added by
-- 20261105120000_accounts_v2_p3_invoice_revise.sql (R.n numbering + predecessor
-- retirement). It ONLY adds the retention freeze after submit. Keep the two in
-- sync if the revise migration's issue body changes.
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

  -- Freeze retention held back (section 28): retention% x claim gross ex-VAT.
  update public.v1_accounts_client_invoices i
  set retention_snapshot = round(i.claimed_ex_vat * coalesce(
      (select retention_percent from public.v1_accounts_project_commercial_profiles
       where project_id = p_project_id), 0) / 100, 2)
  where i.id = v_invoice_id;

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
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date,
    (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'revision_number', v_rev, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid) to authenticated;
revoke all on function public.v1_accounts_invoice_retention(uuid) from public, anon;
grant execute on function public.v1_accounts_invoice_retention(uuid) to authenticated, service_role;

-- Summary workspace: the 'client still owes' (outstanding) KPI and the
-- paid-step state subtract retention per invoice, matching the Invoices tab.
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
  v_open_claim_ref text;
  v_open_claim_gross numeric := 0;
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

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  select c.id, c.claim_reference,
         coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_ref, v_open_claim_gross
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

  v_setup_state := case when v_baseline.id is not null then 'done' else 'current' end;
  v_progress_state := case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end;
  v_invoice_state := case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end;
  v_paid_state := case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end;

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
          'to_come', greatest(round(v_contract * v_vatf, 2) - v_received, 0)::text)));
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
      'claims_draft', v_open_claim_id is not null,
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
$$;

revoke all on function public.v1_get_project_accounts_workspace(uuid) from public, anon;
grant execute on function public.v1_get_project_accounts_workspace(uuid) to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Section 28 R-5: the retention hold-back reduces outstanding/Still-Due in the
-- Accountant-office portfolio, the project overview, the office register and
-- the register exports too (not only the per-project Invoices tab). Each
-- function below is the latest committed body with the retention term added to
-- its due math; everything else is unchanged. CREATE OR REPLACE preserves the
-- existing grants. Default retention_snapshot = 0 keeps every current figure.
-- ---------------------------------------------------------------------------

create or replace function public.v1_get_accounts_portfolio(
  p_project_id uuid default null,
  p_client text default null,
  p_commercial_state text default null,
  p_due_state text default null,
  p_payment_state text default null,
  p_pdc_state text default null,
  p_supplier_match_state text default null,
  p_search text default null,
  p_before_activity_at timestamptz default null,
  p_before_project_id uuid default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_permission_exact_role(auth.uid());
  v_rows jsonb;
  v_totals jsonb;
  v_actions jsonb;
  v_next jsonb;
  v_authorized_count integer;
  v_filtered_count integer;
begin
  if v_actor is null or not public.v1_accounts_portfolio_role_allowed() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_limit < 1 or p_limit > 100
    or (p_before_activity_at is null) <> (p_before_project_id is null)
    or (p_commercial_state is not null and p_commercial_state not in (
      'active', 'not_initialized', 'action_required'
    ))
    or (p_due_state is not null and p_due_state not in (
      'current', 'due_soon', 'overdue'
    ))
    or (p_payment_state is not null and p_payment_state not in (
      'unpaid', 'partially_paid', 'paid'
    ))
    or (p_pdc_state is not null and p_pdc_state not in (
      'expected', 'received', 'deposited', 'cleared', 'returned',
      'bounced', 'replaced', 'cancelled'
    ))
    or (p_supplier_match_state is not null
      and p_supplier_match_state not in ('blocked', 'review', 'matched')) then
    raise exception 'R39_ACCOUNTS_INVALID_PORTFOLIO_FILTER'
      using errcode = '22023';
  end if;

  with authorized as materialized (
    select project.id, project.project_ref, project.name, project.project_site,
      project.state, project.updated_at as project_updated_at,
      client.party_name as client_name,
      public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      ) as can_view_values,
      public.v1_current_user_has_capability(
        'view_supplier_costs', project.id
      ) as can_view_supplier_costs
    from public.v1_projects project
    left join lateral (
      select party.party_name
      from public.v1_project_parties party
      where party.project_id = project.id and party.party_kind = 'client'
      order by party.created_at, party.id
      limit 1
    ) client on true
    where public.v1_current_user_has_capability(
      'view_project_accounts', project.id
    )
      and public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      )
      and (p_project_id is null or project.id = p_project_id)
  ), facts as materialized (
    select authorized.*,
      baseline.id as baseline_revision_id,
      baseline.revision_number as baseline_revision_number,
      baseline.currency_code,
      coalesce(baseline.contract_value, 0) as contract_value,
      coalesce(progress.confirmed_eligible, 0) as confirmed_eligible,
      greatest(
        coalesce(progress.confirmed_eligible, 0)
          - coalesce(claims.claimed_reserved, 0), 0
      ) as available_to_claim,
      coalesce(invoices.claimed, 0) as claimed,
      coalesce(invoices.certified, 0) as certified,
      coalesce(invoices.paid, 0) as paid,
      coalesce(invoices.retention, 0) as retention,
      greatest(coalesce(invoices.certified, 0)
        - coalesce(invoices.retention, 0)
        - coalesce(invoices.paid, 0), 0) as still_due,
      coalesce(invoices.pdc_exposure, 0) as pdc_exposure,
      coalesce(progress.confirmed_percent, 0) as confirmed_percent,
      coalesce(invoices.overdue_count, 0) as overdue_count,
      coalesce(invoices.due_soon_count, 0) as due_soon_count,
      coalesce(invoices.open_invoice_count, 0) as open_invoice_count,
      coalesce(invoices.returned_invoice_count, 0)
        + coalesce(claims.returned_claim_count, 0) as returned_count,
      coalesce(pdcs.action_pdc_count, 0) as action_pdc_count,
      coalesce(suppliers.review_count, 0) as supplier_review_count,
      coalesce(suppliers.open_amount, 0) as supplier_open_amount,
      greatest(
        authorized.project_updated_at,
        coalesce(baseline.created_at, '-infinity'::timestamptz),
        coalesce(progress.latest_at, '-infinity'::timestamptz),
        coalesce(claims.latest_at, '-infinity'::timestamptz),
        coalesce(invoices.latest_at, '-infinity'::timestamptz),
        coalesce(pdcs.latest_at, '-infinity'::timestamptz),
        coalesce(suppliers.latest_at, '-infinity'::timestamptz)
      ) as latest_activity_at,
      case
        when coalesce(invoices.overdue_count, 0) > 0 then 'overdue'
        when coalesce(invoices.due_soon_count, 0) > 0 then 'due_soon'
        else 'current'
      end as due_state,
      case
        when coalesce(invoices.certified, 0) > 0
          and coalesce(invoices.paid, 0)
            >= invoices.certified - coalesce(invoices.retention, 0) then 'paid'
        when coalesce(invoices.paid, 0) > 0 then 'partially_paid'
        else 'unpaid'
      end as payment_state
    from authorized
    left join public.v1_accounts_project_commercial_profiles profile
      on profile.project_id = authorized.id
    left join public.v1_accounts_baseline_revisions baseline
      on baseline.id = profile.current_baseline_revision_id
    left join lateral (
      select
        coalesce(sum(round(
          baseline.contract_value
          * building.allocation_percent / 100
          * stage.allocation_percent / 100
          * entry.confirmed_percent / 100, 2
        )), 0) as confirmed_eligible,
        case when coalesce(sum(
          building.allocation_percent * stage.allocation_percent
        ), 0) = 0 then 0 else round(
          sum(building.allocation_percent * stage.allocation_percent
            * entry.confirmed_percent)
          / sum(building.allocation_percent * stage.allocation_percent), 2
        ) end as confirmed_percent,
        max(entry.updated_at) as latest_at
      from public.v1_accounts_billing_progress entry
      join public.v1_accounts_baseline_building_allocations building
        on building.id = entry.building_allocation_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = entry.stage_allocation_id
      where entry.project_id = authorized.id
        and entry.baseline_revision_id = baseline.id
        and entry.review_status <> 'returned'
    ) progress on true
    left join lateral (
      select coalesce(sum(case when claim.status <> 'cancelled'
          then line.claimed_amount else 0 end), 0) as claimed_reserved,
        count(*) filter (where claim.status = 'draft'
          and claim.is_stale) as returned_claim_count,
        max(claim.updated_at) as latest_at
      from public.v1_accounts_client_claims claim
      left join public.v1_accounts_client_claim_lines line
        on line.claim_id = claim.id
      where claim.project_id = authorized.id
    ) claims on true
    left join lateral (
      select coalesce(sum(case when invoice.status not in (
          'draft', 'returned', 'cancelled'
        ) then invoice.claimed_ex_vat else 0 end), 0) as claimed,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          else 0 end), 0) as certified,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_paid_amount(invoice.id)
          else 0 end), 0) as paid,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_retention(invoice.id)
          else 0 end), 0) as retention,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_pdc_exposure(invoice.id)
          else 0 end), 0) as pdc_exposure,
        count(*) filter (where invoice.due_date < current_date
          and invoice.status not in ('draft','returned','cancelled','paid'))
          as overdue_count,
        count(*) filter (where invoice.due_date >= current_date
          and invoice.due_date <= current_date
            + invoice.reminder_lead_days_snapshot
          and invoice.status not in ('draft','returned','cancelled','paid'))
          as due_soon_count,
        count(*) filter (where invoice.status not in ('cancelled','paid'))
          as open_invoice_count,
        count(*) filter (where invoice.status = 'returned')
          as returned_invoice_count,
        max(invoice.updated_at) as latest_at
      from public.v1_accounts_client_invoices invoice
      where invoice.project_id = authorized.id
    ) invoices on true
    left join lateral (
      select count(*) filter (where pdc.action_required) as action_pdc_count,
        max(pdc.updated_at) as latest_at
      from public.v1_accounts_client_pdcs pdc
      where pdc.project_id = authorized.id
    ) pdcs on true
    left join lateral (
      select count(*) filter (where bill.status <> 'cancelled'
          and public.v1_accounts_supplier_match_status(bill.id) <> 'matched')
          as review_count,
        coalesce(sum(case when bill.status <> 'cancelled' then greatest(
          bill.total_incl_vat
            - public.v1_accounts_supplier_paid_amount(bill.id), 0
        ) else 0 end), 0) as open_amount,
        max(bill.updated_at) as latest_at
      from public.v1_accounts_supplier_bills bill
      where bill.project_id = authorized.id
        and authorized.can_view_supplier_costs
    ) suppliers on true
  ), matched as materialized (
    select facts.* from facts
    where (p_client is null or facts.client_name ilike '%'||btrim(p_client)||'%')
      and (p_search is null or btrim(p_search) = ''
        or facts.project_ref ilike '%'||btrim(p_search)||'%'
        or facts.name ilike '%'||btrim(p_search)||'%'
        or coalesce(facts.client_name, '') ilike '%'||btrim(p_search)||'%')
      and (p_commercial_state is null or case p_commercial_state
        when 'not_initialized' then facts.baseline_revision_id is null
        when 'active' then facts.baseline_revision_id is not null
          and facts.overdue_count + facts.due_soon_count + facts.returned_count
            + facts.action_pdc_count + facts.supplier_review_count = 0
        when 'action_required' then facts.overdue_count + facts.due_soon_count
          + facts.returned_count + facts.action_pdc_count
          + facts.supplier_review_count > 0 end)
      and (p_due_state is null or facts.due_state = p_due_state)
      and (p_payment_state is null or facts.payment_state = p_payment_state)
      and (p_pdc_state is null or exists (
        select 1 from public.v1_accounts_client_pdcs pdc
        where pdc.project_id = facts.id and pdc.status = p_pdc_state
      ))
      and (p_supplier_match_state is null or (
        facts.can_view_supplier_costs and exists (
          select 1 from public.v1_accounts_supplier_bills bill
          where bill.project_id = facts.id and bill.status <> 'cancelled'
            and public.v1_accounts_supplier_match_status(bill.id)
              = p_supplier_match_state
        )
      ))
  ), filtered as materialized (
    select matched.* from matched
    where p_before_activity_at is null
      or (matched.latest_activity_at, matched.id)
        < (p_before_activity_at, p_before_project_id)
  ), page as materialized (
    select * from filtered
    order by latest_activity_at desc, id desc limit p_limit + 1
  )
  select
    (select count(*) from authorized),
    (select count(*) from matched),
    coalesce((select jsonb_agg(
      jsonb_build_object(
        'project_id', page.id,
        'project_reference', page.project_ref,
        'project_name', page.name,
        'project_site', page.project_site,
        'project_state', page.state,
        'client_name', page.client_name,
        'baseline_revision_number', page.baseline_revision_number,
        'currency_code', page.currency_code,
        'contract_baseline', page.contract_value::text,
        'confirmed_eligible', page.confirmed_eligible::text,
        'available_to_claim', page.available_to_claim::text,
        'claimed', page.claimed::text,
        'certified', page.certified::text,
        'amount_paid_till_date', page.paid::text,
        'still_due', page.still_due::text,
        'pdc_exposure', page.pdc_exposure::text,
        'confirmed_percent', page.confirmed_percent::text,
        'due_state', page.due_state,
        'payment_state', page.payment_state,
        'action_count', page.overdue_count + page.due_soon_count
          + page.returned_count + page.action_pdc_count
          + page.supplier_review_count,
        'latest_activity_at', page.latest_activity_at
      ) || case when page.can_view_supplier_costs then jsonb_build_object(
        'supplier_review_count', page.supplier_review_count,
        'supplier_open_amount', page.supplier_open_amount::text
      ) else '{}'::jsonb end
      order by page.latest_activity_at desc, page.id desc
    ) from (select * from page limit p_limit) page), '[]'::jsonb),
    (select jsonb_build_object(
      'project_count', count(*),
      'contract_baseline', coalesce(sum(contract_value),0)::text,
      'confirmed_eligible', coalesce(sum(confirmed_eligible),0)::text,
      'available_to_claim', coalesce(sum(available_to_claim),0)::text,
      'claimed', coalesce(sum(claimed),0)::text,
      'certified', coalesce(sum(certified),0)::text,
      'amount_paid_till_date', coalesce(sum(paid),0)::text,
      'still_due', coalesce(sum(still_due),0)::text,
      'pdc_exposure', coalesce(sum(pdc_exposure),0)::text,
      'action_count', coalesce(sum(overdue_count + due_soon_count
        + returned_count + action_pdc_count + supplier_review_count),0)
    ) from facts),
    (select coalesce(jsonb_agg(action order by
      (action->>'severity_rank')::integer, action->>'occurred_at' desc
    ), '[]'::jsonb) from (
      select jsonb_build_object(
        'project_id', facts.id,
        'project_reference', facts.project_ref,
        'project_name', facts.name,
        'code', case
          when facts.overdue_count > 0 then 'overdue_invoice'
          when facts.action_pdc_count > 0 then 'pdc_action_required'
          when facts.supplier_review_count > 0 then 'supplier_match_review'
          when facts.returned_count > 0 then 'returned_for_correction'
          else 'due_soon_invoice' end,
        'owner_role', case
          when facts.supplier_review_count > 0 then 'procurement'
          when facts.returned_count > 0 then 'project_engineer'
          else 'accountant' end,
        'severity', case when facts.overdue_count > 0
          or facts.action_pdc_count > 0 then 'critical'
          when facts.supplier_review_count > 0
            or facts.returned_count > 0 then 'high' else 'medium' end,
        'severity_rank', case when facts.overdue_count > 0
          or facts.action_pdc_count > 0 then 1
          when facts.supplier_review_count > 0
            or facts.returned_count > 0 then 2 else 3 end,
        'count', greatest(facts.overdue_count, facts.action_pdc_count,
          facts.supplier_review_count, facts.returned_count,
          facts.due_soon_count),
        'occurred_at', facts.latest_activity_at
      ) as action
      from facts
      where facts.overdue_count + facts.due_soon_count + facts.returned_count
        + facts.action_pdc_count + facts.supplier_review_count > 0
      order by case when facts.overdue_count > 0
        or facts.action_pdc_count > 0 then 1
        when facts.supplier_review_count > 0
          or facts.returned_count > 0 then 2 else 3 end,
        facts.latest_activity_at desc
      limit 12
    ) queue),
    (select case when count(*) > p_limit then (
      select jsonb_build_object(
        'before_activity_at', cursor_row.latest_activity_at,
        'before_project_id', cursor_row.id
      )
      from page cursor_row
      order by cursor_row.latest_activity_at desc, cursor_row.id desc
      offset greatest(p_limit - 1, 0) limit 1
    ) else null end from page)
  into v_authorized_count, v_filtered_count, v_rows, v_totals, v_actions, v_next;

  return jsonb_build_object(
    'schema_version', 2,
    'scope', 'portfolio',
    'actor_exact_role', v_exact_role,
    'can_export', public.v1_current_user_has_capability(
      'export_accounts_registers', null
    ),
    'authorized_project_count', v_authorized_count,
    'filtered_project_count', v_filtered_count,
    'totals', v_totals,
    'projects', v_rows,
    'action_queue', v_actions,
    'next_cursor', v_next
  );
end;
$$;

create or replace function public.v1_get_project_accounts_overview(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exact_role text := public.v1_permission_exact_role(auth.uid());
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_progress jsonb;
  v_invoices jsonb;
  v_supplier jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
    or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id
  );
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );
  v_can_supplier := public.v1_current_user_has_capability(
    'view_supplier_costs', p_project_id
  );
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles
    where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
      where id = v_profile.current_baseline_revision_id;
  end if;

  if v_can_view then
    select jsonb_build_object(
      'confirmed_percent', coalesce(case when sum(
        building.allocation_percent * stage.allocation_percent
      ) = 0 then 0 else round(sum(
        building.allocation_percent * stage.allocation_percent
          * entry.confirmed_percent
      ) / sum(building.allocation_percent * stage.allocation_percent),2) end,0)::text,
      'suggested_percent', coalesce(case when sum(
        building.allocation_percent * stage.allocation_percent
      ) = 0 then 0 else round(sum(
        building.allocation_percent * stage.allocation_percent
          * entry.suggested_percent
      ) / sum(building.allocation_percent * stage.allocation_percent),2) end,0)::text,
      'pending_review_count', count(*) filter (
        where entry.review_status = 'pending'
      ),
      'building_position', coalesce(jsonb_agg(jsonb_build_object(
        'building_scope_id', scope.id,
        'building_name', scope.name,
        'confirmed_percent', entry.confirmed_percent::text,
        'suggested_percent', entry.suggested_percent::text,
        'stage_key', entry.stage_key,
        'stage_name', stage.stage_name,
        'review_status', entry.review_status,
        'action_owner', case
          when entry.review_status = 'pending' then 'management'
          when entry.suggested_percent > entry.confirmed_percent
            then 'project_engineer' else 'none' end,
        'updated_at', entry.updated_at
      ) order by scope.scope_code, stage.display_order), '[]'::jsonb)
    ) || case when v_can_values then jsonb_build_object(
      'confirmed_eligible', coalesce(sum(round(
        v_baseline.contract_value
        * building.allocation_percent / 100
        * stage.allocation_percent / 100
        * entry.confirmed_percent / 100, 2
      )),0)::text
    ) else '{}'::jsonb end
    into v_progress
    from public.v1_accounts_billing_progress entry
    join public.v1_accounts_baseline_building_allocations building
      on building.id = entry.building_allocation_id
    join public.v1_accounts_baseline_stage_allocations stage
      on stage.id = entry.stage_allocation_id
    join public.v1_project_scopes scope on scope.id = entry.project_scope_id
    where entry.project_id = p_project_id
      and entry.baseline_revision_id = v_baseline.id
      and entry.review_status <> 'returned';
  end if;

  if v_can_values then
    select jsonb_build_object(
      'claimed', coalesce(sum(case when invoice.status not in (
        'draft','returned','cancelled'
      ) then invoice.claimed_ex_vat else 0 end),0)::text,
      'certified', coalesce(sum(case when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
        else 0 end),0)::text,
      'amount_paid_till_date', coalesce(sum(case
        when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_paid_amount(invoice.id)
        else 0 end),0)::text,
      'still_due', greatest(coalesce(sum(case
        when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id)
        else 0 end),0),0)::text,
      'pdc_exposure', coalesce(sum(case when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_pdc_exposure(invoice.id)
        else 0 end),0)::text,
      'recent_invoices', coalesce(jsonb_agg(jsonb_build_object(
        'invoice_id', invoice.id,
        'invoice_reference', invoice.invoice_reference,
        'status', invoice.status,
        'claimed_ex_vat', invoice.claimed_ex_vat::text,
        'certified_incl_vat',
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)::text,
        'amount_paid_till_date',
          public.v1_accounts_invoice_paid_amount(invoice.id)::text,
        'still_due', greatest(
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id),0
        )::text,
        'due_date', invoice.due_date,
        'updated_at', invoice.updated_at
      ) order by invoice.updated_at desc) filter (
        where invoice.id in (select recent.id from (
          select item.id from public.v1_accounts_client_invoices item
          where item.project_id = p_project_id
          order by item.updated_at desc, item.id desc limit 5
        ) recent)
      ), '[]'::jsonb)
    ) into v_invoices
    from public.v1_accounts_client_invoices invoice
    where invoice.project_id = p_project_id;
  end if;

  if v_can_supplier then
    select jsonb_build_object(
      'total_bills', count(*) filter (where bill.status <> 'cancelled'),
      'needs_review', count(*) filter (where bill.status <> 'cancelled'
        and public.v1_accounts_supplier_match_status(bill.id) <> 'matched'),
      'commitments', coalesce(sum(case when bill.status <> 'cancelled'
        then bill.total_incl_vat else 0 end),0)::text,
      'paid', coalesce(sum(case when bill.status <> 'cancelled'
        then public.v1_accounts_supplier_paid_amount(bill.id) else 0 end),0)::text,
      'open_amount', coalesce(sum(case when bill.status <> 'cancelled'
        then greatest(bill.total_incl_vat
          - public.v1_accounts_supplier_paid_amount(bill.id),0)
        else 0 end),0)::text
    ) into v_supplier
    from public.v1_accounts_supplier_bills bill
    where bill.project_id = p_project_id;
  end if;

  v_result := jsonb_build_object(
    'schema_version', 2,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'project_site', v_project.project_site,
    'project_state', v_project.state,
    'client_name', (select party.party_name
      from public.v1_project_parties party
      where party.project_id = p_project_id and party.party_kind = 'client'
      limit 1),
    'actor_exact_role', v_exact_role,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'view_supplier_costs', v_can_supplier,
      'suggest_billing_progress', public.v1_current_user_has_capability(
        'suggest_billing_progress', p_project_id
      ),
      'confirm_billing_progress', public.v1_current_user_has_capability(
        'confirm_billing_progress', p_project_id
      ),
      'prepare_client_claim', public.v1_current_user_has_capability(
        'prepare_client_claim', p_project_id
      ),
      'manage_client_invoices', public.v1_current_user_has_capability(
        'manage_client_invoices', p_project_id
      ),
      'manage_supplier_bills', public.v1_current_user_has_capability(
        'manage_supplier_bills', p_project_id
      ),
      'approve_supplier_bill_payment', public.v1_current_user_has_capability(
        'approve_supplier_bill_payment', p_project_id
      ),
      'export_accounts_registers', public.v1_current_user_has_capability(
        'export_accounts_registers', p_project_id
      )
    )
  );
  if v_can_view then
    v_result := v_result || jsonb_build_object(
      'progress', coalesce(v_progress, jsonb_build_object(
        'confirmed_percent','0','suggested_percent','0',
        'pending_review_count',0,'building_position','[]'::jsonb
      ))
    );
    if v_baseline.id is not null then
      v_result := v_result || jsonb_build_object(
        'baseline', jsonb_build_object(
          'revision_id', v_baseline.id,
          'revision_number', v_baseline.revision_number,
          'status', v_baseline.status,
          'effective_at', v_baseline.effective_at
        ) || case when v_can_values then jsonb_build_object(
          'contract_value', v_baseline.contract_value::text,
          'currency_code', v_baseline.currency_code,
          'payment_terms_days', v_baseline.payment_terms_days,
          'reminder_lead_days', v_baseline.reminder_lead_days
        ) else '{}'::jsonb end
      );
    else
      v_result := v_result || jsonb_build_object('baseline', null);
    end if;
  end if;
  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'receivables', coalesce(v_invoices, jsonb_build_object(
        'claimed','0','certified','0','amount_paid_till_date','0',
        'still_due','0','pdc_exposure','0','recent_invoices','[]'::jsonb
      ))
    );
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', coalesce(v_supplier, jsonb_build_object(
        'total_bills',0,'needs_review',0,'commitments','0',
        'paid','0','open_amount','0'
      ))
    );
  end if;
  return v_result;
end;
$$;

create or replace function public.v1_get_accounts_office_register(
  p_section text,
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      select sum(line.claimed_amount) as claimed_amount
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
    (select coalesce(sum(amount), 0) from filtered),
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
$$;

create or replace function public.v1_get_accounts_export(
  p_export_kind text,
  p_project_id uuid default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
        select sum(line.claimed_amount) amount, count(*) line_count
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
$$;

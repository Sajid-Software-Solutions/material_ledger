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

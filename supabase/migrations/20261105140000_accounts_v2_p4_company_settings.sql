-- R39 Accounts Workspace V2 — P4 (part a): company letterhead/bank settings (D9)
--
-- Seeds the Admin-managed company letterhead and bank settings into the existing
-- Configuration Centre allowlist (area company_regional), and wires a frozen
-- `company` block into the invoice document model so an issued invoice reprints
-- identically. Additive; existing company.* keys are untouched.
-- See R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 6.9 / 9, PRODUCT_DECISIONS 32 (D9).

insert into public.v1_configuration_settings (
  setting_key, area, value_type, default_value, published_value, display_order
)
values
  ('company.trn', 'company_regional', 'string',
    to_jsonb('100026741700003'::text), to_jsonb('100026741700003'::text), 120),
  ('company.address', 'company_regional', 'string',
    to_jsonb('P.O. Box 4757, Abu Dhabi, U.A.E'::text),
    to_jsonb('P.O. Box 4757, Abu Dhabi, U.A.E'::text), 130),
  ('company.phone', 'company_regional', 'string',
    to_jsonb('02-5509788'::text), to_jsonb('02-5509788'::text), 140),
  ('company.fax', 'company_regional', 'string',
    to_jsonb('02-5509688'::text), to_jsonb('02-5509688'::text), 150),
  ('company.email', 'company_regional', 'string',
    to_jsonb('yorks_sk@yorks.ae'::text), to_jsonb('yorks_sk@yorks.ae'::text), 160),
  ('company.bank_name', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 170),
  ('company.bank_iban', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 180),
  ('company.bank_account_name', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 190)
on conflict (setting_key) do nothing;

-- ---------------------------------------------------------------------------
-- Re-create the invoice document builder to freeze the published company block.
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
  v_company jsonb;
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

  -- Frozen published company letterhead/bank block.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';

  return jsonb_build_object(
    'schema_version', 1,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
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

-- R39 Accounts Workspace V2 — P6 (part c): editable contract references
--
-- The prototype Contract card carries the client TRN, work-order number/date and
-- contract number. These have no V1 home, so this migration adds them to the
-- project-level commercial profile (not the versioned baseline), returns them in
-- the setup read, and adds a focused, idempotent write command to edit them.
--
-- Additive: ADD COLUMN IF NOT EXISTS (nullable), a new CREATE OR REPLACE write
-- function (no existing signature changes), and a CREATE OR REPLACE of the setup
-- read that returns a `references` block (commercial-gated, like the rest of the
-- Contract surface). No table drop, no row change.

alter table public.v1_accounts_project_commercial_profiles
  add column if not exists client_trn text;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists work_order_number text;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists work_order_date date;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists contract_number text;

-- Write: edit the four references on the profile. Capability + optimistic-lock
-- version check + idempotency, following the invoice-settings save pattern.
create or replace function public.v1_save_accounts_contract_references(
  p_project_id uuid,
  p_client_trn text,
  p_work_order_number text,
  p_work_order_date date,
  p_contract_number text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.v1_accounts_project_commercial_profiles%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'configure_project_commercials');
  v_payload := jsonb_build_object('project_id', p_project_id,
    'client_trn', nullif(btrim(coalesce(p_client_trn, '')), ''),
    'work_order_number', nullif(btrim(coalesce(p_work_order_number, '')), ''),
    'work_order_date', p_work_order_date,
    'contract_number', nullif(btrim(coalesce(p_contract_number, '')), ''),
    'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_accounts_contract_references', p_idempotency_key, v_payload);
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_contract_refs|' || p_project_id::text, 0));
  select * into v_row from public.v1_accounts_project_commercial_profiles
    where project_id = p_project_id for update;
  if not found then
    raise exception 'R39_ACCOUNTS_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  update public.v1_accounts_project_commercial_profiles set
    client_trn = nullif(btrim(coalesce(p_client_trn, '')), ''),
    work_order_number = nullif(btrim(coalesce(p_work_order_number, '')), ''),
    work_order_date = p_work_order_date,
    contract_number = nullif(btrim(coalesce(p_contract_number, '')), ''),
    record_version = record_version + 1
  where project_id = p_project_id returning * into v_row;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency(
    'v1_save_accounts_contract_references', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, integer, uuid) from public, anon;
grant execute on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, integer, uuid) to authenticated;

-- Read: return the references block (and keep the parties block from part b).
create or replace function public.v1_get_project_commercial_setup(
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

  -- Editable contract references from the project profile.
  v_result := v_result || jsonb_build_object(
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', v_profile.contract_number));

  return v_result;
end;
$$;

revoke all on function public.v1_get_project_commercial_setup(uuid)
  from public, anon;
grant execute on function public.v1_get_project_commercial_setup(uuid)
  to authenticated, service_role;

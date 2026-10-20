-- Rental review corrections: consistent financial row-lock ordering, finite
-- money and exact-cent receipt/cheque amounts. No imported source, existing
-- amount, allocation, period, receipt, cheque, audit or command key is changed.
-- Existing function signatures and ACLs are preserved. Rollback stops the new
-- client; retain the constraints and history. Do not restore the unsafe lock
-- order or remove/round any accepted receipt to undo a transaction.
begin;

-- PostgreSQL fixed-scale numeric accepts NaN and considers it >= 0. The old
-- nonnegative checks therefore do not enforce finite money. These checks make
-- new writes fail closed and validate retained rows without rewriting any data.
alter table public.v1_rental_leases drop constraint if exists v1_rental_leases_finite_amounts_check;
alter table public.v1_rental_leases add constraint v1_rental_leases_finite_amounts_check
  check (monthly_rent <> 'NaN'::numeric and annual_rent <> 'NaN'::numeric
    and security_deposit <> 'NaN'::numeric and annual_escalation_percent <> 'NaN'::numeric);
alter table public.v1_rental_periods drop constraint if exists v1_rental_periods_finite_amount_check;
alter table public.v1_rental_periods add constraint v1_rental_periods_finite_amount_check check (amount_due <> 'NaN'::numeric);
alter table public.v1_rental_receipts drop constraint if exists v1_rental_receipts_finite_amount_check;
alter table public.v1_rental_receipts add constraint v1_rental_receipts_finite_amount_check check (amount_received <> 'NaN'::numeric);
alter table public.v1_rental_cheques drop constraint if exists v1_rental_cheques_finite_amount_check;
alter table public.v1_rental_cheques add constraint v1_rental_cheques_finite_amount_check check (amount <> 'NaN'::numeric);

-- The workbook's complete original tracker row remains its import evidence
-- after an owner corrects the visible Unit Code. Row number, filename and
-- optional completion fields are deliberately not identity; no records merge.
create or replace function public.v1_rental_tracker_source_fingerprint(p_metadata jsonb)
returns text language sql immutable strict set search_path = '' as $$
  select case when (p_metadata->>'source_format'='yorks_properties_tracker_v1'
      or p_metadata->>'format'='yorks_properties_tracker_v1')
    and jsonb_typeof(p_metadata->'original_values')='object'
    and (p_metadata->'original_values') ?& array['Unit No','Unit Type','Tenant / Company',
      'Contract Start','Contract End','Annual Rent (AED)','Status','Security Cheque (AED)',
      'Contact','Days to Expiry','Expiry Flag']::text[]
  then public.v1_hash_json((select jsonb_object_agg(source_key,p_metadata->'original_values'->source_key)
    from unnest(array['Unit No','Unit Type','Tenant / Company','Contract Start','Contract End',
      'Annual Rent (AED)','Status','Security Cheque (AED)','Contact','Days to Expiry','Expiry Flag']::text[]) source_key)) end
$$;
revoke all on function public.v1_rental_tracker_source_fingerprint(jsonb) from public,anon,authenticated;
-- An index supplies concurrent-writer enforcement. If retained data already has
-- ambiguous identical evidence, stop for review rather than choose/merge a row.
create unique index if not exists v1_rental_properties_tracker_source_unique_idx
  on public.v1_rental_properties(public.v1_rental_tracker_source_fingerprint(source_metadata))
  where public.v1_rental_tracker_source_fingerprint(source_metadata) is not null;

create or replace function public.v1_record_rent_payment(
  p_period_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text,
  p_reference text,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_role text := public.v1_current_role();
  v_existing jsonb;
  v_period public.v1_rental_periods%rowtype;
  v_lease public.v1_rental_leases%rowtype;
  v_paid numeric(16,2);
  v_receipt_id uuid := gen_random_uuid();
  v_response jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_record_rent_payment', p_idempotency_key,
    jsonb_build_object('period_id', p_period_id, 'amount', p_amount,
      'payment_date', p_payment_date, 'payment_method', p_payment_method,
      'reference', p_reference, 'note', p_note)
  );
  if v_existing is not null then return v_existing; end if;
  if p_amount is null or p_amount = 'NaN'::numeric or p_amount <= 0
    or p_amount <> round(p_amount, 2) or p_payment_date is null then
    raise exception 'V1_RENTAL_PAYMENT_INVALID' using errcode = '22023';
  end if;
  if p_payment_method is null or p_payment_method not in ('bank_transfer', 'cash', 'cdc', 'pdc', 'other') then
    raise exception 'V1_RENTAL_PAYMENT_METHOD_INVALID' using errcode = '22023';
  end if;
  if p_payment_method in ('cdc', 'pdc')
    and btrim(coalesce(p_reference, '')) = '' then
    raise exception 'V1_RENTAL_PAYMENT_REFERENCE_REQUIRED'
      using errcode = '22023';
  end if;

  -- Resolve immutable ownership before taking locks, then use the same
  -- property -> lease -> period order as property edits/import/archive. A late
  -- receipt FK property lock after a period lock can deadlock a schedule edit.
  select lease_record.* into strict v_lease
  from public.v1_rental_periods period_record
  join public.v1_rental_leases lease_record on lease_record.id = period_record.lease_id
  where period_record.id = p_period_id;
  perform 1 from public.v1_rental_properties
  where id = v_lease.property_id for update;
  select * into strict v_lease from public.v1_rental_leases
  where id = v_lease.id for update;
  select * into strict v_period from public.v1_rental_periods
  where id = p_period_id and lease_id = v_lease.id for update;
  select coalesce(sum(amount_received), 0) into v_paid
  from public.v1_rental_receipts where period_id = p_period_id;
  if v_paid + p_amount > v_period.amount_due then
    raise exception 'V1_RENTAL_PAYMENT_EXCEEDS_BALANCE'
      using errcode = '23514';
  end if;

  insert into public.v1_rental_receipts (
    id, property_id, lease_id, period_id, amount_received, payment_date,
    payment_method, reference, note, recorded_by_auth_user_id,
    recorded_by_role, idempotency_key
  ) values (
    v_receipt_id, v_lease.property_id, v_lease.id, p_period_id, p_amount,
    p_payment_date, p_payment_method, nullif(btrim(p_reference), ''),
    nullif(btrim(p_note), ''), v_actor, v_role, p_idempotency_key
  );
  v_response := jsonb_build_object(
    'receipt_id', v_receipt_id, 'period_id', p_period_id,
    'amount_paid', v_paid + p_amount,
    'balance', v_period.amount_due - v_paid - p_amount
  );
  perform public.v1_write_audit_event(
    'rent_payment_recorded', 'rental_receipt', v_receipt_id, null, null,
    v_response, null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_record_rent_payment', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_save_rental_cheque(
  p_payload jsonb,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_existing jsonb;
  v_id uuid := coalesce(nullif(p_payload ->> 'cheque_id', '')::uuid, gen_random_uuid());
  v_cheque public.v1_rental_cheques%rowtype;
  v_property public.v1_rental_properties%rowtype;
  v_property_id uuid := nullif(p_payload ->> 'property_id', '')::uuid;
  v_lease_id uuid := nullif(p_payload ->> 'lease_id', '')::uuid;
  v_period_id uuid := nullif(p_payload ->> 'period_id', '')::uuid;
  v_response jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_rental_cheque', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected_version', p_expected_version)
  );
  if v_existing is not null then return v_existing; end if;
  if btrim(coalesce(p_payload ->> 'cheque_number', '')) = ''
    or btrim(coalesce(p_payload ->> 'bank_name', '')) = ''
    or v_property_id is null or v_lease_id is null
    or nullif(p_payload ->> 'cheque_date', '') is null
    or coalesce(p_payload ->> 'cheque_type', '') not in ('cdc', 'pdc')
    or coalesce((p_payload ->> 'amount')::numeric, 0) <= 0
    or (p_payload ->> 'amount')::numeric = 'NaN'::numeric
    or (p_payload ->> 'amount')::numeric <> round((p_payload ->> 'amount')::numeric, 2) then
    raise exception 'V1_RENTAL_CHEQUE_REQUIRED_FIELDS'
      using errcode = '22023';
  end if;
  select * into strict v_property from public.v1_rental_properties
  where id = v_property_id for update;
  if v_property.is_archived then
    raise exception 'V1_RENTAL_ARCHIVED_PROPERTY_READ_ONLY' using errcode = '23514';
  end if;
  -- Serialize a new cheque's linkage with lease/schedule edits before checking
  -- the referenced period and acquiring its own cheque row lock.
  perform 1 from public.v1_rental_leases
  where id = v_lease_id and property_id = v_property_id for update;
  if not exists (
    select 1 from public.v1_rental_leases lease_record
    where lease_record.id = v_lease_id
      and lease_record.property_id = v_property_id
  ) then
    raise exception 'V1_RENTAL_CHEQUE_LEASE_MISMATCH'
      using errcode = '23514';
  end if;
  if v_period_id is not null and not exists (
    select 1 from public.v1_rental_periods period_record
    where period_record.id = v_period_id
      and period_record.lease_id = v_lease_id
  ) then
    raise exception 'V1_RENTAL_CHEQUE_PERIOD_MISMATCH'
      using errcode = '23514';
  end if;
  if v_period_id is not null then
    perform 1 from public.v1_rental_periods
    where id = v_period_id and lease_id = v_lease_id for update;
  end if;
  select * into v_cheque from public.v1_rental_cheques where id = v_id for update;
  if found then
    if p_expected_version is null or p_expected_version <> v_cheque.record_version then
      raise exception 'V1_RENTAL_CHEQUE_VERSION_CONFLICT' using errcode = '40001';
    end if;
    if v_cheque.property_id <> v_property_id
      or v_cheque.lease_id <> v_lease_id then
      raise exception 'V1_RENTAL_CHEQUE_IDENTITY_IMMUTABLE'
        using errcode = '23514';
    end if;
    if v_cheque.status in ('deposited', 'cleared', 'cancelled') and row(
      v_cheque.period_id, v_cheque.cheque_number, v_cheque.cheque_type,
      v_cheque.bank_name, v_cheque.cheque_date, v_cheque.amount
    ) is distinct from row(
      v_period_id, btrim(p_payload ->> 'cheque_number'),
      p_payload ->> 'cheque_type', btrim(p_payload ->> 'bank_name'),
      (p_payload ->> 'cheque_date')::date, (p_payload ->> 'amount')::numeric
    ) then
      raise exception 'V1_RENTAL_CHEQUE_TERMS_LOCKED' using errcode = '23514';
    end if;
    update public.v1_rental_cheques set
      period_id = v_period_id,
      cheque_number = btrim(p_payload ->> 'cheque_number'),
      cheque_type = p_payload ->> 'cheque_type',
      bank_name = btrim(p_payload ->> 'bank_name'),
      cheque_date = (p_payload ->> 'cheque_date')::date,
      amount = (p_payload ->> 'amount')::numeric,
      note = nullif(btrim(p_payload ->> 'note'), ''),
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor, updated_at = clock_timestamp()
    where id = v_id returning * into v_cheque;
  else
    if p_expected_version is not null then
      raise exception 'V1_RENTAL_CHEQUE_NOT_FOUND' using errcode = 'P0002';
    end if;
    insert into public.v1_rental_cheques (
      id, property_id, lease_id, period_id, cheque_number, cheque_type,
      bank_name, cheque_date, amount, note, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_id, v_property_id, v_lease_id, v_period_id,
      btrim(p_payload ->> 'cheque_number'), p_payload ->> 'cheque_type',
      btrim(p_payload ->> 'bank_name'), (p_payload ->> 'cheque_date')::date,
      (p_payload ->> 'amount')::numeric, nullif(btrim(p_payload ->> 'note'), ''),
      v_actor, v_actor
    ) returning * into v_cheque;
  end if;
  v_response := jsonb_build_object(
    'cheque_id', v_id, 'record_version', v_cheque.record_version,
    'status', v_cheque.status
  );
  perform public.v1_write_audit_event(
    'rental_cheque_saved', 'rental_cheque', v_id, null, null,
    (select to_jsonb(c) from public.v1_rental_cheques c where c.id = v_id),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_save_rental_cheque', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_save_rental_property(
  p_payload jsonb,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_existing jsonb;
  v_property_id uuid := coalesce(
    nullif(p_payload ->> 'property_id', '')::uuid, gen_random_uuid()
  );
  v_lease_id uuid := nullif(p_payload ->> 'lease_id', '')::uuid;
  v_occupancy text := coalesce(nullif(p_payload->>'occupancy_state',''),
    case when coalesce((p_payload->>'occupied')::boolean,false) then 'occupied' else 'vacant' end);
  v_manage_lease boolean;
  v_billing_start date;
  v_before jsonb;
  v_property public.v1_rental_properties%rowtype;
  v_existing_lease public.v1_rental_leases%rowtype;
  v_schedule_changed boolean;
  v_response jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_rental_property', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected_version', p_expected_version)
  );
  if v_existing is not null then return v_existing; end if;

  if (p_payload ? 'unit_code' and btrim(coalesce(p_payload ->> 'unit_code',''))='')
    or (p_payload ? 'property_name' and btrim(coalesce(p_payload ->> 'property_name',''))='')
    or (p_expected_version is null and (not p_payload ? 'unit_code' or not p_payload ? 'property_name')) then
    raise exception 'V1_RENTAL_PROPERTY_REQUIRED_FIELDS'
      using errcode = '22023';
  end if;

  if p_payload ? 'source_metadata'
    and jsonb_typeof(p_payload->'source_metadata') not in ('object','null') then
    raise exception 'V1_RENTAL_SOURCE_METADATA_INVALID' using errcode='22023';
  end if;

  if public.v1_rental_tracker_source_fingerprint(p_payload->'source_metadata') is not null
    and exists(select 1 from public.v1_rental_properties previous_source
      where previous_source.id <> v_property_id
        and public.v1_rental_tracker_source_fingerprint(previous_source.source_metadata)
          = public.v1_rental_tracker_source_fingerprint(p_payload->'source_metadata')) then
    raise exception 'V1_RENTAL_SOURCE_ALREADY_IMPORTED_USE_CURRENT_CODE' using errcode='23505';
  end if;

  select property_record.*
  into v_property
  from public.v1_rental_properties property_record
  where property_record.id = v_property_id
  for update;

  if found then
    -- Omitted optional fields are retained on sparse workbook/metadata edits.
    -- An explicit JSON null remains an intentional clear, subject to the
    -- existing financial-history and immutable-source guards below.
    if not p_payload ? 'occupancy_state' and not p_payload ? 'occupied' then
      v_occupancy := v_property.occupancy_state;
    end if;
    p_payload := to_jsonb(v_property) || coalesce((
      select to_jsonb(current_lease) || jsonb_build_object(
        'lease_id',current_lease.id,'lease_notes',current_lease.notes)
      from public.v1_rental_leases current_lease
      where current_lease.property_id=v_property_id and current_lease.is_current
        and (v_lease_id is null or current_lease.id=v_lease_id)
    ),'{}'::jsonb) || p_payload;
    v_before := to_jsonb(v_property) || jsonb_build_object('lease', (
      select to_jsonb(lease_record) from public.v1_rental_leases lease_record
      where lease_record.property_id = v_property_id and lease_record.is_current
    ));
    if p_expected_version is null or p_expected_version <> v_property.record_version then
      raise exception 'V1_RENTAL_PROPERTY_VERSION_CONFLICT'
        using errcode = '40001';
    end if;
    if v_property.is_archived then
      raise exception 'V1_RENTAL_ARCHIVED_PROPERTY_READ_ONLY'
        using errcode = '23514';
    end if;
    if v_property.source_metadata ? 'original_values' and exists (
      select 1 from jsonb_each(v_property.source_metadata) original_entry
      where original_entry.key in ('original_values','format','source_format','source_file',
        'source_sheet','source_row','source_unit_number','source_unit_type')
        and coalesce(p_payload->'source_metadata','{}'::jsonb) ? original_entry.key
        and p_payload->'source_metadata'->original_entry.key is distinct from original_entry.value
    ) then
      raise exception 'V1_RENTAL_SOURCE_EVIDENCE_IMMUTABLE' using errcode='23514';
    end if;
    update public.v1_rental_properties set
      unit_code = upper(btrim(p_payload ->> 'unit_code')),
      property_name = btrim(p_payload ->> 'property_name'),
      property_type = p_payload ->> 'property_type',
      municipality_number = nullif(btrim(p_payload ->> 'municipality_number'), ''),
      location = nullif(btrim(p_payload ->> 'location'),''),
      description = nullif(btrim(p_payload ->> 'description'), ''),
      occupancy_state = v_occupancy,
      source_metadata = source_metadata || case when jsonb_typeof(p_payload->'source_metadata')='object' then p_payload->'source_metadata' else '{}'::jsonb end,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_at = clock_timestamp()
    where id = v_property_id
    returning * into v_property;
  else
    if p_expected_version is not null then
      raise exception 'V1_RENTAL_PROPERTY_NOT_FOUND' using errcode = 'P0002';
    end if;
    insert into public.v1_rental_properties (
      id, unit_code, property_name, property_type, municipality_number,
      location, description, occupancy_state, source_metadata, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_property_id, upper(btrim(p_payload ->> 'unit_code')),
      btrim(p_payload ->> 'property_name'), p_payload ->> 'property_type',
      nullif(btrim(p_payload ->> 'municipality_number'), ''),
      nullif(btrim(p_payload ->> 'location'),''),
      nullif(btrim(p_payload ->> 'description'), ''),
      v_occupancy, case when jsonb_typeof(p_payload->'source_metadata')='object' then p_payload->'source_metadata' else '{}'::jsonb end,
      v_actor, v_actor
    ) returning * into v_property;
  end if;

  if v_lease_id is null then
    select id into v_lease_id from public.v1_rental_leases
    where property_id=v_property_id and is_current for update;
  end if;
  v_manage_lease := v_occupancy='occupied' or v_lease_id is not null
    or nullif(btrim(p_payload->>'tenant_name'),'') is not null
    or nullif(btrim(p_payload->>'contract_number'),'') is not null
    or nullif(p_payload->>'lease_start','') is not null
    or nullif(p_payload->>'lease_end','') is not null
    or nullif(p_payload->>'annual_rent','') is not null
    or nullif(p_payload->>'monthly_rent','') is not null;
  v_lease_id := coalesce(v_lease_id,gen_random_uuid());
  if v_manage_lease then
    select * into v_existing_lease
    from public.v1_rental_leases where id = v_lease_id for update;
    if found then
      if v_existing_lease.property_id <> v_property_id then
        raise exception 'V1_RENTAL_LEASE_PROPERTY_MISMATCH'
          using errcode = '23514';
      end if;
      if not v_existing_lease.is_current then
        raise exception 'V1_RENTAL_HISTORICAL_LEASE_READ_ONLY'
          using errcode = '23514';
      end if;
      v_billing_start := case when p_payload ? 'billing_start'
        then nullif(p_payload->>'billing_start','')::date else v_existing_lease.billing_start end;
      v_schedule_changed := row(
        v_existing_lease.lease_start, v_existing_lease.lease_end,
        v_existing_lease.monthly_rent, v_existing_lease.monthly_due_day,
        v_existing_lease.annual_rent, v_existing_lease.payment_frequency,
        v_existing_lease.billing_start
      ) is distinct from row(
        nullif(p_payload ->> 'lease_start','')::date,
        nullif(p_payload ->> 'lease_end','')::date,
        nullif(p_payload ->> 'monthly_rent','')::numeric,
        coalesce((p_payload ->> 'monthly_due_day')::integer, 1),
        nullif(p_payload ->> 'annual_rent','')::numeric,
        coalesce(nullif(p_payload->>'payment_frequency',''),'monthly'),
        v_billing_start
      );
    else
      v_billing_start := case when p_payload ? 'billing_start'
        then nullif(p_payload->>'billing_start','')::date
        else nullif(p_payload->>'lease_start','')::date end;
      v_schedule_changed := true;
    end if;

    update public.v1_rental_leases
    set is_current = false, updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where property_id = v_property_id and is_current and id <> v_lease_id;

    insert into public.v1_rental_leases (
      id, property_id, contract_number, contract_type, contract_status,
      tenant_name, trade_licence_number, contact_number, email, signed_date,
      lease_start, lease_end, monthly_rent, security_deposit,
      monthly_due_day, grace_period_days, default_payment_method,
      payment_frequency, contract_cheque_count, annual_escalation_percent,
      renewal_notice_days, notes, annual_rent, billing_start, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_lease_id, v_property_id, nullif(btrim(p_payload ->> 'contract_number'),''),
      coalesce(nullif(p_payload ->> 'contract_type', ''), 'tenancy_contract'),
      coalesce(nullif(p_payload ->> 'contract_status', ''), 'draft'),
      nullif(btrim(p_payload ->> 'tenant_name'),''),
      nullif(btrim(p_payload ->> 'trade_licence_number'), ''),
      nullif(btrim(p_payload ->> 'contact_number'), ''),
      nullif(btrim(p_payload ->> 'email'), ''),
      nullif(p_payload ->> 'signed_date', '')::date,
      nullif(p_payload ->> 'lease_start','')::date,
      nullif(p_payload ->> 'lease_end','')::date,
      nullif(p_payload ->> 'monthly_rent','')::numeric,
      coalesce((p_payload ->> 'security_deposit')::numeric, 0),
      coalesce((p_payload ->> 'monthly_due_day')::integer, 1),
      coalesce((p_payload ->> 'grace_period_days')::integer, 5),
      coalesce(nullif(p_payload ->> 'default_payment_method', ''), 'bank_transfer'),
      coalesce(nullif(p_payload ->> 'payment_frequency', ''), 'monthly'),
      coalesce((p_payload ->> 'contract_cheque_count')::integer, 0),
      coalesce((p_payload ->> 'annual_escalation_percent')::numeric, 0),
      coalesce((p_payload ->> 'renewal_notice_days')::integer, 90),
      nullif(btrim(p_payload ->> 'lease_notes'), ''),
      nullif(p_payload->>'annual_rent','')::numeric,v_billing_start,v_actor,v_actor
    )
    on conflict (id) do update set
      contract_number = excluded.contract_number,
      contract_type = excluded.contract_type,
      contract_status = excluded.contract_status,
      tenant_name = excluded.tenant_name,
      trade_licence_number = excluded.trade_licence_number,
      contact_number = excluded.contact_number,
      email = excluded.email,
      signed_date = excluded.signed_date,
      lease_start = excluded.lease_start,
      lease_end = excluded.lease_end,
      monthly_rent = excluded.monthly_rent,
      annual_rent = excluded.annual_rent, billing_start = excluded.billing_start,
      security_deposit = excluded.security_deposit,
      monthly_due_day = excluded.monthly_due_day,
      grace_period_days = excluded.grace_period_days,
      default_payment_method = excluded.default_payment_method,
      payment_frequency = excluded.payment_frequency,
      contract_cheque_count = excluded.contract_cheque_count,
      annual_escalation_percent = excluded.annual_escalation_percent,
      renewal_notice_days = excluded.renewal_notice_days,
      notes = excluded.notes,
      is_current = true,
      record_version = public.v1_rental_leases.record_version + 1,
      updated_by_auth_user_id = excluded.updated_by_auth_user_id,
      updated_at = clock_timestamp();

    -- Contact/name/status/notice metadata never rebuilds financial history.
    if v_schedule_changed then
      perform public.v1_rental_replace_unpaid_schedule(v_lease_id);
    end if;

  end if;

  v_response := jsonb_build_object(
    'property_id', v_property_id,
    'lease_id', case when v_manage_lease then v_lease_id else null end,
    'record_version', v_property.record_version
  );
  perform public.v1_write_audit_event(
    case when v_before is null then 'rental_property_created'
      else 'rental_property_updated' end,
    'rental_property', v_property_id, null, v_before,
    (select to_jsonb(p) || jsonb_build_object('lease', (
      select to_jsonb(lease_record) from public.v1_rental_leases lease_record
      where lease_record.property_id = v_property_id and lease_record.is_current
    )) from public.v1_rental_properties p where p.id = v_property_id),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_save_rental_property', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

commit;

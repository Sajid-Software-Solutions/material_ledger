-- Owner-approved incomplete source intake. The original tracker is evidence,
-- not authority for missing facts or historical debt. No amount conversion,
-- fabricated tenant/contract/location, or automatic historic receipt is made.
-- Additive columns and relaxed optional-field constraints preserve all old IDs,
-- values, schedules, receipts, cheques, documents and actor/audit history.
-- Rollback: stop the new intake/UI; retain columns and imported evidence. Do not
-- reapply NOT NULL/old enums to populated data or remove imported records.
begin;

alter table public.v1_rental_properties alter column location drop not null;
alter table public.v1_rental_properties drop constraint if exists v1_rental_properties_occupancy_state_check;
alter table public.v1_rental_properties add constraint v1_rental_properties_occupancy_state_check
  check (occupancy_state in ('vacant', 'occupied', 'unknown'));
alter table public.v1_rental_properties drop constraint if exists v1_rental_properties_property_type_check;
alter table public.v1_rental_properties add constraint v1_rental_properties_property_type_check
  check (property_type in ('shop', 'store', 'office_store', 'warehouse', 'office', 'labour_camp', 'villa', 'other'));
alter table public.v1_rental_properties add column if not exists source_metadata jsonb not null default '{}'::jsonb;
alter table public.v1_rental_properties drop constraint if exists v1_rental_properties_source_metadata_check;
alter table public.v1_rental_properties add constraint v1_rental_properties_source_metadata_check
  check (jsonb_typeof(source_metadata) = 'object');

alter table public.v1_rental_leases alter column contract_number drop not null;
alter table public.v1_rental_leases alter column tenant_name drop not null;
alter table public.v1_rental_leases alter column lease_start drop not null;
alter table public.v1_rental_leases alter column lease_end drop not null;
alter table public.v1_rental_leases alter column monthly_rent drop not null;
alter table public.v1_rental_leases add column if not exists annual_rent numeric(16,2);
alter table public.v1_rental_leases drop constraint if exists v1_rental_leases_annual_rent_check;
alter table public.v1_rental_leases add constraint v1_rental_leases_annual_rent_check check (annual_rent >= 0);
alter table public.v1_rental_leases drop constraint if exists v1_rental_leases_payment_frequency_check;
alter table public.v1_rental_leases add constraint v1_rental_leases_payment_frequency_check
  check (payment_frequency in ('monthly', 'annual'));

-- Only the first installation preserves the already-approved legacy billing
-- range. Reapplying this migration must never activate imported pending rows.
do $billing_start$
begin
  if not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='v1_rental_leases' and column_name='billing_start') then
    alter table public.v1_rental_leases add column billing_start date;
    update public.v1_rental_leases set billing_start=lease_start;
  end if;
end;
$billing_start$;

create or replace function public.v1_rental_business_date()
returns date language sql stable set search_path = '' as $$
  select (current_timestamp at time zone 'Asia/Dubai')::date
$$;

create or replace function public.v1_rental_missing_fields_internal(p_property_id uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    case when nullif(btrim(p.location), '') is null then 'location' end,
    case when p.property_type='other' and p.source_metadata ? 'source_row'
      and nullif(btrim(p.source_metadata->>'source_unit_type'),'') is null then 'property_type' end,
    case when p.occupancy_state='unknown' then 'occupancy' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null) and nullif(btrim(l.tenant_name), '') is null then 'tenant_name' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null) and nullif(btrim(l.contract_number), '') is null then 'contract_number' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null) and nullif(btrim(l.contact_number), '') is null then 'contact_number' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null) and l.lease_start is null then 'lease_start' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null) and l.lease_end is null then 'lease_end' end,
    case when (p.occupancy_state<>'vacant' or l.id is not null)
      and (case when l.payment_frequency='annual' then l.annual_rent else l.monthly_rent end) is null then 'rent_amount' end,
    case when l.id is not null and l.billing_start is null then 'billing_start' end,
    case when p.source_metadata ? 'source_row' and nullif(btrim(p.source_metadata->>'source_unit_number'), '') is null
      and p.unit_code='SOURCE-'||(p.source_metadata->>'source_row') then 'source_unit_number' end,
    case when p.source_metadata ? 'source_row' and nullif(btrim(p.source_metadata->>'source_unit_type'), '') is null
      and p.property_type='other' then 'source_property_type' end
  ]::text[], null)
  from public.v1_rental_properties p
  left join public.v1_rental_leases l on l.property_id=p.id and l.is_current
  where p.id=p_property_id
$$;

create or replace function public.v1_rental_missing_fields(p_property_id uuid)
returns text[] language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.v1_rental_assert_admin();
  return public.v1_rental_missing_fields_internal(p_property_id);
end;
$$;

create or replace function public.v1_rental_replace_unpaid_schedule(p_lease_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_lease public.v1_rental_leases%rowtype;
  v_ready boolean;
begin
  select * into strict v_lease from public.v1_rental_leases where id=p_lease_id for update;
  v_ready := v_lease.billing_start is not null and v_lease.lease_start is not null
    and v_lease.lease_end is not null
    and (case when v_lease.payment_frequency='annual' then v_lease.annual_rent else v_lease.monthly_rent end) is not null;
  if not v_ready then
    if exists(select 1 from public.v1_rental_periods where lease_id=p_lease_id) then
      raise exception 'V1_RENTAL_EXISTING_BILLING_CANNOT_BE_CLEARED' using errcode='23514';
    end if;
    return;
  end if;
  if v_lease.billing_start < v_lease.lease_start or v_lease.billing_start > v_lease.lease_end then
    raise exception 'V1_RENTAL_BILLING_START_OUTSIDE_LEASE' using errcode='22023';
  end if;
  if exists(select 1 from public.v1_rental_receipts where lease_id=p_lease_id) then
    raise exception 'V1_RENTAL_PAID_SCHEDULE_CANNOT_BE_REBUILT' using errcode='23514';
  end if;
  if exists(select 1 from public.v1_rental_cheques c join public.v1_rental_periods p on p.id=c.period_id where p.lease_id=p_lease_id) then
    raise exception 'V1_RENTAL_LINKED_SCHEDULE_CANNOT_BE_REBUILT' using errcode='23514';
  end if;
  delete from public.v1_rental_periods where lease_id=p_lease_id and period_month not in (
    select date_trunc('month', desired.bill_date)::date
    from generate_series(0,case when v_lease.payment_frequency='annual'
      then extract(year from v_lease.lease_end)::integer-extract(year from v_lease.billing_start)::integer
      else (extract(year from v_lease.lease_end)::integer-extract(year from v_lease.billing_start)::integer)*12
        +extract(month from v_lease.lease_end)::integer-extract(month from v_lease.billing_start)::integer end) step_index
    cross join lateral(select case when v_lease.payment_frequency='annual'
      then (v_lease.billing_start+make_interval(years=>step_index))::date
      else (date_trunc('month',v_lease.billing_start)+make_interval(months=>step_index))::date end bill_date) desired
    where desired.bill_date<=v_lease.lease_end
  );
  insert into public.v1_rental_periods(id,lease_id,period_month,due_date,amount_due)
  select gen_random_uuid(),p_lease_id,date_trunc('month',bill_date)::date,
    case when v_lease.payment_frequency='annual' then bill_date::date
      else greatest(v_lease.billing_start, (date_trunc('month',bill_date)::date+
        (least(v_lease.monthly_due_day,extract(day from (date_trunc('month',bill_date)+interval '1 month - 1 day'))::integer)-1))::date) end,
    case when v_lease.payment_frequency='annual' then v_lease.annual_rent else v_lease.monthly_rent end
  from generate_series(0,case when v_lease.payment_frequency='annual'
    then extract(year from v_lease.lease_end)::integer-extract(year from v_lease.billing_start)::integer
    else (extract(year from v_lease.lease_end)::integer-extract(year from v_lease.billing_start)::integer)*12
      +extract(month from v_lease.lease_end)::integer-extract(month from v_lease.billing_start)::integer end) step_index
  cross join lateral(select case when v_lease.payment_frequency='annual'
    then (v_lease.billing_start+make_interval(years=>step_index))::date
    else (date_trunc('month',v_lease.billing_start)+make_interval(months=>step_index))::date end bill_date) desired
  where desired.bill_date<=v_lease.lease_end
  on conflict(lease_id,period_month) do update set due_date=excluded.due_date,amount_due=excluded.amount_due;
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

create or replace function public.v1_get_rental_portfolio()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_result jsonb;
begin
  with current_lease as (
    select * from public.v1_rental_leases where is_current
  ), property_rollup as (
    select p.id, p.unit_code, p.property_name, p.property_type,
      p.municipality_number, p.location, p.description,
      p.occupancy_state, p.is_archived, p.record_version, p.updated_at,
      p.source_metadata,
      coalesce(public.v1_rental_missing_fields_internal(p.id),array[]::text[]) missing_fields,
      public.v1_rental_business_date() business_date,
      l.lease_end-public.v1_rental_business_date() days_to_lease_end,
      (l.id is not null and (l.billing_start is null or l.lease_start is null or l.lease_end is null
        or (case when l.payment_frequency='annual' then l.annual_rent else l.monthly_rent end) is null)) billing_setup_pending,
      exists(select 1 from public.v1_rental_cheques attention_cheque where attention_cheque.property_id=p.id
        and (attention_cheque.status='returned' or (attention_cheque.status in ('scheduled','received','deposited')
          and attention_cheque.cheque_date<=public.v1_rental_business_date()+30))) cheque_attention,
      l.id lease_id, l.contract_number, l.contract_type, l.contract_status,
      l.tenant_name, l.contact_number, l.email, l.trade_licence_number,
      l.lease_start, l.lease_end, l.monthly_rent, l.annual_rent, l.payment_frequency rent_frequency, l.billing_start, l.security_deposit,
      l.monthly_due_day, l.grace_period_days, l.default_payment_method,
      l.annual_escalation_percent, l.renewal_notice_days,
      coalesce(period_rollup.outstanding, 0) outstanding,
      coalesce(period_rollup.current_paid, 0) current_paid,
      coalesce(period_rollup.current_due, 0) current_due,
      cheque_rollup.next_cheque_date,
      cheque_rollup.next_cheque_number
    from public.v1_rental_properties p
    left join current_lease l on l.property_id = p.id
    left join lateral (
      select
        coalesce(sum(case when period_record.due_date <= public.v1_rental_business_date()
          then greatest(period_record.amount_due - coalesce(receipt_rollup.amount_paid, 0), 0)
          else 0 end), 0) outstanding,
        coalesce(sum(case when period_record.lease_id = l.id
          and period_record.period_month = date_trunc('month', public.v1_rental_business_date())::date
          then coalesce(receipt_rollup.amount_paid, 0) else 0 end), 0) current_paid,
        coalesce(sum(case when period_record.lease_id = l.id
          and period_record.period_month = date_trunc('month', public.v1_rental_business_date())::date
          then period_record.amount_due else 0 end), 0) current_due
      from public.v1_rental_periods period_record
      left join lateral (
        select coalesce(sum(receipt_record.amount_received), 0) amount_paid
        from public.v1_rental_receipts receipt_record
        where receipt_record.period_id = period_record.id
      ) receipt_rollup on true
      -- The current tenant does not erase a previous lease's arrears.
      where exists (
        select 1 from public.v1_rental_leases historical_lease
        where historical_lease.id = period_record.lease_id
          and historical_lease.property_id = p.id
      )
    ) period_rollup on true
    left join lateral (
      select cheque_record.cheque_date next_cheque_date,
        cheque_record.cheque_number next_cheque_number
      from public.v1_rental_cheques cheque_record
      where cheque_record.property_id = p.id
        and cheque_record.status in ('scheduled', 'received', 'deposited')
      order by cheque_record.cheque_date, cheque_record.id
      limit 1
    ) cheque_rollup on true
  ), summary as (
    select
      count(*) filter (where not is_archived) total_properties,
      count(*) filter (where not is_archived and occupancy_state = 'occupied') occupied,
      coalesce(sum(monthly_rent) filter (where not is_archived and occupancy_state = 'occupied' and rent_frequency='monthly'), 0) monthly_rent_roll,
      coalesce(sum(annual_rent) filter (where not is_archived and occupancy_state = 'occupied' and rent_frequency='annual'), 0) annual_rent_roll,
      coalesce((select sum(r.amount_received) from public.v1_rental_receipts r
        where date_trunc('month', r.payment_date) = date_trunc('month', public.v1_rental_business_date())), 0) collected_this_month,
      coalesce(sum(outstanding) filter (where not is_archived), 0) outstanding,
      coalesce(sum(security_deposit) filter (where not is_archived), 0) security_deposits,
      count(*) filter (where not is_archived and lease_end between public.v1_rental_business_date()
        and public.v1_rental_business_date() + interval '90 days') expiring_within_90,
      (select count(*) from public.v1_rental_cheques c where c.status in
        ('scheduled','received','deposited','returned') and c.cheque_date <= public.v1_rental_business_date() + 30) cheque_attention
    from property_rollup
  )
  select jsonb_build_object(
    'as_of', clock_timestamp(),
    'business_date',public.v1_rental_business_date(),
    'summary', (select to_jsonb(s) from summary s),
    'properties', coalesce((select jsonb_agg(to_jsonb(pr) order by unit_code)
      from property_rollup pr), '[]'::jsonb),
    'recent_payments', coalesce((select jsonb_agg(to_jsonb(x) order by x.recorded_at desc)
      from (select r.id, r.property_id, p.unit_code, p.property_name,
        r.amount_received, r.payment_date, r.payment_method, r.reference,
        r.recorded_at, coalesce(profile.display_name, 'Unknown user') recorded_by
        from public.v1_rental_receipts r
        join public.v1_rental_properties p on p.id = r.property_id
        left join public.v1_profiles profile on profile.auth_user_id = r.recorded_by_auth_user_id
        order by r.recorded_at desc limit 8) x), '[]'::jsonb),
    'cheques', coalesce((select jsonb_agg(to_jsonb(x) order by x.cheque_date)
      from (select c.*, p.unit_code, p.property_name, l.tenant_name
        from public.v1_rental_cheques c
        join public.v1_rental_properties p on p.id = c.property_id
        join public.v1_rental_leases l on l.id = c.lease_id) x), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.v1_get_rental_property(p_property_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_result jsonb;
begin
  select jsonb_build_object(
    'property', to_jsonb(p),
    'lease', (select to_jsonb(l) from public.v1_rental_leases l
      where l.property_id = p.id and l.is_current limit 1),
    'periods', coalesce((select jsonb_agg(to_jsonb(x) order by x.period_month)
      from (select rp.*, coalesce(sum(r.amount_received), 0) amount_paid,
        rp.amount_due - coalesce(sum(r.amount_received), 0) balance,
        public.v1_rental_period_status(rp.due_date, rp.amount_due,
          coalesce(sum(r.amount_received), 0), coalesce(l.grace_period_days, 0)) status
        from public.v1_rental_periods rp
        join public.v1_rental_leases l on l.id = rp.lease_id
        left join public.v1_rental_receipts r on r.period_id = rp.id
        where l.property_id = p.id group by rp.id, l.grace_period_days) x), '[]'::jsonb),
    'receipts', coalesce((select jsonb_agg(to_jsonb(x) order by x.recorded_at desc)
      from (select r.*, rp.period_month,
        coalesce(profile.display_name, 'Unknown user') recorded_by
        from public.v1_rental_receipts r
        join public.v1_rental_periods rp on rp.id = r.period_id
        left join public.v1_profiles profile on profile.auth_user_id = r.recorded_by_auth_user_id
        where r.property_id = p.id) x), '[]'::jsonb),
    'cheques', coalesce((select jsonb_agg(to_jsonb(c) order by c.cheque_date)
      from public.v1_rental_cheques c where c.property_id = p.id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(to_jsonb(x) order by x.occurred_at desc)
      from (select a.id, a.event_type, a.actor_role, a.occurred_at,
        a.reason, a.after_data,
        coalesce(profile.display_name, 'Unknown user') actor_name
        from public.v1_audit_events a
        left join public.v1_profiles profile on profile.auth_user_id = a.actor_auth_user_id
        where (a.entity_type = 'rental_property' and a.entity_id = p.id)
          or (a.entity_type = 'rental_receipt' and exists
            (select 1 from public.v1_rental_receipts r where r.id = a.entity_id and r.property_id = p.id))
          or (a.entity_type = 'rental_cheque' and exists
            (select 1 from public.v1_rental_cheques c where c.id = a.entity_id and c.property_id = p.id))
        order by a.occurred_at desc) x), '[]'::jsonb)
  ) into v_result
  from public.v1_rental_properties p where p.id = p_property_id;
  if v_result is null then
    raise exception 'V1_RENTAL_PROPERTY_NOT_FOUND' using errcode = 'P0002';
  end if;
  v_result := jsonb_set(v_result,'{property}',(v_result->'property')||jsonb_build_object(
    'outstanding',(select coalesce(sum(greatest((period->>'balance')::numeric,0)),0)
      from jsonb_array_elements(v_result->'periods') period
      where (period->>'due_date')::date<=public.v1_rental_business_date()),
    'current_paid',(select coalesce(sum((period->>'amount_paid')::numeric),0)
      from jsonb_array_elements(v_result->'periods') period
      where period->>'lease_id'=v_result->'lease'->>'id'
        and (period->>'period_month')::date=date_trunc('month',public.v1_rental_business_date())::date),
    'current_due',(select coalesce(sum((period->>'amount_due')::numeric),0)
      from jsonb_array_elements(v_result->'periods') period
      where period->>'lease_id'=v_result->'lease'->>'id'
        and (period->>'period_month')::date=date_trunc('month',public.v1_rental_business_date())::date),
    'missing_fields',public.v1_rental_missing_fields_internal(p_property_id),
    'business_date',public.v1_rental_business_date(),
    'days_to_lease_end',nullif(v_result->'lease'->>'lease_end','')::date-public.v1_rental_business_date(),
    'billing_setup_pending',(v_result->'lease'->>'id' is not null and (
      v_result->'lease'->>'billing_start' is null or v_result->'lease'->>'lease_start' is null
      or v_result->'lease'->>'lease_end' is null or
      case when v_result->'lease'->>'payment_frequency'='annual' then v_result->'lease'->>'annual_rent' else v_result->'lease'->>'monthly_rent' end is null)),
    'rent_frequency',v_result->'lease'->>'payment_frequency',
    'cheque_attention',exists(select 1 from public.v1_rental_cheques c where c.property_id=p_property_id
      and(c.status='returned' or(c.status in('scheduled','received','deposited') and c.cheque_date<=public.v1_rental_business_date()+30)))
  ));
  return v_result;
end;
$$;

create or replace function public.v1_import_rental_workbook(
  p_payload jsonb,
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
  v_entry jsonb;
  v_index bigint;
  v_action text;
  v_unit_code text;
  v_property public.v1_rental_properties%rowtype;
  v_lease public.v1_rental_leases%rowtype;
  v_period public.v1_rental_periods%rowtype;
  v_property_id uuid;
  v_lease_id uuid;
  v_cheque_id uuid;
  v_status text;
  v_response jsonb;
  v_property_count integer := 0;
  v_payment_count integer := 0;
  v_cheque_count integer := 0;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_import_rental_workbook', p_idempotency_key, p_payload
  );
  if v_existing is not null then return v_existing; end if;

  if jsonb_typeof(p_payload) <> 'object'
    or jsonb_typeof(coalesce(p_payload -> 'properties', '[]'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(p_payload -> 'payments', '[]'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(p_payload -> 'cheques', '[]'::jsonb)) <> 'array' then
    raise exception 'V1_RENTAL_IMPORT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_payload -> 'properties', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_payload -> 'payments', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_payload -> 'cheques', '[]'::jsonb)) = 0 then
    raise exception 'V1_RENTAL_IMPORT_EMPTY' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_payload -> 'properties', '[]'::jsonb)) > 1000
    or jsonb_array_length(coalesce(p_payload -> 'payments', '[]'::jsonb)) > 5000
    or jsonb_array_length(coalesce(p_payload -> 'cheques', '[]'::jsonb)) > 5000 then
    raise exception 'V1_RENTAL_IMPORT_TOO_LARGE' using errcode = '54000';
  end if;

  -- Phase 1: validate the complete workbook before any row is applied.
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'properties', '[]'::jsonb)) row_record
    group by upper(btrim(row_record ->> 'unit_code'))
    having count(*) > 1
  ) then
    raise exception 'V1_RENTAL_IMPORT_DUPLICATE_UNIT_CODE' using errcode = '23505';
  end if;

  for v_entry, v_index in
    select value, ordinality
    from jsonb_array_elements(coalesce(p_payload -> 'properties', '[]'::jsonb))
      with ordinality
  loop
    v_action := lower(btrim(coalesce(v_entry ->> 'action', '')));
    v_unit_code := upper(btrim(coalesce(v_entry ->> 'unit_code', '')));
    if v_action not in ('create', 'update')
      or v_unit_code = ''
      or btrim(coalesce(v_entry ->> 'property_name', '')) = ''
      or coalesce(v_entry ->> 'property_type', '') not in
        ('shop', 'store', 'office_store', 'warehouse', 'office', 'labour_camp', 'villa', 'other')
      or coalesce(v_entry->>'occupancy_state',case when coalesce((v_entry->>'occupied')::boolean,false) then 'occupied' else 'vacant' end) not in ('occupied','vacant','unknown') then
      raise exception 'V1_RENTAL_IMPORT_PROPERTY_INVALID_AT_ROW_%',
        coalesce(v_entry ->> 'source_row', v_index::text) using errcode = '22023';
    end if;
    select * into v_property from public.v1_rental_properties
      where unit_code = v_unit_code for update;
    if v_action = 'create' and found then
      raise exception 'V1_RENTAL_IMPORT_CREATE_UNIT_EXISTS_%', v_unit_code
        using errcode = '23505';
    elsif v_action = 'update' and not found then
      raise exception 'V1_RENTAL_IMPORT_UPDATE_UNIT_NOT_FOUND_%', v_unit_code
        using errcode = 'P0002';
    elsif v_action = 'update' and (
      nullif(v_entry ->> 'property_id', '')::uuid is distinct from v_property.id
      or coalesce((v_entry ->> 'expected_version')::integer, 0) <> v_property.record_version
    ) then
      raise exception 'V1_RENTAL_IMPORT_PROPERTY_VERSION_CONFLICT_%', v_unit_code
        using errcode = '40001';
    end if;
    if (nullif(v_entry->>'lease_start','')::date is not null
        and nullif(v_entry->>'lease_end','')::date < nullif(v_entry->>'lease_start','')::date)
      or nullif(v_entry->>'monthly_rent','')::numeric < 0
      or nullif(v_entry->>'annual_rent','')::numeric < 0
      or nullif(v_entry->>'security_deposit','')::numeric < 0
      or coalesce((v_entry->>'monthly_due_day')::integer,1) not between 1 and 31
      or coalesce((v_entry->>'grace_period_days')::integer,5) not between 0 and 90
      or coalesce(nullif(v_entry->>'default_payment_method',''),'bank_transfer') not in ('bank_transfer','cash','cdc','pdc','other')
      or coalesce(nullif(v_entry->>'payment_frequency',''),'monthly') not in ('monthly','annual') then
      raise exception 'V1_RENTAL_IMPORT_LEASE_INVALID_%',v_unit_code using errcode='22023';
    end if;
  end loop;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    where upper(btrim(coalesce(row_record ->> 'unit_code', ''))) = ''
      or nullif(row_record ->> 'rent_period', '') is null
      or nullif(row_record ->> 'payment_date', '') is null
      or coalesce((row_record ->> 'amount_received')::numeric, 0) <= 0
      or coalesce(row_record ->> 'payment_method', '') not in
        ('bank_transfer', 'cash', 'cdc', 'pdc', 'other')
      or (row_record ->> 'payment_method' in ('cdc', 'pdc')
        and btrim(coalesce(row_record ->> 'reference', '')) = '')
  ) then
    raise exception 'V1_RENTAL_IMPORT_PAYMENT_INVALID' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    where not exists (
      select 1
      from public.v1_rental_properties property_record
      join public.v1_rental_leases lease_record
        on lease_record.property_id = property_record.id and lease_record.is_current
      join public.v1_rental_periods period_record
        on period_record.lease_id = lease_record.id
       and period_record.period_month =
         date_trunc('month', (row_record ->> 'rent_period')::date)::date
      where property_record.unit_code = upper(btrim(row_record ->> 'unit_code'))
    ) and not exists (
      select 1 from jsonb_array_elements(coalesce(p_payload -> 'properties', '[]'::jsonb)) property_json
      where upper(btrim(property_json ->> 'unit_code')) = upper(btrim(row_record ->> 'unit_code'))
        and nullif(property_json->>'lease_start','') is not null
        and nullif(property_json->>'lease_end','') is not null
        and date_trunc('month', (row_record ->> 'rent_period')::date)::date between
          date_trunc('month', (property_json ->> 'lease_start')::date)::date and
          date_trunc('month', (property_json ->> 'lease_end')::date)::date
    )
  ) then
    raise exception 'V1_RENTAL_IMPORT_PAYMENT_UNIT_OR_PERIOD_UNKNOWN'
      using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    where nullif(btrim(row_record ->> 'reference'), '') is not null
      and exists (select 1 from public.v1_rental_receipts receipt_record
        where lower(btrim(receipt_record.reference)) = lower(btrim(row_record ->> 'reference')))
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    where nullif(btrim(row_record ->> 'reference'), '') is not null
    group by lower(btrim(row_record ->> 'reference')) having count(*) > 1
  ) then
    raise exception 'V1_RENTAL_IMPORT_DUPLICATE_PAYMENT_REFERENCE'
      using errcode = '23505';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    group by upper(btrim(row_record ->> 'unit_code')),
      date_trunc('month', (row_record ->> 'rent_period')::date)::date,
      (row_record ->> 'amount_received')::numeric,
      (row_record ->> 'payment_date')::date,
      row_record ->> 'payment_method',
      lower(btrim(coalesce(row_record ->> 'reference', '')))
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) row_record
    join public.v1_rental_properties property_record
      on property_record.unit_code = upper(btrim(row_record ->> 'unit_code'))
    join public.v1_rental_leases lease_record
      on lease_record.property_id = property_record.id and lease_record.is_current
    join public.v1_rental_periods period_record
      on period_record.lease_id = lease_record.id
     and period_record.period_month =
       date_trunc('month', (row_record ->> 'rent_period')::date)::date
    join public.v1_rental_receipts receipt_record
      on receipt_record.period_id = period_record.id
     and receipt_record.amount_received = (row_record ->> 'amount_received')::numeric
     and receipt_record.payment_date = (row_record ->> 'payment_date')::date
     and receipt_record.payment_method = row_record ->> 'payment_method'
     and lower(btrim(coalesce(receipt_record.reference, ''))) =
       lower(btrim(coalesce(row_record ->> 'reference', '')))
  ) then
    raise exception 'V1_RENTAL_IMPORT_DUPLICATE_PAYMENT'
      using errcode = '23505';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'cheques', '[]'::jsonb)) row_record
    where upper(btrim(coalesce(row_record ->> 'unit_code', ''))) = ''
      or coalesce(row_record ->> 'cheque_type', '') not in ('cdc', 'pdc')
      or btrim(coalesce(row_record ->> 'cheque_number', '')) = ''
      or btrim(coalesce(row_record ->> 'bank_name', '')) = ''
      or nullif(row_record ->> 'cheque_date', '') is null
      or coalesce((row_record ->> 'amount')::numeric, 0) <= 0
      or coalesce(row_record ->> 'status', '') not in
        ('scheduled', 'received', 'deposited', 'cleared', 'returned', 'cancelled')
  ) then
    raise exception 'V1_RENTAL_IMPORT_CHEQUE_INVALID' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'cheques', '[]'::jsonb)) row_record
    group by upper(btrim(row_record ->> 'unit_code')),
      lower(btrim(row_record ->> 'bank_name')),
      lower(btrim(row_record ->> 'cheque_number'))
    having count(*) > 1
  ) or exists (
    select 1 from jsonb_array_elements(coalesce(p_payload -> 'cheques', '[]'::jsonb)) row_record
    where exists (select 1
      from public.v1_rental_cheques cheque_record
      join public.v1_rental_properties property_record
        on property_record.id = cheque_record.property_id
      where property_record.unit_code = upper(btrim(row_record ->> 'unit_code'))
        and lower(btrim(cheque_record.bank_name)) = lower(btrim(row_record ->> 'bank_name'))
        and lower(btrim(cheque_record.cheque_number)) = lower(btrim(row_record ->> 'cheque_number')))
  ) then
    raise exception 'V1_RENTAL_IMPORT_DUPLICATE_CHEQUE' using errcode = '23505';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'cheques', '[]'::jsonb)) row_record
    where not exists (
      select 1
      from public.v1_rental_properties property_record
      join public.v1_rental_leases lease_record
        on lease_record.property_id = property_record.id and lease_record.is_current
      left join public.v1_rental_periods period_record
        on period_record.lease_id = lease_record.id
       and period_record.period_month =
         date_trunc('month', nullif(row_record ->> 'rent_period', '')::date)::date
      where property_record.unit_code = upper(btrim(row_record ->> 'unit_code'))
        and (nullif(row_record ->> 'rent_period', '') is null or period_record.id is not null)
    ) and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_payload -> 'properties', '[]'::jsonb)) property_json
      where upper(btrim(property_json ->> 'unit_code')) =
        upper(btrim(row_record ->> 'unit_code'))
        and nullif(property_json->>'lease_start','') is not null
        and nullif(property_json->>'lease_end','') is not null
        and (nullif(row_record ->> 'rent_period', '') is null or
          date_trunc('month', (row_record ->> 'rent_period')::date)::date between
            date_trunc('month', (property_json ->> 'lease_start')::date)::date and
            date_trunc('month', (property_json ->> 'lease_end')::date)::date)
    )
  ) then
    raise exception 'V1_RENTAL_IMPORT_CHEQUE_UNIT_OR_PERIOD_UNKNOWN'
      using errcode = 'P0002';
  end if;

  -- Phase 2: apply all rows in the same transaction using deterministic child
  -- command identities. Any failure rolls the whole import back.
  for v_entry, v_index in
    select value, ordinality
    from jsonb_array_elements(coalesce(p_payload -> 'properties', '[]'::jsonb))
      with ordinality
  loop
    v_action := lower(btrim(v_entry ->> 'action'));
    v_unit_code := upper(btrim(v_entry ->> 'unit_code'));
    if v_action = 'create' then
      v_property_id := public.v1_rental_import_child_key(p_idempotency_key, 'property', v_index);
      v_lease_id := public.v1_rental_import_child_key(p_idempotency_key, 'lease', v_index);
      v_entry := v_entry || jsonb_build_object(
        'property_id', v_property_id,
        'lease_id', v_lease_id
      );
    else
      v_property_id := (v_entry ->> 'property_id')::uuid;
    end if;
    perform public.v1_save_rental_property(
      v_entry - 'action' - 'source_row' - 'expected_version',
      case when v_action = 'update' then (v_entry ->> 'expected_version')::integer else null end,
      public.v1_rental_import_child_key(p_idempotency_key, 'save-property', v_index)
    );
    v_property_count := v_property_count + 1;
  end loop;

  for v_entry, v_index in
    select value, ordinality
    from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb))
      with ordinality
  loop
    v_unit_code := upper(btrim(v_entry ->> 'unit_code'));
    select property_record.* into strict v_property
      from public.v1_rental_properties property_record
      where property_record.unit_code = v_unit_code for update;
    select lease_record.* into strict v_lease
      from public.v1_rental_leases lease_record
      where lease_record.property_id = v_property.id and lease_record.is_current
      for update;
    select period_record.* into strict v_period
      from public.v1_rental_periods period_record
      where period_record.lease_id = v_lease.id
        and period_record.period_month = date_trunc('month', (v_entry ->> 'rent_period')::date)::date
      for update;
    perform public.v1_record_rent_payment(
      v_period.id,
      (v_entry ->> 'amount_received')::numeric,
      (v_entry ->> 'payment_date')::date,
      v_entry ->> 'payment_method',
      nullif(btrim(v_entry ->> 'reference'), ''),
      nullif(btrim(v_entry ->> 'note'), ''),
      public.v1_rental_import_child_key(p_idempotency_key, 'payment', v_index)
    );
    v_payment_count := v_payment_count + 1;
  end loop;

  for v_entry, v_index in
    select value, ordinality
    from jsonb_array_elements(coalesce(p_payload -> 'cheques', '[]'::jsonb))
      with ordinality
  loop
    v_unit_code := upper(btrim(v_entry ->> 'unit_code'));
    select property_record.* into strict v_property
      from public.v1_rental_properties property_record
      where property_record.unit_code = v_unit_code for update;
    select lease_record.* into strict v_lease
      from public.v1_rental_leases lease_record
      where lease_record.property_id = v_property.id and lease_record.is_current
      for update;
    v_period.id := null;
    if nullif(v_entry ->> 'rent_period', '') is not null then
      select period_record.* into strict v_period
        from public.v1_rental_periods period_record
        where period_record.lease_id = v_lease.id
          and period_record.period_month = date_trunc('month', (v_entry ->> 'rent_period')::date)::date;
    end if;
    v_cheque_id := public.v1_rental_import_child_key(p_idempotency_key, 'cheque', v_index);
    perform public.v1_save_rental_cheque(
      jsonb_build_object(
        'cheque_id', v_cheque_id, 'property_id', v_property.id,
        'lease_id', v_lease.id,
        'period_id', case when v_period.id is null then null else v_period.id end,
        'cheque_number', v_entry ->> 'cheque_number',
        'cheque_type', v_entry ->> 'cheque_type',
        'bank_name', v_entry ->> 'bank_name',
        'cheque_date', v_entry ->> 'cheque_date',
        'amount', v_entry ->> 'amount', 'note', v_entry ->> 'note'
      ), null,
      public.v1_rental_import_child_key(p_idempotency_key, 'save-cheque', v_index)
    );
    v_status := v_entry ->> 'status';
    if v_status in ('received', 'deposited', 'cleared', 'returned') then
      perform public.v1_transition_rental_cheque(
        v_cheque_id, 1, 'received', null,
        public.v1_rental_import_child_key(p_idempotency_key, 'cheque-received', v_index)
      );
    end if;
    if v_status in ('deposited', 'cleared') then
      perform public.v1_transition_rental_cheque(
        v_cheque_id, 2, 'deposited', null,
        public.v1_rental_import_child_key(p_idempotency_key, 'cheque-deposited', v_index)
      );
    end if;
    if v_status = 'cleared' then
      perform public.v1_transition_rental_cheque(
        v_cheque_id, 3, 'cleared', null,
        public.v1_rental_import_child_key(p_idempotency_key, 'cheque-cleared', v_index)
      );
    elsif v_status = 'returned' then
      perform public.v1_transition_rental_cheque(
        v_cheque_id, 2, 'returned', coalesce(nullif(btrim(v_entry ->> 'note'), ''), 'Imported as returned'),
        public.v1_rental_import_child_key(p_idempotency_key, 'cheque-returned', v_index)
      );
    elsif v_status = 'cancelled' then
      perform public.v1_transition_rental_cheque(
        v_cheque_id, 1, 'cancelled', coalesce(nullif(btrim(v_entry ->> 'note'), ''), 'Imported as cancelled'),
        public.v1_rental_import_child_key(p_idempotency_key, 'cheque-cancelled', v_index)
      );
    end if;
    v_cheque_count := v_cheque_count + 1;
  end loop;

  v_response := jsonb_build_object(
    'properties_applied', v_property_count,
    'payments_applied', v_payment_count,
    'cheques_applied', v_cheque_count,
    'file_name', nullif(btrim(p_payload ->> 'file_name'), '')
  );
  perform public.v1_write_audit_event(
    'rental_workbook_imported', 'rental_import',
    public.v1_rental_import_child_key(p_idempotency_key, 'import-audit', 1),
    null, null, v_response, null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_import_rental_workbook', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_get_rental_export_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_rental_assert_admin();
  v_result jsonb;
begin
  with current_leases as (
    select lease_record.*
    from public.v1_rental_leases lease_record
    where lease_record.is_current
  )
  select jsonb_build_object(
    'generated_at', clock_timestamp(),
    'properties', coalesce((
      select jsonb_agg(jsonb_build_object(
        'Unit Code', property_record.unit_code,
        'Property Name', property_record.property_name,
        'Property Type', replace(initcap(replace(property_record.property_type, '_', ' ')), ' ', ' '),
        'Property / Municipality No.', property_record.municipality_number,
        'Location', property_record.location,
        'Occupancy', initcap(property_record.occupancy_state),
        'Tenant / Company', lease_record.tenant_name,
        'Contract No.', lease_record.contract_number,
        'Contract Status', initcap(lease_record.contract_status),
        'Lease Start', lease_record.lease_start,
        'Lease End', lease_record.lease_end,
        'Monthly Rent AED', lease_record.monthly_rent,
        'Annual Rent AED', lease_record.annual_rent,
        'Rent Frequency',lease_record.payment_frequency,
        'Billing Start',lease_record.billing_start,
        'Missing Fields',array_to_string(public.v1_rental_missing_fields_internal(property_record.id),', '),
        'Source Metadata',property_record.source_metadata::text,
        'Security Deposit AED', lease_record.security_deposit,
        'Archived', property_record.is_archived,
        'Last Updated', property_record.updated_at
      ) order by property_record.unit_code)
      from public.v1_rental_properties property_record
      left join current_leases lease_record
        on lease_record.property_id = property_record.id
    ), '[]'::jsonb),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'Unit Code', property_record.unit_code,
        'Property Name', property_record.property_name,
        'Tenant / Company', lease_record.tenant_name,
        'Rent Period', period_record.period_month,
        'Due Date', period_record.due_date,
        'Amount Due AED', period_record.amount_due,
        'Amount Paid AED', coalesce(receipt_rollup.amount_paid, 0),
        'Outstanding AED', greatest(period_record.amount_due - coalesce(receipt_rollup.amount_paid, 0), 0),
        'Status', public.v1_rental_period_status(
          period_record.due_date, period_record.amount_due,
          coalesce(receipt_rollup.amount_paid, 0), lease_record.grace_period_days
        )
      ) order by property_record.unit_code, period_record.period_month)
      from public.v1_rental_periods period_record
      join public.v1_rental_leases lease_record on lease_record.id = period_record.lease_id
      join public.v1_rental_properties property_record on property_record.id = lease_record.property_id
      left join lateral (
        select sum(receipt_record.amount_received) amount_paid
        from public.v1_rental_receipts receipt_record
        where receipt_record.period_id = period_record.id
      ) receipt_rollup on true
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'Unit Code', property_record.unit_code,
        'Property Name', property_record.property_name,
        'Tenant / Company', lease_record.tenant_name,
        'Rent Period', period_record.period_month,
        'Amount Received AED', receipt_record.amount_received,
        'Payment Date', receipt_record.payment_date,
        'Payment Method', receipt_record.payment_method,
        'Reference', receipt_record.reference,
        'Note', receipt_record.note,
        'Recorded At', receipt_record.recorded_at,
        'Recorded By', coalesce(profile_record.display_name, 'Unknown user')
      ) order by receipt_record.payment_date desc, receipt_record.recorded_at desc)
      from public.v1_rental_receipts receipt_record
      join public.v1_rental_properties property_record on property_record.id = receipt_record.property_id
      join public.v1_rental_leases lease_record on lease_record.id = receipt_record.lease_id
      join public.v1_rental_periods period_record on period_record.id = receipt_record.period_id
      left join public.v1_profiles profile_record
        on profile_record.auth_user_id = receipt_record.recorded_by_auth_user_id
    ), '[]'::jsonb),
    'cheques', coalesce((
      select jsonb_agg(jsonb_build_object(
        'Unit Code', property_record.unit_code,
        'Property Name', property_record.property_name,
        'Tenant / Company', lease_record.tenant_name,
        'Cheque Type', upper(cheque_record.cheque_type),
        'Cheque Number', cheque_record.cheque_number,
        'Bank', cheque_record.bank_name,
        'Linked Rent Period', period_record.period_month,
        'Cheque Date', cheque_record.cheque_date,
        'Amount AED', cheque_record.amount,
        'Status', initcap(cheque_record.status),
        'Note', cheque_record.note,
        'Last Updated', cheque_record.updated_at
      ) order by cheque_record.cheque_date, property_record.unit_code)
      from public.v1_rental_cheques cheque_record
      join public.v1_rental_properties property_record on property_record.id = cheque_record.property_id
      join public.v1_rental_leases lease_record on lease_record.id = cheque_record.lease_id
      left join public.v1_rental_periods period_record on period_record.id = cheque_record.period_id
    ), '[]'::jsonb),
    'lease_expiry', coalesce((
      select jsonb_agg(jsonb_build_object(
        'Unit Code', property_record.unit_code,
        'Property Name', property_record.property_name,
        'Tenant / Company', lease_record.tenant_name,
        'Contract No.', lease_record.contract_number,
        'Contract Status', initcap(lease_record.contract_status),
        'Lease End', lease_record.lease_end,
        'Days Remaining', lease_record.lease_end - public.v1_rental_business_date(),
        'Renewal Notice Days', lease_record.renewal_notice_days,
        'Renewal Status', case
          when lease_record.lease_end < public.v1_rental_business_date() then 'Expired'
          when lease_record.lease_end <= public.v1_rental_business_date() + lease_record.renewal_notice_days then 'Notice Due'
          else 'Current'
        end
      ) order by lease_record.lease_end, property_record.unit_code)
      from current_leases lease_record
      join public.v1_rental_properties property_record on property_record.id = lease_record.property_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.v1_archive_rental_property(
  p_property_id uuid,
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
  v_actor uuid := public.v1_rental_assert_admin();
  v_existing jsonb;
  v_property public.v1_rental_properties%rowtype;
  v_outstanding numeric(16,2);
  v_response jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_archive_rental_property', p_idempotency_key,
    jsonb_build_object('property_id', p_property_id,
      'expected_version', p_expected_version, 'reason', p_reason)
  );
  if v_existing is not null then return v_existing; end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'V1_RENTAL_ARCHIVE_REASON_REQUIRED' using errcode = '22023';
  end if;
  select * into strict v_property from public.v1_rental_properties
  where id = p_property_id for update;
  if p_expected_version is null
    or p_expected_version <> v_property.record_version then
    raise exception 'V1_RENTAL_PROPERTY_VERSION_CONFLICT' using errcode = '40001';
  end if;
  -- Future-period prepayments cannot offset another period's unpaid rent.
  select coalesce(sum(greatest(period_record.amount_due - coalesce((
      select sum(receipt_record.amount_received)
      from public.v1_rental_receipts receipt_record
      where receipt_record.period_id = period_record.id
    ), 0), 0)), 0)
  into v_outstanding
  from public.v1_rental_periods period_record
  join public.v1_rental_leases lease_record on lease_record.id = period_record.lease_id
  where lease_record.property_id = p_property_id
    and period_record.due_date <= public.v1_rental_business_date();
  if v_outstanding > 0
    or exists (select 1 from public.v1_rental_leases l
      where l.property_id = p_property_id and l.is_current
        and l.contract_status in ('draft', 'active', 'notice_due')
        and l.billing_start is not null)
    or exists (select 1 from public.v1_rental_cheques c
      where c.property_id = p_property_id
        and c.status in ('scheduled', 'received', 'deposited', 'returned')) then
    raise exception 'V1_RENTAL_ARCHIVE_BLOCKED_BY_OPEN_OBLIGATION'
      using errcode = '23514';
  end if;
  update public.v1_rental_properties set
    is_archived = true, record_version = record_version + 1,
    archived_by_auth_user_id = v_actor, archived_at = clock_timestamp(),
    archive_reason = btrim(p_reason), updated_by_auth_user_id = v_actor,
    updated_at = clock_timestamp()
  where id = p_property_id returning * into v_property;
  v_response := jsonb_build_object(
    'property_id', p_property_id, 'record_version', v_property.record_version,
    'archived', true
  );
  perform public.v1_write_audit_event(
    'rental_property_archived', 'rental_property', p_property_id,
    null, null, v_response, p_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_archive_rental_property', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

create or replace function public.v1_rental_period_status(
  p_due_date date,
  p_amount_due numeric,
  p_amount_paid numeric,
  p_grace_days integer
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_amount_paid >= p_amount_due then 'paid'
    when public.v1_rental_business_date() > p_due_date + p_grace_days then 'overdue'
    when p_amount_paid > 0 then 'partially_paid'
    when public.v1_rental_business_date() >= p_due_date then 'due'
    else 'upcoming'
  end
$$;

revoke all on function public.v1_rental_missing_fields_internal(uuid) from public,anon,authenticated;
grant execute on function public.v1_rental_missing_fields_internal(uuid) to service_role;
revoke all on function public.v1_rental_missing_fields(uuid) from public,anon;
grant execute on function public.v1_rental_missing_fields(uuid) to authenticated;
revoke all on function public.v1_rental_business_date() from public,anon;
grant execute on function public.v1_rental_business_date() to authenticated,service_role;
commit;

-- Rental safety corrections only: no historical row, balance, receipt, cheque,
-- document, or legacy collection is migrated, removed, or reinterpreted.
-- Existing function ACLs remain in force. Commands keep the same signatures.
-- Rollback: restore the previous function bodies only after review; retain every
-- domain/audit/idempotency row and schedule identifier. No table rollback/drop.

begin;

create or replace function public.v1_rental_assert_admin()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or public.v1_current_role() <> 'admin'
    or not public.v1_current_actor_is_active() then
    raise exception 'V1_RENTAL_ADMIN_REQUIRED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

create or replace function public.v1_rental_replace_unpaid_schedule(
  p_lease_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lease public.v1_rental_leases%rowtype;
begin
  select * into strict v_lease
  from public.v1_rental_leases where id = p_lease_id for update;

  if exists (
    select 1 from public.v1_rental_receipts receipt_record
    where receipt_record.lease_id = p_lease_id
  ) then
    raise exception 'V1_RENTAL_PAID_SCHEDULE_CANNOT_BE_REBUILT'
      using errcode = '23514';
  end if;

  if exists (
    select 1 from public.v1_rental_cheques cheque_record
    join public.v1_rental_periods period_record
      on period_record.id = cheque_record.period_id
    where period_record.lease_id = p_lease_id
  ) then
    raise exception 'V1_RENTAL_LINKED_SCHEDULE_CANNOT_BE_REBUILT'
      using errcode = '23514';
  end if;

  -- Preserve IDs for retained months. Only unreferenced months outside the
  -- explicitly revised lease range may be removed.
  delete from public.v1_rental_periods
  where lease_id = p_lease_id and period_month not between
    date_trunc('month', v_lease.lease_start)::date and
    date_trunc('month', v_lease.lease_end)::date;
  insert into public.v1_rental_periods (
    id, lease_id, period_month, due_date, amount_due
  )
  select
    gen_random_uuid(),
    p_lease_id,
    month_value::date,
    (
      month_value::date
      + (least(
          v_lease.monthly_due_day,
          extract(day from (
            month_value + interval '1 month - 1 day'
          ))::integer
        ) - 1)
    )::date,
    v_lease.monthly_rent
  from generate_series(
    date_trunc('month', v_lease.lease_start)::date,
    date_trunc('month', v_lease.lease_end)::date,
    interval '1 month'
  ) month_value
  on conflict (lease_id, period_month) do update set
    due_date = excluded.due_date,
    amount_due = excluded.amount_due;
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
  v_lease_id uuid := coalesce(
    nullif(p_payload ->> 'lease_id', '')::uuid, gen_random_uuid()
  );
  v_occupied boolean := coalesce((p_payload ->> 'occupied')::boolean, false);
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

  if btrim(coalesce(p_payload ->> 'unit_code', '')) = ''
    or btrim(coalesce(p_payload ->> 'property_name', '')) = ''
    or btrim(coalesce(p_payload ->> 'location', '')) = '' then
    raise exception 'V1_RENTAL_PROPERTY_REQUIRED_FIELDS'
      using errcode = '22023';
  end if;

  select property_record.*
  into v_property
  from public.v1_rental_properties property_record
  where property_record.id = v_property_id
  for update;

  if found then
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
    update public.v1_rental_properties set
      unit_code = upper(btrim(p_payload ->> 'unit_code')),
      property_name = btrim(p_payload ->> 'property_name'),
      property_type = p_payload ->> 'property_type',
      municipality_number = nullif(btrim(p_payload ->> 'municipality_number'), ''),
      location = btrim(p_payload ->> 'location'),
      description = nullif(btrim(p_payload ->> 'description'), ''),
      occupancy_state = case when v_occupied then 'occupied' else 'vacant' end,
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
      location, description, occupancy_state, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_property_id, upper(btrim(p_payload ->> 'unit_code')),
      btrim(p_payload ->> 'property_name'), p_payload ->> 'property_type',
      nullif(btrim(p_payload ->> 'municipality_number'), ''),
      btrim(p_payload ->> 'location'),
      nullif(btrim(p_payload ->> 'description'), ''),
      case when v_occupied then 'occupied' else 'vacant' end,
      v_actor, v_actor
    ) returning * into v_property;
  end if;

  if v_occupied then
    if btrim(coalesce(p_payload ->> 'tenant_name', '')) = ''
      or btrim(coalesce(p_payload ->> 'contract_number', '')) = ''
      or nullif(p_payload ->> 'lease_start', '') is null
      or nullif(p_payload ->> 'lease_end', '') is null then
      raise exception 'V1_RENTAL_OCCUPIED_LEASE_REQUIRED'
        using errcode = '22023';
    end if;

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
      v_schedule_changed := row(
        v_existing_lease.lease_start, v_existing_lease.lease_end,
        v_existing_lease.monthly_rent, v_existing_lease.monthly_due_day
      ) is distinct from row(
        (p_payload ->> 'lease_start')::date,
        (p_payload ->> 'lease_end')::date,
        coalesce((p_payload ->> 'monthly_rent')::numeric, 0),
        coalesce((p_payload ->> 'monthly_due_day')::integer, 1)
      );
    else
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
      renewal_notice_days, notes, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_lease_id, v_property_id, btrim(p_payload ->> 'contract_number'),
      coalesce(nullif(p_payload ->> 'contract_type', ''), 'tenancy_contract'),
      coalesce(nullif(p_payload ->> 'contract_status', ''), 'draft'),
      btrim(p_payload ->> 'tenant_name'),
      nullif(btrim(p_payload ->> 'trade_licence_number'), ''),
      nullif(btrim(p_payload ->> 'contact_number'), ''),
      nullif(btrim(p_payload ->> 'email'), ''),
      nullif(p_payload ->> 'signed_date', '')::date,
      (p_payload ->> 'lease_start')::date,
      (p_payload ->> 'lease_end')::date,
      coalesce((p_payload ->> 'monthly_rent')::numeric, 0),
      coalesce((p_payload ->> 'security_deposit')::numeric, 0),
      coalesce((p_payload ->> 'monthly_due_day')::integer, 1),
      coalesce((p_payload ->> 'grace_period_days')::integer, 5),
      coalesce(nullif(p_payload ->> 'default_payment_method', ''), 'bank_transfer'),
      coalesce(nullif(p_payload ->> 'payment_frequency', ''), 'monthly'),
      coalesce((p_payload ->> 'contract_cheque_count')::integer, 0),
      coalesce((p_payload ->> 'annual_escalation_percent')::numeric, 0),
      coalesce((p_payload ->> 'renewal_notice_days')::integer, 90),
      nullif(btrim(p_payload ->> 'lease_notes'), ''), v_actor, v_actor
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
  elsif exists (
    select 1 from public.v1_rental_leases lease_record
    where lease_record.property_id = v_property_id and lease_record.is_current
      and lease_record.contract_status not in ('terminated', 'expired', 'renewed')
  ) then
    raise exception 'V1_RENTAL_END_ACTIVE_LEASE_FIRST'
      using errcode = '23514';
  end if;

  v_response := jsonb_build_object(
    'property_id', v_property_id,
    'lease_id', case when v_occupied then v_lease_id else null end,
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
    or coalesce((p_payload ->> 'amount')::numeric, 0) <= 0 then
    raise exception 'V1_RENTAL_CHEQUE_REQUIRED_FIELDS'
      using errcode = '22023';
  end if;
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

create or replace function public.v1_transition_rental_cheque(
  p_cheque_id uuid,
  p_expected_version integer,
  p_next_status text,
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
  v_cheque public.v1_rental_cheques%rowtype;
  v_allowed boolean := false;
  v_response jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_transition_rental_cheque', p_idempotency_key,
    jsonb_build_object('cheque_id', p_cheque_id,
      'expected_version', p_expected_version, 'next_status', p_next_status,
      'reason', p_reason)
  );
  if v_existing is not null then return v_existing; end if;
  select * into strict v_cheque from public.v1_rental_cheques
  where id = p_cheque_id for update;
  if p_expected_version is null
    or p_expected_version <> v_cheque.record_version then
    raise exception 'V1_RENTAL_CHEQUE_VERSION_CONFLICT' using errcode = '40001';
  end if;
  v_allowed := case v_cheque.status
    when 'scheduled' then p_next_status in ('received', 'cancelled')
    when 'received' then p_next_status in ('deposited', 'returned', 'cancelled')
    when 'deposited' then p_next_status in ('cleared', 'returned')
    when 'returned' then p_next_status in ('received', 'cancelled')
    else false end;
  if not v_allowed then
    raise exception 'V1_RENTAL_CHEQUE_TRANSITION_INVALID' using errcode = '23514';
  end if;
  if p_next_status in ('returned', 'cancelled')
    and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'V1_RENTAL_CHEQUE_REASON_REQUIRED' using errcode = '22023';
  end if;
  update public.v1_rental_cheques set
    status = p_next_status, note = coalesce(nullif(btrim(p_reason), ''), note),
    record_version = record_version + 1,
    updated_by_auth_user_id = v_actor, updated_at = clock_timestamp()
  where id = p_cheque_id returning * into v_cheque;
  v_response := jsonb_build_object(
    'cheque_id', p_cheque_id, 'status', v_cheque.status,
    'record_version', v_cheque.record_version
  );
  perform public.v1_write_audit_event(
    'rental_cheque_status_changed', 'rental_cheque', p_cheque_id,
    null, null, v_response, p_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_transition_rental_cheque', p_idempotency_key, v_response
  );
  return v_response;
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
    and period_record.due_date <= current_date;
  if v_outstanding > 0
    or exists (select 1 from public.v1_rental_leases l
      where l.property_id = p_property_id and l.is_current
        and l.contract_status in ('draft', 'active', 'notice_due'))
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
      l.id lease_id, l.contract_number, l.contract_type, l.contract_status,
      l.tenant_name, l.contact_number, l.email, l.trade_licence_number,
      l.lease_start, l.lease_end, l.monthly_rent, l.security_deposit,
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
        coalesce(sum(case when period_record.due_date <= current_date
          then greatest(period_record.amount_due - coalesce(receipt_rollup.amount_paid, 0), 0)
          else 0 end), 0) outstanding,
        coalesce(sum(case when period_record.lease_id = l.id
          and period_record.period_month = date_trunc('month', current_date)::date
          then coalesce(receipt_rollup.amount_paid, 0) else 0 end), 0) current_paid,
        coalesce(sum(case when period_record.lease_id = l.id
          and period_record.period_month = date_trunc('month', current_date)::date
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
      coalesce(sum(monthly_rent) filter (where not is_archived and occupancy_state = 'occupied'), 0) monthly_rent_roll,
      coalesce((select sum(r.amount_received) from public.v1_rental_receipts r
        where date_trunc('month', r.payment_date) = date_trunc('month', current_date)), 0) collected_this_month,
      coalesce(sum(outstanding) filter (where not is_archived), 0) outstanding,
      coalesce(sum(security_deposit) filter (where not is_archived), 0) security_deposits,
      count(*) filter (where not is_archived and lease_end between current_date
        and current_date + interval '90 days') expiring_within_90,
      (select count(*) from public.v1_rental_cheques c where c.status in
        ('scheduled','received','deposited','returned') and c.cheque_date <= current_date + 30) cheque_attention
    from property_rollup
  )
  select jsonb_build_object(
    'as_of', clock_timestamp(),
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

-- A recovery read reports only this active Admin actor's completion state.
-- Missing/in-flight rows remain unconfirmed; callers must retain the key.
create or replace function public.v1_get_rental_command_outcome(
  p_command_name text,p_idempotency_key uuid
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=public.v1_rental_assert_admin();v_response jsonb;
begin
  if p_idempotency_key is null or p_command_name is null or p_command_name not in (
    'v1_save_rental_property','v1_record_rent_payment','v1_save_rental_cheque',
    'v1_transition_rental_cheque','v1_archive_rental_property','v1_import_rental_workbook'
  ) then
    raise exception 'V1_RENTAL_COMMAND_INVALID' using errcode='22023';
  end if;
  select response_json into v_response from public.v1_idempotency_keys
  where actor_auth_user_id=v_actor and command_name=p_command_name
    and idempotency_key=p_idempotency_key;
  return jsonb_build_object('state',case when v_response is not null then 'confirmed' else 'unconfirmed' end);
end;
$$;
revoke all on function public.v1_get_rental_command_outcome(text,uuid) from public,anon;
grant execute on function public.v1_get_rental_command_outcome(text,uuid) to authenticated;

commit;

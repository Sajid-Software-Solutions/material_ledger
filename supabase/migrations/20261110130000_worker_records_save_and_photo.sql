-- Worker Records slice 2: create/update a record and set a photo
-- (PRODUCT_DECISIONS.md section 33).
--
-- Both commands require `worker_records.manage`, lock the worker row, check
-- the expected record version, are retry-safe through the shared idempotency
-- ledger and append one protected revision. The idempotency ledger and the
-- general audit trail store identifiers and changed field names only, never a
-- salary or passport value.
--
-- On an existing worker this command may correct the name, company and
-- designation. It never changes status, dates, trade, type or assignments;
-- those stay with Workforce Administration and its own checks.
--
-- Data preservation: additive only (one sequence, three functions). Rollback:
-- revoke execute on the two public functions; retain all rows and photos.

begin;

create sequence if not exists public.v1_worker_record_number_seq;
revoke all on sequence public.v1_worker_record_number_seq
  from public, anon, authenticated;

-- Internal: the full protected row as JSON, for revisions only.
create or replace function public.v1_worker_employment_record_snapshot(
  p_worker_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'full_name', worker.full_name,
    'designation', worker.designation,
    'employer_company', worker.employer_company,
    'trade_license_no', record.trade_license_no,
    'passport_no', record.passport_no,
    'basic_salary', record.basic_salary,
    'housing_allowance', record.housing_allowance,
    'other_allowance', record.other_allowance,
    'photo_object_path', record.photo_object_path,
    'record_version', record.record_version
  )
  from public.v1_workforce_workers worker
  left join public.v1_worker_employment_records record
    on record.worker_id = worker.id
  where worker.id = p_worker_id;
$$;

-- Internal: parse an optional non-negative amount with at most two decimals.
create or replace function public.v1_worker_record_amount(
  p_payload jsonb,
  p_key text
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text := btrim(coalesce(p_payload ->> p_key, ''));
begin
  if v_text = '' then
    return null;
  end if;
  if v_text !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then
    raise exception 'V1_WORKER_RECORD_AMOUNT_INVALID' using errcode = '22023';
  end if;
  return v_text::numeric;
end;
$$;

create or replace function public.v1_save_worker_record(
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_worker_records_assert('worker_records.manage');
  v_role text := public.v1_permission_exact_role(v_actor);
  v_existing jsonb;
  v_worker_id uuid;
  v_is_new_worker boolean := false;
  v_worker public.v1_workforce_workers%rowtype;
  v_record public.v1_worker_employment_records%rowtype;
  v_has_record boolean;
  v_full_name text := btrim(coalesce(p_payload ->> 'full_name', ''));
  v_designation text := btrim(coalesce(p_payload ->> 'designation', ''));
  v_company text := btrim(coalesce(p_payload ->> 'employer_company', ''));
  v_license text := nullif(btrim(coalesce(
    p_payload ->> 'trade_license_no', '')), '');
  v_passport text := nullif(upper(btrim(coalesce(
    p_payload ->> 'passport_no', ''))), '');
  v_basic numeric;
  v_housing numeric;
  v_other numeric;
  v_joining_date date;
  v_before jsonb;
  v_after jsonb;
  v_changed text[];
  v_version bigint;
begin
  if p_idempotency_key is null then
    raise exception 'V1_WORKER_RECORD_IDEMPOTENCY_REQUIRED'
      using errcode = '22023';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'worker_id', 'full_name', 'designation', 'employer_company',
      'joining_date', 'trade_license_no', 'passport_no', 'basic_salary',
      'housing_allowance', 'other_allowance'
    ],
    'save_worker_record_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_worker_record', p_idempotency_key,
    jsonb_build_object(
      'payload', p_payload, 'expected_version', p_expected_version
    )
  );
  if v_existing is not null then
    -- The ledger holds identifiers only; rebuild the protected projection.
    return public.v1_worker_record_json((v_existing ->> 'worker_id')::uuid)
      || jsonb_build_object('schema_version', 1);
  end if;

  begin
    v_worker_id := nullif(btrim(coalesce(
      p_payload ->> 'worker_id', '')), '')::uuid;
    v_joining_date := nullif(btrim(coalesce(
      p_payload ->> 'joining_date', '')), '')::date;
  exception when invalid_text_representation or datetime_field_overflow
    or invalid_datetime_format then
    raise exception 'V1_WORKER_RECORD_REFERENCE_INVALID'
      using errcode = '22023';
  end;
  v_basic := public.v1_worker_record_amount(p_payload, 'basic_salary');
  v_housing := public.v1_worker_record_amount(p_payload, 'housing_allowance');
  v_other := public.v1_worker_record_amount(p_payload, 'other_allowance');

  if v_full_name = '' or v_designation = '' or v_company = ''
    or char_length(v_full_name) > 180 or char_length(v_designation) > 120
    or char_length(v_company) > 180
    or char_length(coalesce(v_license, '')) > 60
    or char_length(coalesce(v_passport, '')) > 40
  then
    raise exception 'V1_WORKER_RECORD_REQUIRED_FIELDS' using errcode = '22023';
  end if;

  if v_worker_id is null then
    -- A new worker. Status, type and number take safe defaults; Workforce
    -- Administration remains the place to change them afterwards.
    if p_expected_version is not null then
      raise exception 'V1_WORKER_RECORD_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_joining_date is null then
      raise exception 'V1_WORKER_RECORD_REQUIRED_FIELDS'
        using errcode = '22023';
    end if;
    v_is_new_worker := true;
    insert into public.v1_workforce_workers (
      worker_number, full_name, designation, employer_company, worker_type,
      joining_date, created_by_auth_user_id, updated_by_auth_user_id
    ) values (
      'WR-' || lpad(
        nextval('public.v1_worker_record_number_seq')::text, 6, '0'
      ),
      v_full_name, v_designation, v_company, 'yorks_employee',
      v_joining_date, v_actor, v_actor
    ) returning * into v_worker;
    v_worker_id := v_worker.id;
  else
    select worker.* into v_worker
    from public.v1_workforce_workers worker
    where worker.id = v_worker_id
    for update;
    if not found then
      raise exception 'V1_WORKER_RECORD_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  select record.* into v_record
  from public.v1_worker_employment_records record
  where record.worker_id = v_worker_id
  for update;
  v_has_record := found;
  if not v_is_new_worker
    and coalesce(p_expected_version, -1)
      <> (case when v_has_record then v_record.record_version else 0 end)
  then
    perform public.v1_raise_version_conflict(
      'V1_WORKER_RECORD_VERSION_CONFLICT'
    );
  end if;

  v_before := case when v_is_new_worker then null
    else public.v1_worker_employment_record_snapshot(v_worker_id) end;

  if not v_is_new_worker and (
    v_worker.full_name is distinct from v_full_name
    or v_worker.designation is distinct from v_designation
    or v_worker.employer_company is distinct from v_company
  ) then
    update public.v1_workforce_workers set
      full_name = v_full_name,
      designation = v_designation,
      employer_company = v_company,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_at = clock_timestamp()
    where id = v_worker_id;
  end if;

  begin
    if v_has_record then
      update public.v1_worker_employment_records set
        trade_license_no = v_license,
        passport_no = v_passport,
        basic_salary = v_basic,
        housing_allowance = v_housing,
        other_allowance = v_other,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_by_role = v_role,
        updated_at = clock_timestamp()
      where worker_id = v_worker_id
      returning record_version into v_version;
    else
      insert into public.v1_worker_employment_records (
        worker_id, trade_license_no, passport_no, basic_salary,
        housing_allowance, other_allowance, created_by_auth_user_id,
        updated_by_auth_user_id, updated_by_role
      ) values (
        v_worker_id, v_license, v_passport, v_basic, v_housing, v_other,
        v_actor, v_actor, v_role
      ) returning record_version into v_version;
    end if;
  exception when unique_violation then
    raise exception 'V1_WORKER_RECORD_PASSPORT_DUPLICATE'
      using errcode = '23505';
  end;

  v_after := public.v1_worker_employment_record_snapshot(v_worker_id);
  select coalesce(array_agg(field.key order by field.key), '{}'::text[])
  into v_changed
  from jsonb_each(v_after) field
  where field.key <> 'record_version'
    and field.value is distinct from coalesce(v_before -> field.key, 'null');

  insert into public.v1_worker_employment_record_revisions (
    worker_id, record_version, change_kind, before_data, after_data,
    actor_auth_user_id, actor_role, idempotency_key
  ) values (
    v_worker_id, v_version,
    case when v_has_record then 'updated' else 'created' end,
    v_before, v_after, v_actor, v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    case when v_has_record then 'worker_record_updated'
      else 'worker_record_created' end,
    'worker_employment_record', v_worker_id, null, null,
    jsonb_build_object(
      'record_version', v_version,
      'new_worker', v_is_new_worker,
      'changed_fields', to_jsonb(v_changed)
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_save_worker_record', p_idempotency_key,
    jsonb_build_object('worker_id', v_worker_id, 'record_version', v_version)
  );
  return public.v1_worker_record_json(v_worker_id)
    || jsonb_build_object('schema_version', 1);
end;
$$;

create or replace function public.v1_set_worker_photo(
  p_worker_id uuid,
  p_object_path text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_worker_records_assert('worker_records.manage');
  v_role text := public.v1_permission_exact_role(v_actor);
  v_existing jsonb;
  v_record public.v1_worker_employment_records%rowtype;
  v_has_record boolean;
  v_before jsonb;
  v_version bigint;
begin
  if p_idempotency_key is null or p_worker_id is null then
    raise exception 'V1_WORKER_RECORD_REFERENCE_INVALID'
      using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_set_worker_photo', p_idempotency_key,
    jsonb_build_object(
      'worker_id', p_worker_id, 'object_path', p_object_path,
      'expected_version', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_worker_record_json(p_worker_id)
      || jsonb_build_object('schema_version', 1);
  end if;

  -- The path must name this worker and the object must already be stored.
  if public.v1_worker_photo_path_worker_id(
      'yorks-worker-photos', p_object_path
    ) is distinct from p_worker_id
    or not exists (
      select 1 from storage.objects stored
      where stored.bucket_id = 'yorks-worker-photos'
        and stored.name = p_object_path
    )
  then
    raise exception 'V1_WORKER_PHOTO_INVALID' using errcode = '22023';
  end if;

  perform 1 from public.v1_workforce_workers worker
  where worker.id = p_worker_id for update;
  if not found then
    raise exception 'V1_WORKER_RECORD_NOT_FOUND' using errcode = 'P0002';
  end if;
  select record.* into v_record
  from public.v1_worker_employment_records record
  where record.worker_id = p_worker_id
  for update;
  v_has_record := found;
  if coalesce(p_expected_version, -1)
    <> (case when v_has_record then v_record.record_version else 0 end)
  then
    perform public.v1_raise_version_conflict(
      'V1_WORKER_RECORD_VERSION_CONFLICT'
    );
  end if;
  v_before := public.v1_worker_employment_record_snapshot(p_worker_id);

  if v_has_record then
    update public.v1_worker_employment_records set
      photo_object_path = p_object_path,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where worker_id = p_worker_id
    returning record_version into v_version;
  else
    insert into public.v1_worker_employment_records (
      worker_id, photo_object_path, created_by_auth_user_id,
      updated_by_auth_user_id, updated_by_role
    ) values (
      p_worker_id, p_object_path, v_actor, v_actor, v_role
    ) returning record_version into v_version;
  end if;

  insert into public.v1_worker_employment_record_revisions (
    worker_id, record_version, change_kind, before_data, after_data,
    actor_auth_user_id, actor_role, idempotency_key
  ) values (
    p_worker_id, v_version, 'photo_set', v_before,
    public.v1_worker_employment_record_snapshot(p_worker_id),
    v_actor, v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    'worker_record_photo_set', 'worker_employment_record', p_worker_id,
    null, null,
    jsonb_build_object(
      'record_version', v_version,
      'changed_fields', jsonb_build_array('photo_object_path')
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_set_worker_photo', p_idempotency_key,
    jsonb_build_object('worker_id', p_worker_id, 'record_version', v_version)
  );
  return public.v1_worker_record_json(p_worker_id)
    || jsonb_build_object('schema_version', 1);
end;
$$;

revoke all on function public.v1_worker_employment_record_snapshot(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_worker_record_amount(jsonb, text)
  from public, anon, authenticated;
revoke all on function public.v1_save_worker_record(jsonb, bigint, uuid)
  from public, anon;
revoke all on function public.v1_set_worker_photo(uuid, text, bigint, uuid)
  from public, anon;
grant execute on function public.v1_save_worker_record(jsonb, bigint, uuid)
  to authenticated;
grant execute on function public.v1_set_worker_photo(uuid, text, bigint, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;

-- Worker Records slice 3: Excel import with a server preview
-- (PRODUCT_DECISIONS.md section 33).
--
-- One internal routine classifies every sheet row; the read-only preview and
-- the all-or-nothing import both use it, so they cannot disagree.
--
-- Matching, in order:
--   1. passport number (normalized) -> that worker, provided the names match;
--   2. otherwise exact normalized name + company -> that worker;
--   3. otherwise a new worker.
-- A passport held by a differently named worker, a matched worker whose
-- stored passport differs, two workers with the same name and company, and a
-- row repeated in the file are row errors. Any row error blocks the import.
--
-- An import never changes an existing worker's name, company, status, dates
-- or assignments, and a blank cell never erases a stored value.
--
-- Data preservation: additive only (three functions). Rollback: revoke
-- execute on the two public functions; imported rows remain ordinary records
-- with their revisions.

begin;

create or replace function public.v1_worker_import_normalized(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(btrim(coalesce(p_value, '')), '\s+', ' ', 'g'));
$$;

-- Internal. Returns one classification object per input row, in input order.
create or replace function public.v1_worker_import_classify(p_rows jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_index integer := 0;
  v_result jsonb := '[]'::jsonb;
  v_errors text[];
  v_changed text[];
  v_name text;
  v_company text;
  v_passport text;
  v_license text;
  v_amount_key text;
  v_amounts jsonb;
  v_worker_id uuid;
  v_worker_name text;
  v_match_count integer;
  v_record public.v1_worker_employment_records%rowtype;
  v_has_record boolean;
  v_action text;
  v_seen_passports text[] := '{}';
  v_seen_identities text[] := '{}';
begin
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'V1_WORKER_IMPORT_ROWS_INVALID' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 500 then
    raise exception 'V1_WORKER_IMPORT_ROW_COUNT_INVALID'
      using errcode = '22023';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_row) <> 'object' then
      raise exception 'V1_WORKER_IMPORT_ROWS_INVALID' using errcode = '22023';
    end if;
    perform public.v1_assert_object_keys(
      v_row,
      array[
        'row_number', 'full_name', 'employer_company', 'trade_license_no',
        'passport_no', 'basic_salary', 'housing_allowance', 'other_allowance'
      ],
      'import_worker_record_row'
    );
    v_errors := '{}';
    v_changed := '{}';
    v_worker_id := null;
    v_worker_name := null;
    v_has_record := false;
    v_name := btrim(coalesce(v_row ->> 'full_name', ''));
    v_company := btrim(coalesce(v_row ->> 'employer_company', ''));
    v_passport := nullif(upper(btrim(coalesce(v_row ->> 'passport_no', ''))), '');
    v_license := nullif(btrim(coalesce(v_row ->> 'trade_license_no', '')), '');

    if v_name = '' then v_errors := array_append(v_errors, 'name_required'); end if;
    if v_company = '' then v_errors := array_append(v_errors, 'company_required'); end if;
    if char_length(v_name) > 180 or char_length(v_company) > 180
      or char_length(coalesce(v_passport, '')) > 40
      or char_length(coalesce(v_license, '')) > 60 then
      v_errors := array_append(v_errors, 'field_too_long');
    end if;
    v_amounts := '{}'::jsonb;
    foreach v_amount_key in array array[
      'basic_salary', 'housing_allowance', 'other_allowance'
    ] loop
      if btrim(coalesce(v_row ->> v_amount_key, '')) <> ''
        and btrim(v_row ->> v_amount_key) !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$'
      then
        v_errors := array_append(v_errors, 'amount_invalid');
        exit;
      end if;
      v_amounts := v_amounts || jsonb_build_object(
        v_amount_key,
        nullif(btrim(coalesce(v_row ->> v_amount_key, '')), '')::numeric
      );
    end loop;

    -- The same person twice in one file.
    if v_passport is not null then
      if v_passport = any(v_seen_passports) then
        v_errors := array_append(v_errors, 'duplicate_in_file');
      end if;
      v_seen_passports := array_append(v_seen_passports, v_passport);
    end if;
    if v_name <> '' and v_company <> '' then
      if public.v1_worker_import_normalized(v_name) || '|'
          || public.v1_worker_import_normalized(v_company)
        = any(v_seen_identities)
        and not ('duplicate_in_file' = any(v_errors)) then
        v_errors := array_append(v_errors, 'duplicate_in_file');
      end if;
      v_seen_identities := array_append(
        v_seen_identities,
        public.v1_worker_import_normalized(v_name) || '|'
          || public.v1_worker_import_normalized(v_company)
      );
    end if;

    if cardinality(v_errors) = 0 then
      -- 1. Passport match.
      if v_passport is not null then
        select worker.id, worker.full_name into v_worker_id, v_worker_name
        from public.v1_worker_employment_records record
        join public.v1_workforce_workers worker on worker.id = record.worker_id
        where upper(btrim(record.passport_no)) = v_passport;
        if v_worker_id is not null
          and public.v1_worker_import_normalized(v_worker_name)
            <> public.v1_worker_import_normalized(v_name) then
          v_errors := array_append(v_errors, 'passport_other_worker');
        end if;
      end if;
      -- 2. Name + company match.
      if v_worker_id is null then
        select count(*), min(worker.id::text)::uuid
        into v_match_count, v_worker_id
        from public.v1_workforce_workers worker
        where public.v1_worker_import_normalized(worker.full_name)
            = public.v1_worker_import_normalized(v_name)
          and public.v1_worker_import_normalized(worker.employer_company)
            = public.v1_worker_import_normalized(v_company);
        if v_match_count > 1 then
          v_errors := array_append(v_errors, 'ambiguous_match');
          v_worker_id := null;
        end if;
      end if;
    end if;

    if v_worker_id is not null and cardinality(v_errors) = 0 then
      select record.* into v_record
      from public.v1_worker_employment_records record
      where record.worker_id = v_worker_id;
      v_has_record := found;
      if v_has_record and v_passport is not null
        and v_record.passport_no is not null
        and upper(btrim(v_record.passport_no)) <> v_passport then
        v_errors := array_append(v_errors, 'passport_differs');
      end if;
      if cardinality(v_errors) = 0 then
        -- Only cells that hold a value and differ count as changes.
        if v_license is not null
          and v_license is distinct from v_record.trade_license_no then
          v_changed := array_append(v_changed, 'trade_license_no');
        end if;
        if v_passport is not null
          and v_passport is distinct from upper(btrim(v_record.passport_no)) then
          v_changed := array_append(v_changed, 'passport_no');
        end if;
        if v_amounts ->> 'basic_salary' is not null
          and (v_amounts ->> 'basic_salary')::numeric
            is distinct from v_record.basic_salary then
          v_changed := array_append(v_changed, 'basic_salary');
        end if;
        if v_amounts ->> 'housing_allowance' is not null
          and (v_amounts ->> 'housing_allowance')::numeric
            is distinct from v_record.housing_allowance then
          v_changed := array_append(v_changed, 'housing_allowance');
        end if;
        if v_amounts ->> 'other_allowance' is not null
          and (v_amounts ->> 'other_allowance')::numeric
            is distinct from v_record.other_allowance then
          v_changed := array_append(v_changed, 'other_allowance');
        end if;
      end if;
    end if;

    v_action := case
      when cardinality(v_errors) > 0 then 'error'
      when v_worker_id is null then 'create'
      when cardinality(v_changed) = 0 then 'unchanged'
      else 'update'
    end;
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'index', v_index,
      'row_number', v_row -> 'row_number',
      'action', v_action,
      'worker_id', case when v_action = 'error' then null else v_worker_id end,
      'record_version', case
        when v_worker_id is null or v_action = 'error' then null
        when v_has_record then v_record.record_version
        else 0
      end,
      'errors', to_jsonb(v_errors),
      'changed_fields', to_jsonb(v_changed)
    ));
  end loop;
  return v_result;
end;
$$;

create or replace function public.v1_preview_worker_records_import(
  p_rows jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  perform public.v1_worker_records_assert('worker_records.manage');
  v_rows := public.v1_worker_import_classify(p_rows);
  return jsonb_build_object(
    'schema_version', 1,
    'rows', v_rows,
    'create_count', (select count(*) from jsonb_array_elements(v_rows) row
      where row ->> 'action' = 'create'),
    'update_count', (select count(*) from jsonb_array_elements(v_rows) row
      where row ->> 'action' = 'update'),
    'unchanged_count', (select count(*) from jsonb_array_elements(v_rows) row
      where row ->> 'action' = 'unchanged'),
    'error_count', (select count(*) from jsonb_array_elements(v_rows) row
      where row ->> 'action' = 'error')
  );
end;
$$;

create or replace function public.v1_import_worker_records(
  p_payload jsonb,
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
  v_rows jsonb;
  v_expected jsonb;
  v_classified jsonb;
  v_item jsonb;
  v_row jsonb;
  v_expect jsonb;
  v_designation text;
  v_joining_date date;
  v_worker_id uuid;
  v_before jsonb;
  v_version bigint;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_response jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'V1_WORKER_IMPORT_IDEMPOTENCY_REQUIRED'
      using errcode = '22023';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['rows', 'expected', 'new_worker_designation',
      'new_worker_joining_date'],
    'import_worker_records_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_import_worker_records', p_idempotency_key, p_payload
  );
  if v_existing is not null then
    return v_existing;
  end if;

  v_rows := p_payload -> 'rows';
  v_expected := p_payload -> 'expected';
  if jsonb_typeof(v_expected) <> 'array'
    or jsonb_typeof(v_rows) <> 'array'
    or jsonb_array_length(v_expected) <> jsonb_array_length(v_rows) then
    raise exception 'V1_WORKER_IMPORT_ROWS_INVALID' using errcode = '22023';
  end if;

  -- Serialize with saves and other imports so matching cannot race.
  lock table public.v1_workforce_workers in share row exclusive mode;
  lock table public.v1_worker_employment_records in share row exclusive mode;

  v_classified := public.v1_worker_import_classify(v_rows);
  if exists (
    select 1 from jsonb_array_elements(v_classified) row
    where row ->> 'action' = 'error'
  ) then
    raise exception 'V1_WORKER_IMPORT_HAS_ERRORS' using errcode = '22023';
  end if;
  -- The file must still mean what the preview showed.
  if exists (
    select 1
    from jsonb_array_elements(v_classified) with ordinality now(item, position)
    join jsonb_array_elements(v_expected) with ordinality was(item, position)
      using (position)
    where now.item ->> 'action' is distinct from was.item ->> 'action'
      or now.item ->> 'worker_id' is distinct from was.item ->> 'worker_id'
      or now.item ->> 'record_version'
        is distinct from was.item ->> 'record_version'
  ) then
    perform public.v1_raise_version_conflict('V1_WORKER_IMPORT_PREVIEW_STALE');
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_classified) row
    where row ->> 'action' = 'create'
  ) then
    v_designation := btrim(coalesce(
      p_payload ->> 'new_worker_designation', ''));
    begin
      v_joining_date := nullif(btrim(coalesce(
        p_payload ->> 'new_worker_joining_date', '')), '')::date;
    exception when invalid_text_representation or datetime_field_overflow
      or invalid_datetime_format then
      raise exception 'V1_WORKER_IMPORT_NEW_WORKER_DEFAULTS_INVALID'
        using errcode = '22023';
    end;
    if v_designation = '' or char_length(v_designation) > 120
      or v_joining_date is null then
      raise exception 'V1_WORKER_IMPORT_NEW_WORKER_DEFAULTS_INVALID'
        using errcode = '22023';
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(v_classified) loop
    v_row := v_rows -> ((v_item ->> 'index')::integer - 1);
    if v_item ->> 'action' = 'unchanged' then
      v_unchanged := v_unchanged + 1;
      continue;
    end if;

    if v_item ->> 'action' = 'create' then
      insert into public.v1_workforce_workers (
        worker_number, full_name, designation, employer_company, worker_type,
        joining_date, created_by_auth_user_id, updated_by_auth_user_id
      ) values (
        'WR-' || lpad(
          nextval('public.v1_worker_record_number_seq')::text, 6, '0'),
        btrim(v_row ->> 'full_name'), v_designation,
        btrim(v_row ->> 'employer_company'), 'yorks_employee',
        v_joining_date, v_actor, v_actor
      ) returning id into v_worker_id;
      v_before := null;
      insert into public.v1_worker_employment_records (
        worker_id, trade_license_no, passport_no, basic_salary,
        housing_allowance, other_allowance, created_by_auth_user_id,
        updated_by_auth_user_id, updated_by_role
      ) values (
        v_worker_id,
        nullif(btrim(coalesce(v_row ->> 'trade_license_no', '')), ''),
        nullif(upper(btrim(coalesce(v_row ->> 'passport_no', ''))), ''),
        nullif(btrim(coalesce(v_row ->> 'basic_salary', '')), '')::numeric,
        nullif(btrim(coalesce(v_row ->> 'housing_allowance', '')), '')::numeric,
        nullif(btrim(coalesce(v_row ->> 'other_allowance', '')), '')::numeric,
        v_actor, v_actor, v_role
      ) returning record_version into v_version;
      v_created := v_created + 1;
    else
      v_worker_id := (v_item ->> 'worker_id')::uuid;
      v_before := public.v1_worker_employment_record_snapshot(v_worker_id);
      if (v_item ->> 'record_version')::bigint = 0 then
        insert into public.v1_worker_employment_records (
          worker_id, trade_license_no, passport_no, basic_salary,
          housing_allowance, other_allowance, created_by_auth_user_id,
          updated_by_auth_user_id, updated_by_role
        ) values (
          v_worker_id,
          nullif(btrim(coalesce(v_row ->> 'trade_license_no', '')), ''),
          nullif(upper(btrim(coalesce(v_row ->> 'passport_no', ''))), ''),
          nullif(btrim(coalesce(v_row ->> 'basic_salary', '')), '')::numeric,
          nullif(btrim(coalesce(v_row ->> 'housing_allowance', '')), '')::numeric,
          nullif(btrim(coalesce(v_row ->> 'other_allowance', '')), '')::numeric,
          v_actor, v_actor, v_role
        ) returning record_version into v_version;
      else
        -- A blank cell keeps the stored value.
        update public.v1_worker_employment_records record set
          trade_license_no = coalesce(nullif(btrim(coalesce(
            v_row ->> 'trade_license_no', '')), ''), record.trade_license_no),
          passport_no = coalesce(nullif(upper(btrim(coalesce(
            v_row ->> 'passport_no', ''))), ''), record.passport_no),
          basic_salary = coalesce(nullif(btrim(coalesce(
            v_row ->> 'basic_salary', '')), '')::numeric, record.basic_salary),
          housing_allowance = coalesce(nullif(btrim(coalesce(
            v_row ->> 'housing_allowance', '')), '')::numeric,
            record.housing_allowance),
          other_allowance = coalesce(nullif(btrim(coalesce(
            v_row ->> 'other_allowance', '')), '')::numeric,
            record.other_allowance),
          record_version = record.record_version + 1,
          updated_by_auth_user_id = v_actor,
          updated_by_role = v_role,
          updated_at = clock_timestamp()
        where record.worker_id = v_worker_id
        returning record.record_version into v_version;
      end if;
      v_updated := v_updated + 1;
    end if;

    insert into public.v1_worker_employment_record_revisions (
      worker_id, record_version, change_kind, before_data, after_data,
      actor_auth_user_id, actor_role, idempotency_key
    ) values (
      v_worker_id, v_version, 'imported', v_before,
      public.v1_worker_employment_record_snapshot(v_worker_id),
      v_actor, v_role, p_idempotency_key
    );
  end loop;

  v_response := jsonb_build_object(
    'schema_version', 1,
    'created_count', v_created,
    'updated_count', v_updated,
    'unchanged_count', v_unchanged
  );
  -- One audit event per import batch, identified by its idempotency key.
  -- Counts only: no name, passport or amount.
  perform public.v1_write_audit_event(
    'worker_records_imported', 'worker_records_import', p_idempotency_key,
    null, null, v_response, null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_import_worker_records', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

revoke all on function public.v1_worker_import_normalized(text)
  from public, anon, authenticated;
revoke all on function public.v1_worker_import_classify(jsonb)
  from public, anon, authenticated;
revoke all on function public.v1_preview_worker_records_import(jsonb)
  from public, anon;
revoke all on function public.v1_import_worker_records(jsonb, uuid)
  from public, anon;
grant execute on function public.v1_preview_worker_records_import(jsonb)
  to authenticated;
grant execute on function public.v1_import_worker_records(jsonb, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;

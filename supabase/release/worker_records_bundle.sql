-- =============================================================================
-- Worker Records — apply script for the Supabase SQL editor
-- =============================================================================
-- Concatenation, in order, of:
--   supabase/migrations/20261110120000_worker_records_foundation.sql
--   supabase/migrations/20261110130000_worker_records_save_and_photo.sql
-- Additive and repeatable. No existing data is changed.
--
-- BEFORE YOU RUN THIS:
--   1. Run it on STAGING first and confirm it succeeds.
--   2. Then run the identical script on PRODUCTION.
--   3. Do NOT run `supabase db push` or `supabase migration repair`.
-- ROLLBACK: see the header of each migration below.
-- =============================================================================

-- Worker Records foundation (owner decision, 10 November 2026;
-- PRODUCT_DECISIONS.md section 33).
--
-- Adds the protected employment record kept beside each Workforce worker:
-- trade licence number, passport number, salary breakdown and a photo. It is
-- stored reference data only. No payroll calculation is introduced and no
-- Workforce attendance, timesheet or report projection gains a pay field.
--
-- Access is two new enforced capabilities in their own `worker_records`
-- module. They deliberately do not use the `workforce.` prefix: the Workforce
-- contract fixes that family at twelve keys. Neither depends on
-- `workforce.view`, so a holder gains no attendance or timesheet access, and
-- no `users.*` capability is touched.
--
-- Data preservation: additive. No existing table, row, policy or grant is
-- changed. One rule in three existing permission functions is widened by
-- exactly the two worker_records keys for Accountant (see below); nothing
-- else in them changes. Rollback: set both catalogue rows to
-- is_assignable = false and deny the client route; to restore the original
-- Accountant rule, run the same replacement in reverse. Retain every record,
-- revision and stored photo.

begin;

-- ---------------------------------------------------------------------------
-- Capabilities
-- ---------------------------------------------------------------------------

insert into public.v1_capability_catalog (
  capability_key, module_key, action_key, label, description, risk_level,
  allowed_scope_kinds, requires_project_access, dependencies, status,
  authorization_mode, is_assignable, display_order
)
select
  'worker_records.view', 'worker_records', 'view',
  'View worker records',
  'Read worker employment records: company, trade licence, passport, salary and photo.',
  'critical', array['organization']::text[], false, '{}'::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'worker_records.view'
);

insert into public.v1_capability_catalog (
  capability_key, module_key, action_key, label, description, risk_level,
  allowed_scope_kinds, requires_project_access, dependencies, status,
  authorization_mode, is_assignable, display_order
)
select
  'worker_records.manage', 'worker_records', 'manage',
  'Manage worker records',
  'Create and update worker employment records, photos and imports.',
  'critical', array['organization']::text[], false,
  array['worker_records.view']::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'worker_records.manage'
);

-- Admin holds and may delegate both. Accountant holds both. Everyone else,
-- including PR staff, receives them per person through User Access. Existing
-- rows are left alone so a re-run never resets an edited role template.
insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select role_name, capability_key,
  role_name in ('admin', 'accountant'), role_name = 'admin'
from unnest(array[
  'project_engineer', 'site_engineer',
  'senior_mechanical_engineer', 'project_manager',
  'workshop_in_charge', 'document_controller',
  'procurement', 'accountant', 'admin'
]::text[]) role_name
cross join unnest(array[
  'worker_records.view', 'worker_records.manage'
]::text[]) capability_key
on conflict (role_name, capability_key) do nothing;

-- ---------------------------------------------------------------------------
-- Accountant boundary: one narrow, explicit exception
-- ---------------------------------------------------------------------------
--
-- The R39 Accounts contract makes Accountant an Accounts-only role: the
-- resolver and the assignment guard refuse every non-Accounts capability for
-- it. The owner's 10 November 2026 decision gives Accounting the worker
-- records, so exactly the two `worker_records.*` keys are added to what an
-- Accountant may hold. Every other non-Accounts capability (projects, BOQ,
-- material requests, dispatch, receipts, inventory, returns, team management,
-- users, permissions) stays refused. The frozen R39 Accounts key list in
-- `v1_accounts_is_capability_key` is unchanged.

create or replace function public.v1_accountant_may_hold_capability(
  p_capability_key text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select public.v1_accounts_is_capability_key(p_capability_key)
    or p_capability_key in ('worker_records.view', 'worker_records.manage');
$$;

revoke all on function public.v1_accountant_may_hold_capability(text)
  from public, anon, authenticated;

-- Replace only the Accountant test inside the three live definitions, and
-- refuse to proceed unless each contains exactly the expected text once. This
-- keeps every other line of those security functions byte-for-byte as
-- deployed, including changes made by later migrations.
do $accountant_boundary$
declare
  v_target record;
  v_definition text;
  v_old text;
  v_new text;
begin
  for v_target in
    select *
    from (values
      ('public.v1_permission_candidate_raw(uuid,text,uuid)',
       'not public.v1_accounts_is_capability_key(p_capability_key)',
       'not public.v1_accountant_may_hold_capability(p_capability_key)'),
      ('public.v1_permission_legacy_raw(uuid,text,uuid)',
       'not public.v1_accounts_is_capability_key(p_capability_key)',
       'not public.v1_accountant_may_hold_capability(p_capability_key)'),
      ('public.v1_permission_guard_assignment()',
       'not public.v1_accounts_is_capability_key(new.capability_key)',
       'not public.v1_accountant_may_hold_capability(new.capability_key)')
    ) target(signature, old_text, new_text)
  loop
    v_definition := pg_catalog.pg_get_functiondef(
      v_target.signature::regprocedure
    );
    v_old := v_target.old_text;
    v_new := v_target.new_text;
    -- Already applied on a previous run: nothing to do.
    if position(v_new in v_definition) > 0
      and position(v_old in v_definition) = 0 then
      continue;
    end if;
    if (char_length(v_definition)
        - char_length(replace(v_definition, v_old, '')))
      / char_length(v_old) <> 1 then
      raise exception 'V1_WORKER_RECORDS_ACCOUNTANT_BOUNDARY_DRIFT: %',
        v_target.signature using errcode = '55000';
    end if;
    execute replace(v_definition, v_old, v_new);
  end loop;
end;
$accountant_boundary$;

-- ---------------------------------------------------------------------------
-- Protected relations
-- ---------------------------------------------------------------------------

create table if not exists public.v1_worker_employment_records (
  worker_id uuid primary key
    references public.v1_workforce_workers (id) on delete restrict,
  trade_license_no text check (
    trade_license_no is null
    or (btrim(trade_license_no) <> '' and char_length(trade_license_no) <= 60)
  ),
  passport_no text check (
    passport_no is null
    or (btrim(passport_no) <> '' and char_length(passport_no) <= 40)
  ),
  -- NULL means "not entered", which is different from an entered zero.
  basic_salary numeric(12,2) check (basic_salary is null or basic_salary >= 0),
  housing_allowance numeric(12,2) check (
    housing_allowance is null or housing_allowance >= 0
  ),
  other_allowance numeric(12,2) check (
    other_allowance is null or other_allowance >= 0
  ),
  total_salary numeric(13,2) generated always as (
    coalesce(basic_salary, 0) + coalesce(housing_allowance, 0)
      + coalesce(other_allowance, 0)
  ) stored,
  currency_code text not null default 'AED' check (currency_code = 'AED'),
  photo_object_path text check (
    photo_object_path is null
    or photo_object_path ~ '^workers/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
  ),
  record_version bigint not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  updated_by_role text not null check (btrim(updated_by_role) <> ''),
  updated_at timestamptz not null default clock_timestamp()
);

-- One passport belongs to one worker.
create unique index if not exists v1_worker_employment_records_passport_uidx
  on public.v1_worker_employment_records (upper(btrim(passport_no)))
  where passport_no is not null;

create table if not exists public.v1_worker_employment_record_revisions (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  record_version bigint not null check (record_version > 0),
  change_kind text not null check (change_kind in (
    'created', 'updated', 'photo_set', 'imported'
  )),
  before_data jsonb,
  after_data jsonb not null,
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_role text not null check (btrim(actor_role) <> ''),
  idempotency_key uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (worker_id, record_version)
);

create or replace function public.v1_worker_records_block_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'V1_WORKER_RECORD_HISTORY_IMMUTABLE' using errcode = '55000';
end;
$$;

drop trigger if exists v1_worker_employment_records_no_delete
  on public.v1_worker_employment_records;
create trigger v1_worker_employment_records_no_delete
before delete on public.v1_worker_employment_records
for each row execute function public.v1_worker_records_block_change();

drop trigger if exists v1_worker_employment_record_revisions_immutable
  on public.v1_worker_employment_record_revisions;
create trigger v1_worker_employment_record_revisions_immutable
before update or delete on public.v1_worker_employment_record_revisions
for each row execute function public.v1_worker_records_block_change();

alter table public.v1_worker_employment_records enable row level security;
alter table public.v1_worker_employment_record_revisions
  enable row level security;

-- No policies and no client grants: every read and write goes through the
-- trusted functions below, so an unauthorized query, cache or export cannot
-- contain a salary or passport value.
revoke all on table public.v1_worker_employment_records
  from public, anon, authenticated;
revoke all on table public.v1_worker_employment_record_revisions
  from public, anon, authenticated;
grant all on table public.v1_worker_employment_records to service_role;
grant all on table public.v1_worker_employment_record_revisions
  to service_role;

-- ---------------------------------------------------------------------------
-- Authorization and projection
-- ---------------------------------------------------------------------------

create or replace function public.v1_worker_records_assert(
  p_capability_key text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if p_capability_key not in (
    'worker_records.view', 'worker_records.manage'
  ) then
    raise exception 'V1_WORKER_RECORDS_CAPABILITY_INVALID'
      using errcode = '22023';
  end if;
  if v_actor is null then
    raise exception 'V1_WORKER_RECORDS_DENIED' using errcode = '42501';
  end if;
  perform public.v1_sync_profile_from_auth(v_actor);
  if not public.v1_current_actor_is_active()
    or public.v1_permission_exact_role(v_actor) = ''
    or not public.v1_current_user_has_capability(p_capability_key, null)
  then
    raise exception 'V1_WORKER_RECORDS_DENIED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

-- Internal projection. Money is returned as text so the client never parses
-- it through a binary float.
create or replace function public.v1_worker_record_json(p_worker_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'worker_id', worker.id,
    'worker_number', worker.worker_number,
    'full_name', worker.full_name,
    'designation', worker.designation,
    'employer_company', worker.employer_company,
    'worker_type', worker.worker_type,
    'current_status', worker.current_status,
    'joining_date', worker.joining_date,
    'worker_version', worker.record_version,
    'has_record', record.worker_id is not null,
    'trade_license_no', record.trade_license_no,
    'passport_no', record.passport_no,
    'basic_salary', record.basic_salary::text,
    'housing_allowance', record.housing_allowance::text,
    'other_allowance', record.other_allowance::text,
    'total_salary', record.total_salary::text,
    'currency_code', coalesce(record.currency_code, 'AED'),
    'photo_object_path', record.photo_object_path,
    'record_version', coalesce(record.record_version, 0),
    'updated_at', record.updated_at,
    'updated_by_name', updater.display_name,
    'updated_by_role', record.updated_by_role
  )
  from public.v1_workforce_workers worker
  left join public.v1_worker_employment_records record
    on record.worker_id = worker.id
  left join public.v1_profiles updater
    on updater.auth_user_id = record.updated_by_auth_user_id
  where worker.id = p_worker_id;
$$;

create or replace function public.v1_list_worker_records(
  p_search text default null,
  p_company text default null,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_company text := lower(btrim(coalesce(p_company, '')));
  v_status text := btrim(coalesce(p_status, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  perform public.v1_worker_records_assert('worker_records.view');
  if v_status <> '' and v_status not in (
    'active', 'inactive', 'left_company', 'suspended'
  ) then
    raise exception 'V1_WORKER_RECORDS_FILTER_INVALID' using errcode = '22023';
  end if;
  if char_length(v_search) > 120 or char_length(v_company) > 180 then
    raise exception 'V1_WORKER_RECORDS_FILTER_INVALID' using errcode = '22023';
  end if;

  with matched as materialized (
    select worker.id, worker.full_name, record.basic_salary,
      record.housing_allowance, record.other_allowance, record.total_salary,
      record.worker_id is not null as has_record
    from public.v1_workforce_workers worker
    left join public.v1_worker_employment_records record
      on record.worker_id = worker.id
    where (v_status = '' or worker.current_status = v_status)
      and (v_company = ''
        or lower(btrim(worker.employer_company)) = v_company)
      and (v_search = ''
        or position(v_search in lower(worker.full_name)) > 0
        or position(v_search in lower(worker.worker_number)) > 0
        or position(v_search in lower(worker.employer_company)) > 0
        or position(v_search in lower(coalesce(record.passport_no, ''))) > 0
        or position(
          v_search in lower(coalesce(record.trade_license_no, ''))
        ) > 0)
  ), page as materialized (
    select matched.id, matched.full_name
    from matched
    order by lower(matched.full_name), matched.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'schema_version', 1,
    'total_count', (select count(*) from matched),
    'with_record_count', (select count(*) from matched where has_record),
    'limit', v_limit,
    'offset', v_offset,
    'totals', (
      select jsonb_build_object(
        'basic_salary', coalesce(sum(basic_salary), 0)::text,
        'housing_allowance', coalesce(sum(housing_allowance), 0)::text,
        'other_allowance', coalesce(sum(other_allowance), 0)::text,
        'total_salary', coalesce(sum(total_salary), 0)::text
      )
      from matched
    ),
    'companies', coalesce((
      select jsonb_agg(company.name order by lower(company.name))
      from (
        select distinct btrim(worker.employer_company) as name
        from public.v1_workforce_workers worker
      ) company
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        public.v1_worker_record_json(page.id)
        order by lower(page.full_name), page.id
      )
      from page
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.v1_get_worker_record(p_worker_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform public.v1_worker_records_assert('worker_records.view');
  v_result := public.v1_worker_record_json(p_worker_id);
  if v_result is null then
    raise exception 'V1_WORKER_RECORD_NOT_FOUND' using errcode = 'P0002';
  end if;
  return v_result || jsonb_build_object('schema_version', 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- Photos: private bucket, authorization by capability, never by path alone
-- ---------------------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'yorks-worker-photos', 'yorks-worker-photos', false, 2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create or replace function public.v1_worker_photo_path_worker_id(
  p_bucket_id text,
  p_object_path text
)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_bucket_id = 'yorks-worker-photos'
      and p_object_path ~ '^workers/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    then split_part(p_object_path, '/', 2)::uuid
    else null
  end;
$$;

create or replace function public.v1_worker_photo_readable(
  p_bucket_id text,
  p_object_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.v1_worker_photo_path_worker_id(p_bucket_id, p_object_path)
      is not null
    and public.v1_current_user_has_capability('worker_records.view', null);
$$;

create or replace function public.v1_worker_photo_writable(
  p_bucket_id text,
  p_object_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.v1_workforce_workers worker
      where worker.id = public.v1_worker_photo_path_worker_id(
        p_bucket_id, p_object_path
      )
    )
    and public.v1_current_user_has_capability('worker_records.manage', null);
$$;

drop policy if exists v1_worker_photo_select on storage.objects;
create policy v1_worker_photo_select
on storage.objects for select to authenticated
using (public.v1_worker_photo_readable(bucket_id, name));

drop policy if exists v1_worker_photo_insert on storage.objects;
create policy v1_worker_photo_insert
on storage.objects for insert to authenticated
with check (public.v1_worker_photo_writable(bucket_id, name));

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on function public.v1_worker_records_block_change()
  from public, anon, authenticated;
revoke all on function public.v1_worker_records_assert(text)
  from public, anon, authenticated;
revoke all on function public.v1_worker_record_json(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_worker_photo_path_worker_id(text, text)
  from public, anon;
revoke all on function public.v1_worker_photo_readable(text, text)
  from public, anon;
revoke all on function public.v1_worker_photo_writable(text, text)
  from public, anon;
revoke all on function public.v1_list_worker_records(
  text, text, text, integer, integer
) from public, anon;
revoke all on function public.v1_get_worker_record(uuid) from public, anon;

grant execute on function public.v1_worker_photo_path_worker_id(text, text)
  to authenticated;
grant execute on function public.v1_worker_photo_readable(text, text)
  to authenticated;
grant execute on function public.v1_worker_photo_writable(text, text)
  to authenticated;
grant execute on function public.v1_list_worker_records(
  text, text, text, integer, integer
) to authenticated;
grant execute on function public.v1_get_worker_record(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

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

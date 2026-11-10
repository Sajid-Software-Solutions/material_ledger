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
-- Data preservation: additive only. No existing table, row, function, policy
-- or grant is changed. Rollback: set both catalogue rows to
-- is_assignable = false and deny the client route; retain every record,
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

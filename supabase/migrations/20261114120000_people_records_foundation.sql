-- People records: staff and labour, their identity documents and site
-- passes (owner decision, 13 November 2026; PRODUCT_DECISIONS section 42).
--
-- A person is a Workforce worker (`v1_workforce_workers`), so whoever is kept
-- here is the same person crews, attendance and timesheets use. Beside each
-- worker this adds:
--
--   * a profile: Staff or Labour, Arabic name, date of birth, unified number;
--   * documents: visa, passport, labour card, ILOE, Emirates ID, CICPA and
--     CMW site passes, with number, dates and the sites a pass covers. A
--     renewal keeps the previous document as history;
--   * an append-only history of every change.
--
-- Access is two new enforced capabilities in their own module,
-- `people_records.view` and `people_records.manage`, held by Admin, PR and
-- Accountant. They do not reuse the legacy shadow `people.*` keys, which
-- Procurement holds. Identity numbers and dates of birth are returned only
-- to holders; nothing here is readable through table grants.
--
-- Data preservation: additive. Two capabilities, three tables, functions.
-- The Accountant and PR capability boundaries each gain exactly these two
-- keys; nothing else in them changes. Rollback: set both catalogue rows to
-- is_assignable = false and turn the client flag off; keep every row.

begin;

-- ---------------------------------------------------------------------------
-- 1. Capabilities
-- ---------------------------------------------------------------------------

insert into public.v1_capability_catalog (
  capability_key, module_key, action_key, label, description, risk_level,
  allowed_scope_kinds, requires_project_access, dependencies, status,
  authorization_mode, is_assignable, display_order
)
select
  'people_records.view', 'people_records', 'view',
  'View people records',
  'Read staff and labour records: identity documents, numbers, dates of birth and site passes.',
  'critical', array['organization']::text[], false, '{}'::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'people_records.view'
);

insert into public.v1_capability_catalog (
  capability_key, module_key, action_key, label, description, risk_level,
  allowed_scope_kinds, requires_project_access, dependencies, status,
  authorization_mode, is_assignable, display_order
)
select
  'people_records.manage', 'people_records', 'manage',
  'Manage people records',
  'Add and edit staff and labour, record and renew documents, import and export the tracker.',
  'critical', array['organization']::text[], false,
  array['people_records.view']::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'people_records.manage'
);

-- Admin, PR and Accountant hold both; Admin and PR may delegate. Existing
-- rows are left alone so a re-run never resets an edited template.
insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select role_name, capability_key,
  role_name in ('admin', 'pr', 'accountant'),
  role_name in ('admin', 'pr')
from unnest(array[
  'project_engineer', 'site_engineer',
  'senior_mechanical_engineer', 'project_manager',
  'workshop_in_charge', 'document_controller',
  'procurement', 'accountant', 'pr', 'admin'
]::text[]) role_name
cross join unnest(array[
  'people_records.view', 'people_records.manage'
]::text[]) capability_key
on conflict (role_name, capability_key) do nothing;

-- Accountant: one more narrow exception beside worker records.
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
    or p_capability_key in (
      'worker_records.view', 'worker_records.manage',
      'people_records.view', 'people_records.manage'
    );
$$;

revoke all on function public.v1_accountant_may_hold_capability(text)
  from public, anon, authenticated;

-- PR: the fixed list gains exactly the two keys. The replacement refuses to
-- run unless the live definition still lists worker records once, so a
-- later change to the list is never silently overwritten.
do $pr_boundary$
declare
  v_definition text := pg_catalog.pg_get_functiondef(
    'public.v1_pr_may_hold_capability(text)'::regprocedure
  );
  v_old text := '''worker_records.view'', ''worker_records.manage'',';
  v_new text := '''worker_records.view'', ''worker_records.manage'',
    ''people_records.view'', ''people_records.manage'',';
begin
  if position('people_records.view' in v_definition) > 0 then
    return;
  end if;
  if (char_length(v_definition)
      - char_length(replace(v_definition, v_old, '')))
    / char_length(v_old) <> 1 then
    raise exception 'V1_PEOPLE_RECORDS_PR_BOUNDARY_DRIFT' using errcode = '55000';
  end if;
  execute replace(v_definition, v_old, v_new);
end;
$pr_boundary$;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.v1_people_profiles (
  worker_id uuid primary key
    references public.v1_workforce_workers (id) on delete restrict,
  category text not null check (category in ('staff', 'labour')),
  arabic_name text check (
    arabic_name is null
    or (btrim(arabic_name) <> '' and char_length(arabic_name) <= 180)
  ),
  date_of_birth date check (
    date_of_birth is null
    or date_of_birth between date '1900-01-01' and date '2100-01-01'
  ),
  unified_number text check (
    unified_number is null
    or (btrim(unified_number) <> '' and char_length(unified_number) <= 40)
  ),
  -- Where the person first came from, e.g. the gate pass list.
  source_note text check (
    source_note is null or char_length(source_note) <= 200
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

create table if not exists public.v1_people_documents (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  kind text not null check (kind in (
    'visa', 'passport', 'labour_card', 'iloe', 'emirates_id',
    'cicpa_pass', 'cmw_pass', 'other'
  )),
  label text check (
    label is null or (btrim(label) <> '' and char_length(label) <= 120)
  ),
  document_number text check (
    document_number is null
    or (btrim(document_number) <> '' and char_length(document_number) <= 60)
  ),
  issue_date date,
  expiry_date date,
  sites text check (sites is null or char_length(sites) <= 500),
  notes text check (notes is null or char_length(notes) <= 1000),
  is_current boolean not null default true,
  replaced_by_document_id uuid
    references public.v1_people_documents (id) on delete restrict,
  ended_at timestamptz,
  ended_reason text check (
    ended_reason is null or char_length(ended_reason) <= 500
  ),
  record_version bigint not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  updated_by_role text not null check (btrim(updated_by_role) <> ''),
  updated_at timestamptz not null default clock_timestamp(),
  check (kind <> 'other' or label is not null),
  -- Something is recorded: a number, an expiry, or for a site pass the
  -- sites it covers (the tracker often lists a pass before its number).
  check (
    document_number is not null or expiry_date is not null
    or (kind in ('cicpa_pass', 'cmw_pass') and sites is not null)
  ),
  check (
    expiry_date is null or issue_date is null or expiry_date >= issue_date
  ),
  check (is_current or ended_at is not null)
);

-- One current visa, passport, labour card, ILOE and Emirates ID each.
create unique index if not exists v1_people_documents_single_current_uidx
  on public.v1_people_documents (worker_id, kind)
  where is_current and kind in (
    'visa', 'passport', 'labour_card', 'iloe', 'emirates_id'
  );
create index if not exists v1_people_documents_worker_idx
  on public.v1_people_documents (worker_id, kind) where is_current;
create index if not exists v1_people_documents_expiry_idx
  on public.v1_people_documents (expiry_date) where is_current;

create table if not exists public.v1_people_revisions (
  id bigint generated always as identity primary key,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  entity text not null check (entity in ('person', 'document')),
  entity_id uuid not null,
  action text not null check (action in (
    'created', 'updated', 'renewed', 'ended', 'imported'
  )),
  before_data jsonb,
  after_data jsonb not null,
  reason text check (reason is null or char_length(reason) <= 500),
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_role text not null check (btrim(actor_role) <> ''),
  idempotency_key uuid,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists v1_people_revisions_worker_idx
  on public.v1_people_revisions (worker_id, id desc);

create or replace function public.v1_people_block_history_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'V1_PEOPLE_HISTORY_IMMUTABLE' using errcode = '55000';
end;
$$;

drop trigger if exists v1_people_revisions_immutable
  on public.v1_people_revisions;
create trigger v1_people_revisions_immutable
  before update or delete on public.v1_people_revisions
  for each row execute function public.v1_people_block_history_change();

-- Documents and profiles are never deleted: a document ends, a person
-- leaves through Workforce.
drop trigger if exists v1_people_documents_no_delete
  on public.v1_people_documents;
create trigger v1_people_documents_no_delete
  before delete on public.v1_people_documents
  for each row execute function public.v1_people_block_history_change();
drop trigger if exists v1_people_profiles_no_delete
  on public.v1_people_profiles;
create trigger v1_people_profiles_no_delete
  before delete on public.v1_people_profiles
  for each row execute function public.v1_people_block_history_change();

alter table public.v1_people_profiles enable row level security;
alter table public.v1_people_documents enable row level security;
alter table public.v1_people_revisions enable row level security;
revoke all on table public.v1_people_profiles,
  public.v1_people_documents, public.v1_people_revisions
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

create or replace function public.v1_people_assert(p_capability_key text)
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
    'people_records.view', 'people_records.manage'
  ) then
    raise exception 'V1_PEOPLE_CAPABILITY_INVALID' using errcode = '22023';
  end if;
  if v_actor is null then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  perform public.v1_sync_profile_from_auth(v_actor);
  if not public.v1_current_actor_is_active()
    or public.v1_permission_exact_role(v_actor) = ''
    or not public.v1_current_user_has_capability(p_capability_key, null)
  then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

-- Expired, expiring within 60 days, fine, or no expiry recorded.
create or replace function public.v1_people_status(
  p_expiry date,
  p_today date
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_expiry is null then 'no_expiry'
    when p_expiry < p_today then 'expired'
    when p_expiry <= p_today + 60 then 'expiring'
    else 'ok'
  end;
$$;

create or replace function public.v1_people_kind_order(p_kind text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select array_position(array[
    'visa', 'passport', 'labour_card', 'iloe', 'emirates_id',
    'cicpa_pass', 'cmw_pass', 'other'
  ]::text[], p_kind);
$$;

-- Comparable form of a name or company: case, spacing and punctuation
-- ignored.
create or replace function public.v1_people_key(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(regexp_replace(
    regexp_replace(upper(coalesce(p_value, '')), '[^[:alnum:] ]', ' ', 'g'),
    '\s+', ' ', 'g'
  ));
$$;

create or replace function public.v1_people_document_json(
  p_document public.v1_people_documents,
  p_today date
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_document.id,
    'kind', p_document.kind,
    'label', p_document.label,
    'number', p_document.document_number,
    'issue_date', p_document.issue_date,
    'expiry_date', p_document.expiry_date,
    'days_left', case when p_document.expiry_date is null then null
      else p_document.expiry_date - p_today end,
    'status', public.v1_people_status(p_document.expiry_date, p_today),
    'sites', p_document.sites,
    'notes', p_document.notes,
    'is_current', p_document.is_current,
    'ended_at', p_document.ended_at,
    'ended_reason', p_document.ended_reason,
    'record_version', p_document.record_version,
    'updated_at', p_document.updated_at,
    'updated_by', public.v1_wf_display_name(p_document.updated_by_auth_user_id)
  );
$$;

-- One person. The register uses the short form; the record adds history.
create or replace function public.v1_people_person_json(
  p_worker_id uuid,
  p_detail boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with today as (select public.v1_wf_today() as day)
  select jsonb_build_object(
    'id', worker.id,
    'number', worker.worker_number,
    'name', worker.full_name,
    'company', worker.employer_company,
    'profession', worker.designation,
    'status', worker.current_status,
    'worker_type', worker.worker_type,
    'joining_date', worker.joining_date,
    'mobile', worker.mobile_number,
    'category', coalesce(profile.category, 'labour'),
    'has_profile', profile.worker_id is not null,
    'arabic_name', profile.arabic_name,
    'date_of_birth', profile.date_of_birth,
    'unified_number', profile.unified_number,
    'source_note', profile.source_note,
    'record_version', coalesce(profile.record_version, 0),
    'updated_at', greatest(worker.updated_at, profile.updated_at),
    'documents', coalesce((
      select jsonb_agg(
        public.v1_people_document_json(document, today.day)
        order by public.v1_people_kind_order(document.kind),
          document.expiry_date nulls last, document.created_at
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
    ), '[]'::jsonb),
    'attention', coalesce((
      select case
        when bool_or(document.expiry_date < today.day) then 'expired'
        when bool_or(document.expiry_date <= today.day + 60) then 'expiring'
        else 'ok'
      end
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
        and document.expiry_date is not null
    ), 'ok'),
    'next_expiry', (
      select jsonb_build_object(
        'kind', document.kind, 'label', document.label,
        'expiry_date', document.expiry_date,
        'days_left', document.expiry_date - today.day
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
        and document.expiry_date is not null
      order by document.expiry_date
      limit 1
    ),
    'crew', (
      select jsonb_build_object('id', team.id, 'name', team.team_name)
      from public.v1_workforce_crew_members member
      join public.v1_workforce_teams team on team.id = member.team_id
      where member.worker_id = worker.id and member.removed_at is null
      limit 1
    ),
    'previous_documents', case when p_detail then coalesce((
      select jsonb_agg(
        public.v1_people_document_json(document, today.day)
        order by document.updated_at desc
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and not document.is_current
    ), '[]'::jsonb) end,
    'history', case when p_detail then coalesce((
      select jsonb_agg(item order by (item ->> 'id')::bigint desc)
      from (
        select jsonb_build_object(
          'id', revision.id,
          'entity', revision.entity,
          'action', revision.action,
          'kind', coalesce(
            revision.after_data ->> 'kind', revision.before_data ->> 'kind'
          ),
          'changed', (
            select coalesce(jsonb_agg(key order by key), '[]'::jsonb)
            from jsonb_object_keys(revision.after_data) key
            where key not in ('record_version', 'updated_at')
              and revision.after_data -> key
                is distinct from coalesce(revision.before_data, '{}'::jsonb)
                  -> key
          ),
          'reason', revision.reason,
          'actor_name', public.v1_wf_display_name(revision.actor_auth_user_id),
          'actor_role', revision.actor_role,
          'at', revision.created_at
        ) as item
        from public.v1_people_revisions revision
        where revision.worker_id = worker.id
        order by revision.id desc
        limit 100
      ) recent
    ), '[]'::jsonb) end
  )
  from public.v1_workforce_workers worker
  cross join today
  left join public.v1_people_profiles profile
    on profile.worker_id = worker.id
  where worker.id = p_worker_id;
$$;

create or replace function public.v1_people_revision(
  p_worker_id uuid,
  p_entity text,
  p_entity_id uuid,
  p_action text,
  p_before jsonb,
  p_after jsonb,
  p_reason text,
  p_actor uuid,
  p_role text,
  p_key uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.v1_people_revisions (
    worker_id, entity, entity_id, action, before_data, after_data, reason,
    actor_auth_user_id, actor_role, idempotency_key
  ) values (
    p_worker_id, p_entity, p_entity_id, p_action, p_before, p_after,
    p_reason, p_actor, p_role, p_key
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. Reads
-- ---------------------------------------------------------------------------

create or replace function public.v1_people_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
begin
  perform public.v1_people_assert('people_records.view');
  return jsonb_build_object(
    'schema_version', 'yorks.people.overview.v1',
    'today', v_today,
    'can_manage', public.v1_current_user_has_capability(
      'people_records.manage', null
    ),
    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'staff', count(*) filter (
          where coalesce(profile.category, 'labour') = 'staff'
        ),
        'labour', count(*) filter (
          where coalesce(profile.category, 'labour') = 'labour'
        ),
        'expired', count(*) filter (where exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and document.expiry_date < v_today
        )),
        'expiring', count(*) filter (where exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and document.expiry_date between v_today and v_today + 60
        )),
        'no_visa', count(*) filter (where not exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and document.kind = 'visa'
        ))
      )
      from public.v1_workforce_workers worker
      left join public.v1_people_profiles profile
        on profile.worker_id = worker.id
      where worker.current_status = 'active'
    ),
    'by_kind', coalesce((
      select jsonb_object_agg(kind, counts)
      from (
        select document.kind, jsonb_build_object(
          'expired', count(*) filter (where document.expiry_date < v_today),
          'expiring', count(*) filter (
            where document.expiry_date between v_today and v_today + 60
          ),
          'total', count(*)
        ) as counts
        from public.v1_people_documents document
        join public.v1_workforce_workers worker
          on worker.id = document.worker_id
        where document.is_current and worker.current_status = 'active'
        group by document.kind
      ) kinds
    ), '{}'::jsonb),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object('name', company, 'count', n)
        order by n desc, company)
      from (
        select worker.employer_company as company, count(*) as n
        from public.v1_workforce_workers worker
        where worker.current_status = 'active'
        group by worker.employer_company
      ) companies
    ), '[]'::jsonb),
    -- What needs attention: expired first, then soonest to expire.
    'attention', coalesce((
      select jsonb_agg(item order by expiry, name)
      from (
        select document.expiry_date as expiry, worker.full_name as name,
          jsonb_build_object(
            'document', public.v1_people_document_json(document, v_today),
            'person', jsonb_build_object(
              'id', worker.id, 'number', worker.worker_number,
              'name', worker.full_name, 'company', worker.employer_company,
              'category', coalesce(profile.category, 'labour')
            )
          ) as item
        from public.v1_people_documents document
        join public.v1_workforce_workers worker
          on worker.id = document.worker_id
        left join public.v1_people_profiles profile
          on profile.worker_id = worker.id
        where document.is_current and worker.current_status = 'active'
          and document.expiry_date <= v_today + 60
        order by document.expiry_date, worker.full_name
        limit 200
      ) attention
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.v1_people_list(p_query jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_query jsonb := coalesce(p_query, '{}'::jsonb);
  v_category text := nullif(v_query ->> 'category', '');
  v_company text := nullif(v_query ->> 'company', '');
  v_search text := nullif(btrim(coalesce(v_query ->> 'search', '')), '');
  v_status text := nullif(v_query ->> 'status', '');
  v_include_left boolean := coalesce(
    (v_query ->> 'include_left')::boolean, false
  );
  v_sort text := coalesce(nullif(v_query ->> 'sort', ''), 'name');
  v_limit integer := least(greatest(coalesce(
    (v_query ->> 'limit')::integer, 50), 1), 1000);
  v_offset integer := greatest(coalesce((v_query ->> 'offset')::integer, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform public.v1_people_assert('people_records.view');
  perform public.v1_assert_object_keys(
    v_query,
    array['category', 'company', 'search', 'status', 'include_left', 'sort',
      'limit', 'offset'],
    'people_list_query'
  );
  if (v_category is not null and v_category not in ('staff', 'labour'))
    or (v_status is not null and v_status not in (
      'attention', 'expired', 'expiring', 'no_visa'
    ))
    or v_sort not in ('name', 'expiry', 'company', 'number') then
    raise exception 'V1_PEOPLE_INVALID' using errcode = '22023';
  end if;

  with filtered as (
    select worker.id, worker.full_name, worker.employer_company,
      worker.worker_number,
      (select min(document.expiry_date)
       from public.v1_people_documents document
       where document.worker_id = worker.id and document.is_current
      ) as next_expiry
    from public.v1_workforce_workers worker
    left join public.v1_people_profiles profile
      on profile.worker_id = worker.id
    where (v_include_left or worker.current_status = 'active')
      and (v_category is null
        or coalesce(profile.category, 'labour') = v_category)
      and (v_company is null or worker.employer_company = v_company)
      and (v_search is null
        or worker.full_name ilike '%' || v_search || '%'
        or worker.worker_number ilike '%' || v_search || '%'
        or worker.designation ilike '%' || v_search || '%'
        or worker.employer_company ilike '%' || v_search || '%'
        or profile.arabic_name ilike '%' || v_search || '%'
        or exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and (document.document_number ilike '%' || v_search || '%'
              or document.sites ilike '%' || v_search || '%')
        ))
      and (v_status is null
        or (v_status = 'no_visa' and not exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and document.kind = 'visa'
        ))
        or (v_status <> 'no_visa' and exists (
          select 1 from public.v1_people_documents document
          where document.worker_id = worker.id and document.is_current
            and document.expiry_date is not null
            and case v_status
              when 'expired' then document.expiry_date < v_today
              when 'expiring' then document.expiry_date
                between v_today and v_today + 60
              else document.expiry_date <= v_today + 60
            end
        )))
  )
  select
    (select count(*)::integer from filtered),
    coalesce((
      select jsonb_agg(public.v1_people_person_json(page.id, false)
        order by page.ord)
      from (
        select filtered.id, row_number() over (order by
          case when v_sort = 'expiry' then filtered.next_expiry end
            nulls last,
          case when v_sort = 'company' then
            lower(filtered.employer_company) end,
          case when v_sort = 'number' then filtered.worker_number end,
          lower(filtered.full_name), filtered.id
        ) as ord
        from filtered
        order by ord
        offset v_offset
        limit v_limit
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

  return jsonb_build_object(
    'schema_version', 'yorks.people.list.v1',
    'today', v_today,
    'total', v_total,
    'offset', v_offset,
    'limit', v_limit,
    'rows', v_rows
  );
end;
$$;

create or replace function public.v1_people_get(p_worker_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_person jsonb;
begin
  perform public.v1_people_assert('people_records.view');
  v_person := public.v1_people_person_json(p_worker_id, true);
  if v_person is null then
    raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
  end if;
  return v_person || jsonb_build_object(
    'can_manage', public.v1_current_user_has_capability(
      'people_records.manage', null
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Writes
-- ---------------------------------------------------------------------------

-- Add a person (a new Workforce worker with a profile) or edit one. On an
-- existing worker only name, company, profession and mobile are corrected
-- here; status, dates, trade and crews stay with Workforce.
create or replace function public.v1_people_save_person(
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
  v_actor uuid := public.v1_people_assert('people_records.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_worker_id uuid := nullif(p_payload ->> 'worker_id', '')::uuid;
  v_worker public.v1_workforce_workers%rowtype;
  v_profile public.v1_people_profiles%rowtype;
  v_name text := btrim(coalesce(p_payload ->> 'full_name', ''));
  v_company text := btrim(coalesce(p_payload ->> 'employer_company', ''));
  v_designation text := coalesce(
    nullif(btrim(coalesce(p_payload ->> 'designation', '')), ''),
    'Not recorded'
  );
  v_category text := coalesce(nullif(p_payload ->> 'category', ''), 'labour');
  v_arabic text := nullif(btrim(coalesce(p_payload ->> 'arabic_name', '')), '');
  v_dob date := nullif(p_payload ->> 'date_of_birth', '')::date;
  v_unified text := nullif(
    btrim(coalesce(p_payload ->> 'unified_number', '')), ''
  );
  v_mobile text := nullif(btrim(coalesce(p_payload ->> 'mobile_number', '')), '');
  v_joining date := coalesce(
    nullif(p_payload ->> 'joining_date', '')::date, public.v1_wf_today()
  );
  v_before jsonb;
  v_after jsonb;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_save_person', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_people_person_json(
      (v_existing ->> 'worker_id')::uuid, true
    );
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['worker_id', 'full_name', 'employer_company', 'designation',
      'category', 'arabic_name', 'date_of_birth', 'unified_number',
      'mobile_number', 'joining_date'],
    'people_person_payload'
  );
  if v_name = '' or char_length(v_name) > 180
    or v_company = '' or char_length(v_company) > 180
    or char_length(v_designation) > 120
    or v_category not in ('staff', 'labour')
    or (v_dob is not null and v_dob > public.v1_wf_today()) then
    raise exception 'V1_PEOPLE_INVALID' using errcode = '22023';
  end if;

  if v_worker_id is null then
    if coalesce(p_expected_version, 0) <> 0 then
      perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
    end if;
    insert into public.v1_workforce_workers (
      worker_number, full_name, designation, employer_company, worker_type,
      mobile_number, joining_date, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      'WR-' || lpad(
        nextval('public.v1_worker_record_number_seq')::text, 6, '0'
      ),
      v_name, v_designation, v_company, 'yorks_employee', v_mobile,
      v_joining, v_actor, v_actor
    ) returning * into v_worker;
    v_worker_id := v_worker.id;
  else
    select worker.* into v_worker
    from public.v1_workforce_workers worker
    where worker.id = v_worker_id
    for update;
    if not found then
      raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
    end if;
    select profile.* into v_profile
    from public.v1_people_profiles profile
    where profile.worker_id = v_worker_id
    for update;
    if coalesce(p_expected_version, -1)
      <> coalesce(v_profile.record_version, 0) then
      perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
    end if;
    v_before := public.v1_people_person_json(v_worker_id, false)
      - 'documents' - 'attention' - 'next_expiry' - 'crew'
      - 'previous_documents' - 'history';
    update public.v1_workforce_workers set
      full_name = v_name,
      employer_company = v_company,
      designation = v_designation,
      mobile_number = v_mobile,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_at = clock_timestamp()
    where id = v_worker_id;
  end if;

  insert into public.v1_people_profiles (
    worker_id, category, arabic_name, date_of_birth, unified_number,
    created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
  ) values (
    v_worker_id, v_category, v_arabic, v_dob, v_unified, v_actor, v_actor,
    v_role
  )
  on conflict (worker_id) do update set
    category = excluded.category,
    arabic_name = excluded.arabic_name,
    date_of_birth = excluded.date_of_birth,
    unified_number = excluded.unified_number,
    record_version = public.v1_people_profiles.record_version + 1,
    updated_by_auth_user_id = v_actor,
    updated_by_role = v_role,
    updated_at = clock_timestamp();

  v_after := public.v1_people_person_json(v_worker_id, false)
    - 'documents' - 'attention' - 'next_expiry' - 'crew'
    - 'previous_documents' - 'history';
  perform public.v1_people_revision(
    v_worker_id, 'person', v_worker_id,
    case when v_before is null then 'created' else 'updated' end,
    v_before, v_after, null, v_actor, v_role, p_idempotency_key
  );
  -- The audit trail names what changed, never an identity number.
  perform public.v1_write_audit_event(
    case when v_before is null then 'people_person_created'
      else 'people_person_updated' end,
    'people_person', v_worker_id, null,
    null,
    jsonb_build_object(
      'record_version', v_after -> 'record_version',
      'category', v_category
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_save_person', p_idempotency_key,
    jsonb_build_object('worker_id', v_worker_id)
  );
  return public.v1_people_person_json(v_worker_id, true);
end;
$$;

-- Record, correct or renew a document. Renewing ends the current one and
-- keeps it as history.
create or replace function public.v1_people_save_document(
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
  v_actor uuid := public.v1_people_assert('people_records.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_worker_id uuid := nullif(p_payload ->> 'worker_id', '')::uuid;
  v_document_id uuid := nullif(p_payload ->> 'document_id', '')::uuid;
  v_renew boolean := coalesce((p_payload ->> 'renew')::boolean, false);
  v_kind text := nullif(p_payload ->> 'kind', '');
  v_label text := nullif(btrim(coalesce(p_payload ->> 'label', '')), '');
  v_number text := nullif(btrim(coalesce(p_payload ->> 'number', '')), '');
  v_issue date := nullif(p_payload ->> 'issue_date', '')::date;
  v_expiry date := nullif(p_payload ->> 'expiry_date', '')::date;
  v_sites text := nullif(btrim(coalesce(p_payload ->> 'sites', '')), '');
  v_notes text := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  v_current public.v1_people_documents%rowtype;
  v_saved public.v1_people_documents%rowtype;
  v_today date := public.v1_wf_today();
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_save_document', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_people_person_json(
      (v_existing ->> 'worker_id')::uuid, true
    );
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['worker_id', 'document_id', 'renew', 'kind', 'label', 'number',
      'issue_date', 'expiry_date', 'sites', 'notes'],
    'people_document_payload'
  );
  if v_worker_id is null or not exists (
    select 1 from public.v1_workforce_workers where id = v_worker_id
  ) then
    raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.v1_workforce_workers
  where id = v_worker_id for update;

  if v_document_id is not null then
    select document.* into v_current
    from public.v1_people_documents document
    where document.id = v_document_id and document.worker_id = v_worker_id
    for update;
    if not found or not v_current.is_current
      or coalesce(p_expected_version, -1) <> v_current.record_version then
      perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
    end if;
    v_kind := v_current.kind;
    v_label := coalesce(v_label, v_current.label);
  elsif coalesce(p_expected_version, 0) <> 0 then
    perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
  end if;

  if v_kind is null or v_kind not in (
      'visa', 'passport', 'labour_card', 'iloe', 'emirates_id',
      'cicpa_pass', 'cmw_pass', 'other'
    )
    or (v_kind = 'other' and v_label is null)
    or (v_number is null and v_expiry is null
      and not (v_kind in ('cicpa_pass', 'cmw_pass') and v_sites is not null))
    or char_length(coalesce(v_number, '')) > 60
    or char_length(coalesce(v_label, '')) > 120
    or char_length(coalesce(v_sites, '')) > 500
    or char_length(coalesce(v_notes, '')) > 1000
    or (v_issue is not null and v_expiry is not null and v_expiry < v_issue)
  then
    raise exception 'V1_PEOPLE_INVALID' using errcode = '22023';
  end if;

  if v_document_id is null then
    -- A second current visa, passport, labour card, ILOE or Emirates ID
    -- is a renewal of the one held, said explicitly.
    if v_kind in ('visa', 'passport', 'labour_card', 'iloe', 'emirates_id')
    then
      select document.* into v_current
      from public.v1_people_documents document
      where document.worker_id = v_worker_id and document.kind = v_kind
        and document.is_current
      for update;
      if found then
        raise exception 'V1_PEOPLE_DOCUMENT_EXISTS' using errcode = '23505';
      end if;
    end if;
    insert into public.v1_people_documents (
      worker_id, kind, label, document_number, issue_date, expiry_date,
      sites, notes, created_by_auth_user_id, updated_by_auth_user_id,
      updated_by_role
    ) values (
      v_worker_id, v_kind, v_label, v_number, v_issue, v_expiry, v_sites,
      v_notes, v_actor, v_actor, v_role
    ) returning * into v_saved;
    perform public.v1_people_revision(
      v_worker_id, 'document', v_saved.id, 'created', null,
      public.v1_people_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  elsif v_renew then
    update public.v1_people_documents set
      is_current = false,
      ended_at = clock_timestamp(),
      ended_reason = 'renewed',
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where id = v_current.id;
    insert into public.v1_people_documents (
      worker_id, kind, label, document_number, issue_date, expiry_date,
      sites, notes, created_by_auth_user_id, updated_by_auth_user_id,
      updated_by_role
    ) values (
      v_worker_id, v_kind, v_label, v_number, v_issue, v_expiry, v_sites,
      v_notes, v_actor, v_actor, v_role
    ) returning * into v_saved;
    update public.v1_people_documents
    set replaced_by_document_id = v_saved.id
    where id = v_current.id;
    perform public.v1_people_revision(
      v_worker_id, 'document', v_saved.id, 'renewed',
      public.v1_people_document_json(v_current, v_today),
      public.v1_people_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  else
    update public.v1_people_documents set
      label = v_label,
      document_number = v_number,
      issue_date = v_issue,
      expiry_date = v_expiry,
      sites = v_sites,
      notes = v_notes,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where id = v_current.id
    returning * into v_saved;
    perform public.v1_people_revision(
      v_worker_id, 'document', v_saved.id, 'updated',
      public.v1_people_document_json(v_current, v_today),
      public.v1_people_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  end if;

  perform public.v1_write_audit_event(
    'people_document_' || case
      when v_document_id is null then 'created'
      when v_renew then 'renewed'
      else 'updated' end,
    'people_person', v_worker_id, null, null,
    jsonb_build_object(
      'document_id', v_saved.id, 'kind', v_kind,
      'expiry_date', v_saved.expiry_date
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_save_document', p_idempotency_key,
    jsonb_build_object('worker_id', v_worker_id, 'document_id', v_saved.id)
  );
  return public.v1_people_person_json(v_worker_id, true);
end;
$$;

-- A document no longer held (a cancelled visa, a returned pass). It stays
-- in the history.
create or replace function public.v1_people_end_document(
  p_document_id uuid,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_people_assert('people_records.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_document public.v1_people_documents%rowtype;
  v_saved public.v1_people_documents%rowtype;
  v_today date := public.v1_wf_today();
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_end_document', p_idempotency_key,
    jsonb_build_object(
      'document', p_document_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_people_person_json(
      (v_existing ->> 'worker_id')::uuid, true
    );
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'V1_PEOPLE_REASON_REQUIRED' using errcode = '22023';
  end if;
  select document.* into v_document
  from public.v1_people_documents document
  where document.id = p_document_id
  for update;
  if not found then
    raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not v_document.is_current
    or coalesce(p_expected_version, -1) <> v_document.record_version then
    perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
  end if;
  update public.v1_people_documents set
    is_current = false,
    ended_at = clock_timestamp(),
    ended_reason = v_reason,
    record_version = record_version + 1,
    updated_by_auth_user_id = v_actor,
    updated_by_role = v_role,
    updated_at = clock_timestamp()
  where id = p_document_id
  returning * into v_saved;
  perform public.v1_people_revision(
    v_document.worker_id, 'document', p_document_id, 'ended',
    public.v1_people_document_json(v_document, v_today),
    public.v1_people_document_json(v_saved, v_today), v_reason, v_actor,
    v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    'people_document_ended', 'people_person', v_document.worker_id, null,
    null, jsonb_build_object('document_id', p_document_id,
      'kind', v_document.kind),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_end_document', p_idempotency_key,
    jsonb_build_object('worker_id', v_document.worker_id)
  );
  return public.v1_people_person_json(v_document.worker_id, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Import (the Staff Documents & Passes tracker)
-- ---------------------------------------------------------------------------
--
-- The device reads the workbook and sends one entry per person, with gate
-- passes already joined to the person they belong to. The server matches
-- each entry to a worker by name and company (case, spacing and
-- punctuation ignored) and decides, per document, whether it is new,
-- unchanged, a correction of the same document, or a renewal. A blank cell
-- never clears a stored value, and an older expiry never replaces a newer
-- one. The preview writes nothing; the import applies every entry or none.

create or replace function public.v1_people_import_plan(
  p_payload jsonb,
  p_commit boolean,
  p_actor uuid,
  p_role text,
  p_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_people jsonb := p_payload -> 'people';
  v_joining date := coalesce(
    nullif(p_payload ->> 'joining_date', '')::date, v_today
  );
  v_entry jsonb;
  v_document jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_problems jsonb;
  v_changes jsonb;
  v_action text;
  v_name text;
  v_company text;
  v_category text;
  v_designation text;
  v_matches uuid[];
  v_worker_id uuid;
  v_profile public.v1_people_profiles%rowtype;
  v_current public.v1_people_documents%rowtype;
  v_saved public.v1_people_documents%rowtype;
  v_kind text;
  v_number text;
  v_expiry date;
  v_sites text;
  v_doc_action text;
  v_counts jsonb := jsonb_build_object(
    'new', 0, 'update', 0, 'unchanged', 0, 'problem', 0,
    'documents_new', 0, 'documents_renewed', 0, 'documents_updated', 0
  );
  v_seen text[] := '{}';
  v_key text;
  v_row_number integer;
  v_dob date;
  v_arabic text;
  v_unified text;
begin
  if v_people is null or jsonb_typeof(v_people) <> 'array'
    or jsonb_array_length(v_people) not between 1 and 1000 then
    raise exception 'V1_PEOPLE_IMPORT_INVALID' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(v_people) loop
    v_problems := '[]'::jsonb;
    v_changes := '[]'::jsonb;
    v_worker_id := null;
    v_profile := null;
    v_row_number := nullif(v_entry ->> 'row', '')::integer;
    v_name := btrim(regexp_replace(
      coalesce(v_entry ->> 'full_name', ''), '\s+', ' ', 'g'
    ));
    v_company := btrim(regexp_replace(
      coalesce(v_entry ->> 'employer_company', ''), '\s+', ' ', 'g'
    ));
    v_category := coalesce(nullif(v_entry ->> 'category', ''), 'labour');
    v_designation := nullif(btrim(coalesce(v_entry ->> 'designation', '')), '');
    v_arabic := nullif(btrim(coalesce(v_entry ->> 'arabic_name', '')), '');
    v_unified := nullif(btrim(coalesce(v_entry ->> 'unified_number', '')), '');
    begin
      v_dob := nullif(v_entry ->> 'date_of_birth', '')::date;
    exception when others then
      v_dob := null;
      v_problems := v_problems || '"date_of_birth"'::jsonb;
    end;

    if v_name = '' or char_length(v_name) > 180 then
      v_problems := v_problems || '"name"'::jsonb;
    end if;
    if v_company = '' or char_length(v_company) > 180 then
      v_problems := v_problems || '"company"'::jsonb;
    end if;
    if v_category not in ('staff', 'labour') then
      v_problems := v_problems || '"category"'::jsonb;
    end if;
    v_key := public.v1_people_key(v_name) || '|' || public.v1_people_key(v_company);
    if v_key = any(v_seen) then
      v_problems := v_problems || '"repeated"'::jsonb;
    end if;
    v_seen := v_seen || v_key;

    if jsonb_array_length(v_problems) = 0 then
      select coalesce(array_agg(worker.id), '{}') into v_matches
      from public.v1_workforce_workers worker
      where public.v1_people_key(worker.full_name)
          = public.v1_people_key(v_name)
        and public.v1_people_key(worker.employer_company)
          = public.v1_people_key(v_company);
      if cardinality(v_matches) > 1 then
        v_problems := v_problems || '"ambiguous"'::jsonb;
      elsif cardinality(v_matches) = 1 then
        v_worker_id := v_matches[1];
      end if;
    end if;

    if jsonb_array_length(v_problems) > 0 then
      v_action := 'problem';
    elsif v_worker_id is null then
      v_action := 'new';
      if p_commit then
        insert into public.v1_workforce_workers (
          worker_number, full_name, designation, employer_company,
          worker_type, joining_date, created_by_auth_user_id,
          updated_by_auth_user_id
        ) values (
          'WR-' || lpad(
            nextval('public.v1_worker_record_number_seq')::text, 6, '0'
          ),
          v_name, coalesce(v_designation, 'Not recorded'), v_company,
          'yorks_employee', v_joining, p_actor, p_actor
        ) returning id into v_worker_id;
        insert into public.v1_people_profiles (
          worker_id, category, arabic_name, date_of_birth, unified_number,
          source_note, created_by_auth_user_id, updated_by_auth_user_id,
          updated_by_role
        ) values (
          v_worker_id, v_category, v_arabic, v_dob, v_unified,
          nullif(btrim(coalesce(v_entry ->> 'source_note', '')), ''),
          p_actor, p_actor, p_role
        );
      end if;
    else
      v_action := 'unchanged';
      select profile.* into v_profile
      from public.v1_people_profiles profile
      where profile.worker_id = v_worker_id
      for update;
      -- Profile: a filled cell that differs updates; a blank keeps.
      if v_profile.worker_id is null
        or (v_arabic is not null
          and v_arabic is distinct from v_profile.arabic_name)
        or (v_dob is not null
          and v_dob is distinct from v_profile.date_of_birth)
        or (v_unified is not null
          and v_unified is distinct from v_profile.unified_number)
      then
        v_action := 'update';
        v_changes := v_changes || '"profile"'::jsonb;
        if p_commit then
          insert into public.v1_people_profiles (
            worker_id, category, arabic_name, date_of_birth, unified_number,
            source_note, created_by_auth_user_id, updated_by_auth_user_id,
            updated_by_role
          ) values (
            v_worker_id, v_category, v_arabic, v_dob, v_unified,
            nullif(btrim(coalesce(v_entry ->> 'source_note', '')), ''),
            p_actor, p_actor, p_role
          )
          on conflict (worker_id) do update set
            arabic_name = coalesce(excluded.arabic_name,
              public.v1_people_profiles.arabic_name),
            date_of_birth = coalesce(excluded.date_of_birth,
              public.v1_people_profiles.date_of_birth),
            unified_number = coalesce(excluded.unified_number,
              public.v1_people_profiles.unified_number),
            record_version = public.v1_people_profiles.record_version + 1,
            updated_by_auth_user_id = p_actor,
            updated_by_role = p_role,
            updated_at = clock_timestamp();
        end if;
      end if;
      if v_designation is not null and exists (
        select 1 from public.v1_workforce_workers worker
        where worker.id = v_worker_id
          and worker.designation = 'Not recorded'
      ) then
        v_action := 'update';
        v_changes := v_changes || '"profession"'::jsonb;
        if p_commit then
          update public.v1_workforce_workers set
            designation = v_designation,
            record_version = record_version + 1,
            updated_by_auth_user_id = p_actor,
            updated_at = clock_timestamp()
          where id = v_worker_id;
        end if;
      end if;
    end if;

    -- Documents.
    if v_action <> 'problem' then
      for v_document in
        select value from jsonb_array_elements(
          coalesce(v_entry -> 'documents', '[]'::jsonb)
        )
      loop
        v_kind := v_document ->> 'kind';
        v_number := nullif(btrim(coalesce(v_document ->> 'number', '')), '');
        v_sites := nullif(btrim(coalesce(v_document ->> 'sites', '')), '');
        begin
          v_expiry := nullif(v_document ->> 'expiry_date', '')::date;
        exception when others then
          v_problems := v_problems || '"document_date"'::jsonb;
          continue;
        end;
        if v_kind is null or v_kind not in (
            'visa', 'passport', 'labour_card', 'iloe', 'emirates_id',
            'cicpa_pass', 'cmw_pass'
          )
          or (v_number is null and v_expiry is null
            and not (v_kind in ('cicpa_pass', 'cmw_pass')
              and v_sites is not null))
          or char_length(coalesce(v_number, '')) > 60
          or char_length(coalesce(v_sites, '')) > 500 then
          v_problems := v_problems || '"document"'::jsonb;
          continue;
        end if;
        v_current := null;
        if v_worker_id is not null then
          if v_kind in ('cicpa_pass', 'cmw_pass') then
            select document.* into v_current
            from public.v1_people_documents document
            where document.worker_id = v_worker_id
              and document.kind = v_kind and document.is_current
              and (
                (v_number is not null and document.document_number = v_number)
                or (v_number is null and document.document_number is null
                  and public.v1_people_key(document.sites)
                    = public.v1_people_key(v_sites))
              )
            order by document.created_at
            limit 1
            for update;
          else
            select document.* into v_current
            from public.v1_people_documents document
            where document.worker_id = v_worker_id
              and document.kind = v_kind and document.is_current
            for update;
          end if;
        end if;

        if v_current.id is null then
          v_doc_action := 'new';
        elsif v_current.expiry_date is not distinct from v_expiry
          and (v_number is null
            or v_current.document_number is not distinct from v_number)
          and (v_sites is null
            or public.v1_people_key(v_current.sites)
              = public.v1_people_key(v_sites)) then
          v_doc_action := 'unchanged';
        elsif v_expiry is not null and v_current.expiry_date is not null
          and v_expiry < v_current.expiry_date then
          -- An older sheet never replaces a newer document.
          v_doc_action := 'unchanged';
        elsif v_expiry is not null
          and v_current.expiry_date is distinct from v_expiry
          and v_current.expiry_date is not null then
          v_doc_action := 'renewed';
        else
          v_doc_action := 'updated';
        end if;

        if v_doc_action <> 'unchanged' then
          if v_action = 'unchanged' then
            v_action := 'update';
          end if;
          v_changes := v_changes || to_jsonb(v_kind || ':' || v_doc_action);
          v_counts := jsonb_set(v_counts, array['documents_' || v_doc_action],
            to_jsonb((v_counts ->> ('documents_' || v_doc_action))::integer
              + 1));
        end if;

        if p_commit and v_doc_action <> 'unchanged' then
          if v_doc_action = 'new' then
            insert into public.v1_people_documents (
              worker_id, kind, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_worker_id, v_kind, v_number, v_expiry, v_sites, p_actor,
              p_actor, p_role
            ) returning * into v_saved;
          elsif v_doc_action = 'renewed' then
            update public.v1_people_documents set
              is_current = false, ended_at = clock_timestamp(),
              ended_reason = 'renewed',
              record_version = record_version + 1,
              updated_by_auth_user_id = p_actor, updated_by_role = p_role,
              updated_at = clock_timestamp()
            where id = v_current.id;
            insert into public.v1_people_documents (
              worker_id, kind, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_worker_id, v_kind,
              coalesce(v_number, v_current.document_number), v_expiry,
              coalesce(v_sites, v_current.sites), p_actor, p_actor, p_role
            ) returning * into v_saved;
            update public.v1_people_documents
            set replaced_by_document_id = v_saved.id
            where id = v_current.id;
          else
            update public.v1_people_documents set
              document_number = coalesce(v_number, document_number),
              expiry_date = coalesce(v_expiry, expiry_date),
              sites = coalesce(v_sites, sites),
              record_version = record_version + 1,
              updated_by_auth_user_id = p_actor, updated_by_role = p_role,
              updated_at = clock_timestamp()
            where id = v_current.id
            returning * into v_saved;
          end if;
        end if;
      end loop;
    end if;

    if jsonb_array_length(v_problems) > 0 then
      v_action := 'problem';
    end if;
    if p_commit and v_action in ('new', 'update') then
      perform public.v1_people_revision(
        v_worker_id, 'person', v_worker_id, 'imported', null,
        jsonb_build_object(
          'source', nullif(p_payload ->> 'source_name', ''),
          'row', v_row_number, 'changes', v_changes
        ),
        null, p_actor, p_role, p_key
      );
    end if;
    v_counts := jsonb_set(v_counts, array[v_action],
      to_jsonb((v_counts ->> v_action)::integer + 1));
    v_rows := v_rows || jsonb_build_object(
      'row', v_row_number,
      'name', v_name,
      'company', v_company,
      'category', v_category,
      'action', v_action,
      'worker_id', v_worker_id,
      'changes', v_changes,
      'problems', v_problems
    );
  end loop;

  return jsonb_build_object(
    'schema_version', 'yorks.people.import.v1',
    'counts', v_counts,
    'rows', v_rows
  );
end;
$$;

create or replace function public.v1_people_preview_import(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_people_assert('people_records.manage');
begin
  perform public.v1_assert_object_keys(
    p_payload, array['source_name', 'joining_date', 'people'],
    'people_import_payload'
  );
  return public.v1_people_import_plan(
    p_payload, false, v_actor, public.v1_current_exact_role(), null
  );
end;
$$;

create or replace function public.v1_people_import(
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_people_assert('people_records.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_result jsonb;
begin
  perform public.v1_assert_object_keys(
    p_payload, array['source_name', 'joining_date', 'people'],
    'people_import_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_import', p_idempotency_key, p_payload
  );
  if v_existing is not null then
    return v_existing;
  end if;
  -- One import at a time, so two people importing the same sheet cannot
  -- both add the same person.
  perform pg_advisory_xact_lock(hashtext('v1_people_import'));
  v_result := public.v1_people_import_plan(
    p_payload, false, v_actor, v_role, p_idempotency_key
  );
  if (v_result -> 'counts' ->> 'problem')::integer > 0 then
    raise exception 'V1_PEOPLE_IMPORT_HAS_PROBLEMS' using errcode = '22023';
  end if;
  v_result := public.v1_people_import_plan(
    p_payload, true, v_actor, v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    'people_imported', 'people_import', p_idempotency_key, null, null,
    v_result -> 'counts', nullif(p_payload ->> 'source_name', ''),
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_import', p_idempotency_key, v_result
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------

revoke all on function
  public.v1_people_assert(text),
  public.v1_people_status(date, date),
  public.v1_people_kind_order(text),
  public.v1_people_key(text),
  public.v1_people_document_json(public.v1_people_documents, date),
  public.v1_people_person_json(uuid, boolean),
  public.v1_people_revision(uuid, text, uuid, text, jsonb, jsonb, text, uuid,
    text, uuid),
  public.v1_people_import_plan(jsonb, boolean, uuid, text, uuid),
  public.v1_people_block_history_change()
  from public, anon, authenticated;

revoke all on function
  public.v1_people_overview(),
  public.v1_people_list(jsonb),
  public.v1_people_get(uuid),
  public.v1_people_save_person(jsonb, bigint, uuid),
  public.v1_people_save_document(jsonb, bigint, uuid),
  public.v1_people_end_document(uuid, text, bigint, uuid),
  public.v1_people_preview_import(jsonb),
  public.v1_people_import(jsonb, uuid)
  from public, anon;
grant execute on function
  public.v1_people_overview(),
  public.v1_people_list(jsonb),
  public.v1_people_get(uuid),
  public.v1_people_save_person(jsonb, bigint, uuid),
  public.v1_people_save_document(jsonb, bigint, uuid),
  public.v1_people_end_document(uuid, text, bigint, uuid),
  public.v1_people_preview_import(jsonb),
  public.v1_people_import(jsonb, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;

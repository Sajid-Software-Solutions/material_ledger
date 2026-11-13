-- Company documents: trade licences and permits per company and branch,
-- company-wide certificates, vehicles and their passes, insurance policies
-- and CICPA contracts (owner request, 13 November 2026; PRODUCT_DECISIONS
-- section 43). Source: the Company Licenses & Permits and CICPA Contracts
-- sheets of the Staff Documents & Passes tracker, its insurance lines and
-- its vehicle gate passes.
--
-- A record is the thing tracked: a company or branch (entity), a company
-- certificate or permit (item), a vehicle, an insurance policy or a CICPA
-- contract. Each record holds dated documents (a commercial licence, an
-- establishment card, a registration, an Asateel permit, a CICPA pass, a
-- policy, an LOA). A renewal keeps the previous document as history, and
-- every change is kept in an append-only history.
--
-- Access is two new enforced capabilities in their own module,
-- `company_documents.view` and `company_documents.manage`, held by Admin, PR
-- and Accountant. Nothing is readable through table grants. Every function
-- the app calls is VOLATILE: PostgREST runs STABLE functions read-only, and
-- each one syncs the caller's profile first (see 20261114130000).
--
-- Data preservation: additive. Two capabilities, three tables, functions.
-- The Accountant and PR capability boundaries each gain exactly these two
-- keys. Rollback: set both catalogue rows to is_assignable = false and turn
-- the client flag off; keep every row.

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
  'company_documents.view', 'company_documents', 'view',
  'View company documents',
  'Read company licences, permits, certificates, vehicles, insurance policies and CICPA contracts.',
  'high', array['organization']::text[], false, '{}'::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'company_documents.view'
);

insert into public.v1_capability_catalog (
  capability_key, module_key, action_key, label, description, risk_level,
  allowed_scope_kinds, requires_project_access, dependencies, status,
  authorization_mode, is_assignable, display_order
)
select
  'company_documents.manage', 'company_documents', 'manage',
  'Manage company documents',
  'Add and edit company records, record and renew their documents, import and export the tracker.',
  'high', array['organization']::text[], false,
  array['company_documents.view']::text[],
  'operational', 'enforced', true,
  (select coalesce(max(display_order), 0) + 1
   from public.v1_capability_catalog)
where not exists (
  select 1 from public.v1_capability_catalog
  where capability_key = 'company_documents.manage'
);

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
  'company_documents.view', 'company_documents.manage'
]::text[]) capability_key
on conflict (role_name, capability_key) do nothing;

-- Accountant: the narrow exceptions beside Accounts.
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
      'people_records.view', 'people_records.manage',
      'company_documents.view', 'company_documents.manage'
    );
$$;

revoke all on function public.v1_accountant_may_hold_capability(text)
  from public, anon, authenticated;

-- PR: the fixed list gains exactly the two keys. The replacement refuses to
-- run unless the live definition still lists people records once, so a
-- later change to the list is never silently overwritten.
do $pr_boundary$
declare
  v_definition text := pg_catalog.pg_get_functiondef(
    'public.v1_pr_may_hold_capability(text)'::regprocedure
  );
  v_old text := '''people_records.view'', ''people_records.manage'',';
  v_new text := '''people_records.view'', ''people_records.manage'',
    ''company_documents.view'', ''company_documents.manage'',';
begin
  if position('company_documents.view' in v_definition) > 0 then
    return;
  end if;
  if (char_length(v_definition)
      - char_length(replace(v_definition, v_old, '')))
    / char_length(v_old) <> 1 then
    raise exception 'V1_COMPANY_DOCS_PR_BOUNDARY_DRIFT'
      using errcode = '55000';
  end if;
  execute replace(v_definition, v_old, v_new);
end;
$pr_boundary$;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.v1_company_docs_records (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in (
    'entity', 'item', 'vehicle', 'policy', 'contract'
  )),
  name text not null check (btrim(name) <> '' and char_length(name) <= 180),
  -- Licence number, plate, policy or LOA number.
  reference text check (
    reference is null
    or (btrim(reference) <> '' and char_length(reference) <= 80)
  ),
  -- The company or branch it belongs to, or Personal for a private car.
  owner text check (
    owner is null or (btrim(owner) <> '' and char_length(owner) <= 120)
  ),
  -- Contract: job, people, vehicles, applied_people, applied_vehicles.
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object'),
  notes text check (notes is null or char_length(notes) <= 1000),
  status text not null default 'active'
    check (status in ('active', 'archived')),
  archived_at timestamptz,
  archived_reason text check (
    archived_reason is null or char_length(archived_reason) <= 500
  ),
  source_note text check (source_note is null or char_length(source_note) <= 200),
  record_version bigint not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  updated_by_role text not null check (btrim(updated_by_role) <> ''),
  updated_at timestamptz not null default clock_timestamp(),
  check (status = 'active' or archived_at is not null)
);

create table if not exists public.v1_company_docs_documents (
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null
    references public.v1_company_docs_records (id) on delete restrict,
  kind text not null check (kind in (
    'licence', 'establishment_card', 'labour_file', 'pro_card',
    'certificate', 'registration', 'asateel_permit', 'cicpa_pass',
    'insurance', 'contract', 'other'
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
    references public.v1_company_docs_documents (id) on delete restrict,
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
  check (
    document_number is not null or expiry_date is not null
    or (kind = 'cicpa_pass' and sites is not null)
  ),
  check (
    expiry_date is null or issue_date is null or expiry_date >= issue_date
  ),
  check (is_current or ended_at is not null)
);

create index if not exists v1_company_docs_documents_record_idx
  on public.v1_company_docs_documents (record_id, kind) where is_current;
create index if not exists v1_company_docs_documents_expiry_idx
  on public.v1_company_docs_documents (expiry_date) where is_current;

create table if not exists public.v1_company_docs_revisions (
  id bigint generated always as identity primary key,
  record_id uuid not null
    references public.v1_company_docs_records (id) on delete restrict,
  entity text not null check (entity in ('record', 'document')),
  entity_id uuid not null,
  action text not null check (action in (
    'created', 'updated', 'renewed', 'ended', 'imported', 'archived',
    'restored'
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
create index if not exists v1_company_docs_revisions_record_idx
  on public.v1_company_docs_revisions (record_id, id desc);

create or replace function public.v1_company_docs_block_history_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'V1_COMPANY_DOCS_HISTORY_IMMUTABLE' using errcode = '55000';
end;
$$;

drop trigger if exists v1_company_docs_revisions_immutable
  on public.v1_company_docs_revisions;
create trigger v1_company_docs_revisions_immutable
  before update or delete on public.v1_company_docs_revisions
  for each row execute function public.v1_company_docs_block_history_change();
drop trigger if exists v1_company_docs_documents_no_delete
  on public.v1_company_docs_documents;
create trigger v1_company_docs_documents_no_delete
  before delete on public.v1_company_docs_documents
  for each row execute function public.v1_company_docs_block_history_change();
drop trigger if exists v1_company_docs_records_no_delete
  on public.v1_company_docs_records;
create trigger v1_company_docs_records_no_delete
  before delete on public.v1_company_docs_records
  for each row execute function public.v1_company_docs_block_history_change();

alter table public.v1_company_docs_records enable row level security;
alter table public.v1_company_docs_documents enable row level security;
alter table public.v1_company_docs_revisions enable row level security;
revoke all on table public.v1_company_docs_records,
  public.v1_company_docs_documents, public.v1_company_docs_revisions
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

create or replace function public.v1_company_docs_assert(p_capability_key text)
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
    'company_documents.view', 'company_documents.manage'
  ) then
    raise exception 'V1_COMPANY_DOCS_CAPABILITY_INVALID' using errcode = '22023';
  end if;
  if v_actor is null then
    raise exception 'V1_COMPANY_DOCS_DENIED' using errcode = '42501';
  end if;
  perform public.v1_sync_profile_from_auth(v_actor);
  if not public.v1_current_actor_is_active()
    or public.v1_permission_exact_role(v_actor) = ''
    or not public.v1_current_user_has_capability(p_capability_key, null)
  then
    raise exception 'V1_COMPANY_DOCS_DENIED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

create or replace function public.v1_company_docs_kind_order(p_kind text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_position(array[
    'licence', 'establishment_card', 'labour_file', 'pro_card',
    'registration', 'asateel_permit', 'cicpa_pass', 'insurance', 'contract',
    'certificate', 'other'
  ]::text[], p_kind), 99);
$$;

-- What identifies a record when importing: a plate or LOA number, a licence
-- holder by name and licence number, anything else by name and owner.
create or replace function public.v1_company_docs_identity(
  p_kind text,
  p_name text,
  p_reference text,
  p_owner text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_kind || ':' || case
    when p_kind in ('vehicle', 'contract')
      and nullif(public.v1_people_key(p_reference), '') is not null
      then 'ref:' || public.v1_people_key(p_reference)
    when p_kind = 'entity'
      then public.v1_people_key(p_name) || '|'
        || public.v1_people_key(p_reference)
    else public.v1_people_key(p_name) || '|' || public.v1_people_key(p_owner)
  end;
$$;

create or replace function public.v1_company_docs_document_json(
  p_document public.v1_company_docs_documents,
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
    'record_id', p_document.record_id,
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

-- One record. The register uses the short form; the record page adds the
-- previous documents and the history.
create or replace function public.v1_company_docs_record_json(
  p_record_id uuid,
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
    'id', record.id,
    'kind', record.kind,
    'name', record.name,
    'reference', record.reference,
    'owner', record.owner,
    'details', record.details,
    'notes', record.notes,
    'status', record.status,
    'archived_at', record.archived_at,
    'archived_reason', record.archived_reason,
    'source_note', record.source_note,
    'record_version', record.record_version,
    'updated_at', record.updated_at,
    'documents', coalesce((
      select jsonb_agg(
        public.v1_company_docs_document_json(document, today.day)
        order by public.v1_company_docs_kind_order(document.kind),
          document.label nulls first, document.expiry_date nulls last,
          document.created_at
      )
      from public.v1_company_docs_documents document
      where document.record_id = record.id and document.is_current
    ), '[]'::jsonb),
    'attention', coalesce((
      select case
        when bool_or(document.expiry_date < today.day) then 'expired'
        when bool_or(document.expiry_date <= today.day + 60) then 'expiring'
        else 'ok'
      end
      from public.v1_company_docs_documents document
      where document.record_id = record.id and document.is_current
        and document.expiry_date is not null
    ), 'ok'),
    'next_expiry', (
      select jsonb_build_object(
        'kind', document.kind, 'label', document.label,
        'expiry_date', document.expiry_date,
        'days_left', document.expiry_date - today.day
      )
      from public.v1_company_docs_documents document
      where document.record_id = record.id and document.is_current
        and document.expiry_date is not null
      order by document.expiry_date
      limit 1
    ),
    'previous_documents', case when p_detail then coalesce((
      select jsonb_agg(
        public.v1_company_docs_document_json(document, today.day)
        order by document.updated_at desc
      )
      from public.v1_company_docs_documents document
      where document.record_id = record.id and not document.is_current
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
          'label', coalesce(
            revision.after_data ->> 'label', revision.before_data ->> 'label'
          ),
          'reason', revision.reason,
          'actor_name', public.v1_wf_display_name(revision.actor_auth_user_id),
          'actor_role', revision.actor_role,
          'at', revision.created_at
        ) as item
        from public.v1_company_docs_revisions revision
        where revision.record_id = record.id
        order by revision.id desc
        limit 100
      ) recent
    ), '[]'::jsonb) end
  )
  from public.v1_company_docs_records record
  cross join today
  where record.id = p_record_id;
$$;

create or replace function public.v1_company_docs_revision(
  p_record_id uuid,
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
  insert into public.v1_company_docs_revisions (
    record_id, entity, entity_id, action, before_data, after_data, reason,
    actor_auth_user_id, actor_role, idempotency_key
  ) values (
    p_record_id, p_entity, p_entity_id, p_action, p_before, p_after,
    p_reason, p_actor, p_role, p_key
  );
$$;

-- Contract details are numbers; anything else in them is refused.
create or replace function public.v1_company_docs_details(
  p_kind text,
  p_details jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_out jsonb := '{}'::jsonb;
  v_key text;
  v_value text;
begin
  if jsonb_typeof(v_details) <> 'object' then
    raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
  end if;
  if p_kind <> 'contract' then
    if v_details <> '{}'::jsonb then
      raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
    end if;
    return v_out;
  end if;
  for v_key, v_value in select key, value #>> '{}' from jsonb_each(v_details)
  loop
    if v_key = 'job' then
      if v_value is not null and btrim(v_value) <> '' then
        if char_length(v_value) > 120 then
          raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
        end if;
        v_out := v_out || jsonb_build_object('job', btrim(v_value));
      end if;
    elsif v_key in (
      'people', 'vehicles', 'applied_people', 'applied_vehicles'
    ) then
      if v_value is not null and btrim(v_value) <> '' then
        if v_value !~ '^\d{1,5}$' then
          raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
        end if;
        v_out := v_out || jsonb_build_object(v_key, v_value::integer);
      end if;
    else
      raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
    end if;
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Reads
-- ---------------------------------------------------------------------------

create or replace function public.v1_company_docs_overview()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
begin
  perform public.v1_company_docs_assert('company_documents.view');
  return jsonb_build_object(
    'schema_version', 'yorks.company.overview.v1',
    'today', v_today,
    'can_manage', public.v1_current_user_has_capability(
      'company_documents.manage', null
    ),
    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'entity', count(*) filter (where record.kind = 'entity'),
        'item', count(*) filter (where record.kind = 'item'),
        'vehicle', count(*) filter (where record.kind = 'vehicle'),
        'policy', count(*) filter (where record.kind = 'policy'),
        'contract', count(*) filter (where record.kind = 'contract'),
        'expired', count(*) filter (where exists (
          select 1 from public.v1_company_docs_documents document
          where document.record_id = record.id and document.is_current
            and document.expiry_date < v_today
        )),
        'expiring', count(*) filter (where exists (
          select 1 from public.v1_company_docs_documents document
          where document.record_id = record.id and document.is_current
            and document.expiry_date between v_today and v_today + 60
        ))
      )
      from public.v1_company_docs_records record
      where record.status = 'active'
    ),
    'owners', coalesce((
      select jsonb_agg(jsonb_build_object('name', owner, 'count', n)
        order by n desc, owner)
      from (
        select record.owner, count(*) as n
        from public.v1_company_docs_records record
        where record.status = 'active' and record.owner is not null
        group by record.owner
      ) owners
    ), '[]'::jsonb),
    'attention', coalesce((
      select jsonb_agg(item order by expiry, name)
      from (
        select document.expiry_date as expiry, record.name as name,
          jsonb_build_object(
            'document', public.v1_company_docs_document_json(document, v_today),
            'record', jsonb_build_object(
              'id', record.id, 'kind', record.kind, 'name', record.name,
              'reference', record.reference, 'owner', record.owner
            )
          ) as item
        from public.v1_company_docs_documents document
        join public.v1_company_docs_records record
          on record.id = document.record_id
        where document.is_current and record.status = 'active'
          and document.expiry_date <= v_today + 60
        order by document.expiry_date, record.name
        limit 200
      ) attention
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.v1_company_docs_list(p_query jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_query jsonb := coalesce(p_query, '{}'::jsonb);
  v_kinds text[];
  v_owner text := nullif(v_query ->> 'owner', '');
  v_search text := nullif(btrim(coalesce(v_query ->> 'search', '')), '');
  v_status text := nullif(v_query ->> 'status', '');
  v_include_archived boolean := coalesce(
    (v_query ->> 'include_archived')::boolean, false
  );
  v_sort text := coalesce(nullif(v_query ->> 'sort', ''), 'name');
  v_limit integer := least(greatest(coalesce(
    (v_query ->> 'limit')::integer, 50), 1), 1000);
  v_offset integer := greatest(coalesce((v_query ->> 'offset')::integer, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform public.v1_company_docs_assert('company_documents.view');
  perform public.v1_assert_object_keys(
    v_query,
    array['kinds', 'owner', 'search', 'status', 'include_archived', 'sort',
      'limit', 'offset'],
    'company_list_query'
  );
  if v_query ? 'kinds' then
    if jsonb_typeof(v_query -> 'kinds') <> 'array' then
      raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
    end if;
    select array_agg(value) into v_kinds
    from jsonb_array_elements_text(v_query -> 'kinds');
  end if;
  if (v_kinds is not null and not v_kinds <@ array[
      'entity', 'item', 'vehicle', 'policy', 'contract'
    ]::text[])
    or (v_status is not null and v_status not in (
      'attention', 'expired', 'expiring'
    ))
    or v_sort not in ('name', 'expiry', 'owner') then
    raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
  end if;

  with filtered as (
    select record.id, record.name, record.owner,
      (select min(document.expiry_date)
       from public.v1_company_docs_documents document
       where document.record_id = record.id and document.is_current
      ) as next_expiry
    from public.v1_company_docs_records record
    where (v_include_archived or record.status = 'active')
      and (v_kinds is null or record.kind = any(v_kinds))
      and (v_owner is null or record.owner = v_owner)
      and (v_search is null
        or record.name ilike '%' || v_search || '%'
        or record.reference ilike '%' || v_search || '%'
        or record.owner ilike '%' || v_search || '%'
        or record.details ->> 'job' ilike '%' || v_search || '%'
        or exists (
          select 1 from public.v1_company_docs_documents document
          where document.record_id = record.id and document.is_current
            and (document.document_number ilike '%' || v_search || '%'
              or document.label ilike '%' || v_search || '%'
              or document.sites ilike '%' || v_search || '%')
        ))
      and (v_status is null or exists (
        select 1 from public.v1_company_docs_documents document
        where document.record_id = record.id and document.is_current
          and document.expiry_date is not null
          and case v_status
            when 'expired' then document.expiry_date < v_today
            when 'expiring' then document.expiry_date
              between v_today and v_today + 60
            else document.expiry_date <= v_today + 60
          end
      ))
  )
  select
    (select count(*)::integer from filtered),
    coalesce((
      select jsonb_agg(public.v1_company_docs_record_json(page.id, false)
        order by page.ord)
      from (
        select filtered.id, row_number() over (order by
          case when v_sort = 'expiry' then filtered.next_expiry end
            nulls last,
          case when v_sort = 'owner' then lower(filtered.owner) end
            nulls last,
          lower(filtered.name), filtered.id
        ) as ord
        from filtered
        order by ord
        offset v_offset
        limit v_limit
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

  return jsonb_build_object(
    'schema_version', 'yorks.company.list.v1',
    'today', v_today,
    'total', v_total,
    'offset', v_offset,
    'limit', v_limit,
    'rows', v_rows
  );
end;
$$;

create or replace function public.v1_company_docs_get(p_record_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_record jsonb;
begin
  perform public.v1_company_docs_assert('company_documents.view');
  v_record := public.v1_company_docs_record_json(p_record_id, true);
  if v_record is null then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  return v_record || jsonb_build_object(
    'can_manage', public.v1_current_user_has_capability(
      'company_documents.manage', null
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Writes
-- ---------------------------------------------------------------------------

-- Add a record or correct one. The kind is fixed once the record exists.
create or replace function public.v1_company_docs_save_record(
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_record_id uuid := nullif(p_payload ->> 'record_id', '')::uuid;
  v_kind text := nullif(p_payload ->> 'kind', '');
  v_name text := btrim(regexp_replace(
    coalesce(p_payload ->> 'name', ''), '\s+', ' ', 'g'
  ));
  v_reference text := nullif(btrim(coalesce(p_payload ->> 'reference', '')), '');
  v_owner text := nullif(btrim(regexp_replace(
    coalesce(p_payload ->> 'owner', ''), '\s+', ' ', 'g'
  )), '');
  v_notes text := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  v_details jsonb;
  v_current public.v1_company_docs_records%rowtype;
  v_saved public.v1_company_docs_records%rowtype;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_save_record', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_company_docs_record_json(
      (v_existing ->> 'record_id')::uuid, true
    );
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['record_id', 'kind', 'name', 'reference', 'owner', 'details',
      'notes'],
    'company_record_payload'
  );

  if v_record_id is not null then
    select record.* into v_current
    from public.v1_company_docs_records record
    where record.id = v_record_id
    for update;
    if not found then
      raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
    end if;
    if coalesce(p_expected_version, -1) <> v_current.record_version then
      perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
    end if;
    v_kind := v_current.kind;
  elsif coalesce(p_expected_version, 0) <> 0 then
    perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
  end if;

  if v_kind is null or v_kind not in (
      'entity', 'item', 'vehicle', 'policy', 'contract'
    )
    or v_name = '' or char_length(v_name) > 180
    or char_length(coalesce(v_reference, '')) > 80
    or char_length(coalesce(v_owner, '')) > 120
    or char_length(coalesce(v_notes, '')) > 1000 then
    raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
  end if;
  v_details := public.v1_company_docs_details(v_kind, p_payload -> 'details');

  if v_record_id is null then
    insert into public.v1_company_docs_records (
      kind, name, reference, owner, details, notes,
      created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
    ) values (
      v_kind, v_name, v_reference, v_owner, v_details, v_notes,
      v_actor, v_actor, v_role
    ) returning * into v_saved;
    perform public.v1_company_docs_revision(
      v_saved.id, 'record', v_saved.id, 'created', null,
      to_jsonb(v_saved) - 'created_by_auth_user_id'
        - 'updated_by_auth_user_id',
      null, v_actor, v_role, p_idempotency_key
    );
  else
    update public.v1_company_docs_records set
      name = v_name,
      reference = v_reference,
      owner = v_owner,
      details = v_details,
      notes = v_notes,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where id = v_record_id
    returning * into v_saved;
    perform public.v1_company_docs_revision(
      v_saved.id, 'record', v_saved.id, 'updated',
      to_jsonb(v_current) - 'created_by_auth_user_id'
        - 'updated_by_auth_user_id',
      to_jsonb(v_saved) - 'created_by_auth_user_id'
        - 'updated_by_auth_user_id',
      null, v_actor, v_role, p_idempotency_key
    );
  end if;

  perform public.v1_write_audit_event(
    case when v_record_id is null then 'company_record_created'
      else 'company_record_updated' end,
    'company_docs_record', v_saved.id, null, null,
    jsonb_build_object('kind', v_saved.kind, 'name', v_saved.name),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_save_record', p_idempotency_key,
    jsonb_build_object('record_id', v_saved.id)
  );
  return public.v1_company_docs_record_json(v_saved.id, true);
end;
$$;

-- No longer held (a sold vehicle, a finished contract) or back in use.
create or replace function public.v1_company_docs_set_archived(
  p_record_id uuid,
  p_archived boolean,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_current public.v1_company_docs_records%rowtype;
  v_saved public.v1_company_docs_records%rowtype;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_set_archived', p_idempotency_key,
    jsonb_build_object(
      'record', p_record_id, 'archived', p_archived, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_company_docs_record_json(p_record_id, true);
  end if;
  if p_archived is null
    or (p_archived and (v_reason is null or char_length(v_reason) > 500)) then
    raise exception 'V1_COMPANY_DOCS_REASON_REQUIRED' using errcode = '22023';
  end if;
  select record.* into v_current
  from public.v1_company_docs_records record
  where record.id = p_record_id
  for update;
  if not found then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  if coalesce(p_expected_version, -1) <> v_current.record_version
    or (v_current.status = 'archived') = p_archived then
    perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
  end if;
  update public.v1_company_docs_records set
    status = case when p_archived then 'archived' else 'active' end,
    archived_at = case when p_archived then clock_timestamp() end,
    archived_reason = case when p_archived then v_reason end,
    record_version = record_version + 1,
    updated_by_auth_user_id = v_actor,
    updated_by_role = v_role,
    updated_at = clock_timestamp()
  where id = p_record_id
  returning * into v_saved;
  perform public.v1_company_docs_revision(
    p_record_id, 'record', p_record_id,
    case when p_archived then 'archived' else 'restored' end,
    jsonb_build_object('status', v_current.status),
    jsonb_build_object('status', v_saved.status),
    v_reason, v_actor, v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    case when p_archived then 'company_record_archived'
      else 'company_record_restored' end,
    'company_docs_record', p_record_id, null, null,
    jsonb_build_object('kind', v_saved.kind, 'name', v_saved.name),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_set_archived', p_idempotency_key,
    jsonb_build_object('record_id', p_record_id)
  );
  return public.v1_company_docs_record_json(p_record_id, true);
end;
$$;

create or replace function public.v1_company_docs_save_document(
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_record_id uuid := nullif(p_payload ->> 'record_id', '')::uuid;
  v_document_id uuid := nullif(p_payload ->> 'document_id', '')::uuid;
  v_renew boolean := coalesce((p_payload ->> 'renew')::boolean, false);
  v_kind text := nullif(p_payload ->> 'kind', '');
  v_label text := nullif(btrim(coalesce(p_payload ->> 'label', '')), '');
  v_number text := nullif(btrim(coalesce(p_payload ->> 'number', '')), '');
  v_issue date := nullif(p_payload ->> 'issue_date', '')::date;
  v_expiry date := nullif(p_payload ->> 'expiry_date', '')::date;
  v_sites text := nullif(btrim(coalesce(p_payload ->> 'sites', '')), '');
  v_notes text := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  v_current public.v1_company_docs_documents%rowtype;
  v_saved public.v1_company_docs_documents%rowtype;
  v_today date := public.v1_wf_today();
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_save_document', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_company_docs_record_json(
      (v_existing ->> 'record_id')::uuid, true
    );
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['record_id', 'document_id', 'renew', 'kind', 'label', 'number',
      'issue_date', 'expiry_date', 'sites', 'notes'],
    'company_document_payload'
  );
  if v_record_id is null or not exists (
    select 1 from public.v1_company_docs_records record
    where record.id = v_record_id
  ) then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.v1_company_docs_records
  where id = v_record_id for update;

  if v_document_id is not null then
    select document.* into v_current
    from public.v1_company_docs_documents document
    where document.id = v_document_id and document.record_id = v_record_id
    for update;
    if not found or not v_current.is_current
      or coalesce(p_expected_version, -1) <> v_current.record_version then
      perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
    end if;
    v_kind := v_current.kind;
    v_label := coalesce(v_label, v_current.label);
  elsif v_renew or coalesce(p_expected_version, 0) <> 0 then
    perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
  end if;

  if v_kind is null or v_kind not in (
      'licence', 'establishment_card', 'labour_file', 'pro_card',
      'certificate', 'registration', 'asateel_permit', 'cicpa_pass',
      'insurance', 'contract', 'other'
    )
    or (v_kind = 'other' and v_label is null)
    or (v_number is null and v_expiry is null
      and not (v_kind = 'cicpa_pass' and v_sites is not null))
    or char_length(coalesce(v_number, '')) > 60
    or char_length(coalesce(v_label, '')) > 120
    or char_length(coalesce(v_sites, '')) > 500
    or char_length(coalesce(v_notes, '')) > 1000
    or (v_issue is not null and v_expiry is not null and v_expiry < v_issue)
  then
    raise exception 'V1_COMPANY_DOCS_INVALID' using errcode = '22023';
  end if;

  if v_document_id is null then
    insert into public.v1_company_docs_documents (
      record_id, kind, label, document_number, issue_date, expiry_date,
      sites, notes, created_by_auth_user_id, updated_by_auth_user_id,
      updated_by_role
    ) values (
      v_record_id, v_kind, v_label, v_number, v_issue, v_expiry, v_sites,
      v_notes, v_actor, v_actor, v_role
    ) returning * into v_saved;
    perform public.v1_company_docs_revision(
      v_record_id, 'document', v_saved.id, 'created', null,
      public.v1_company_docs_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  elsif v_renew then
    update public.v1_company_docs_documents set
      is_current = false,
      ended_at = clock_timestamp(),
      ended_reason = 'renewed',
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where id = v_current.id;
    insert into public.v1_company_docs_documents (
      record_id, kind, label, document_number, issue_date, expiry_date,
      sites, notes, created_by_auth_user_id, updated_by_auth_user_id,
      updated_by_role
    ) values (
      v_record_id, v_kind, v_label, v_number, v_issue, v_expiry, v_sites,
      v_notes, v_actor, v_actor, v_role
    ) returning * into v_saved;
    update public.v1_company_docs_documents
    set replaced_by_document_id = v_saved.id
    where id = v_current.id;
    perform public.v1_company_docs_revision(
      v_record_id, 'document', v_saved.id, 'renewed',
      public.v1_company_docs_document_json(v_current, v_today),
      public.v1_company_docs_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  else
    update public.v1_company_docs_documents set
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
    perform public.v1_company_docs_revision(
      v_record_id, 'document', v_saved.id, 'updated',
      public.v1_company_docs_document_json(v_current, v_today),
      public.v1_company_docs_document_json(v_saved, v_today), null, v_actor,
      v_role, p_idempotency_key
    );
  end if;

  perform public.v1_write_audit_event(
    'company_document_' || case
      when v_document_id is null then 'created'
      when v_renew then 'renewed'
      else 'updated' end,
    'company_docs_record', v_record_id, null, null,
    jsonb_build_object(
      'document_id', v_saved.id, 'kind', v_kind,
      'expiry_date', v_saved.expiry_date
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_save_document', p_idempotency_key,
    jsonb_build_object('record_id', v_record_id, 'document_id', v_saved.id)
  );
  return public.v1_company_docs_record_json(v_record_id, true);
end;
$$;

create or replace function public.v1_company_docs_end_document(
  p_document_id uuid,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_document public.v1_company_docs_documents%rowtype;
  v_saved public.v1_company_docs_documents%rowtype;
  v_today date := public.v1_wf_today();
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_end_document', p_idempotency_key,
    jsonb_build_object(
      'document', p_document_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_company_docs_record_json(
      (v_existing ->> 'record_id')::uuid, true
    );
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'V1_COMPANY_DOCS_REASON_REQUIRED' using errcode = '22023';
  end if;
  select document.* into v_document
  from public.v1_company_docs_documents document
  where document.id = p_document_id
  for update;
  if not found then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not v_document.is_current
    or coalesce(p_expected_version, -1) <> v_document.record_version then
    perform public.v1_raise_version_conflict('V1_COMPANY_DOCS_VERSION_CONFLICT');
  end if;
  update public.v1_company_docs_documents set
    is_current = false,
    ended_at = clock_timestamp(),
    ended_reason = v_reason,
    record_version = record_version + 1,
    updated_by_auth_user_id = v_actor,
    updated_by_role = v_role,
    updated_at = clock_timestamp()
  where id = p_document_id
  returning * into v_saved;
  perform public.v1_company_docs_revision(
    v_document.record_id, 'document', p_document_id, 'ended',
    public.v1_company_docs_document_json(v_document, v_today),
    public.v1_company_docs_document_json(v_saved, v_today), v_reason, v_actor,
    v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    'company_document_ended', 'company_docs_record', v_document.record_id, null,
    null, jsonb_build_object('document_id', p_document_id,
      'kind', v_document.kind),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_end_document', p_idempotency_key,
    jsonb_build_object('record_id', v_document.record_id)
  );
  return public.v1_company_docs_record_json(v_document.record_id, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Import
-- ---------------------------------------------------------------------------
--
-- The device reads the workbook and sends one entry per record with its
-- documents. The server matches each entry to a record (a plate or LOA
-- number; a licence holder by name and licence number; anything else by
-- name and owner) and, per document (kind and label), decides whether it
-- is new, unchanged, a correction or a renewal. A blank cell never clears a
-- stored value and an older expiry never replaces a newer one. The preview
-- writes nothing; the import applies every entry or none.

create or replace function public.v1_company_docs_import_plan(
  p_payload jsonb,
  p_commit boolean,
  p_actor uuid,
  p_role text,
  p_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_records jsonb := p_payload -> 'records';
  v_entry jsonb;
  v_document jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_problems jsonb;
  v_changes jsonb;
  v_action text;
  v_kind text;
  v_name text;
  v_reference text;
  v_owner text;
  v_details jsonb;
  v_identity text;
  v_matches uuid[];
  v_record_id uuid;
  v_record public.v1_company_docs_records%rowtype;
  v_current public.v1_company_docs_documents%rowtype;
  v_saved public.v1_company_docs_documents%rowtype;
  v_doc_kind text;
  v_label text;
  v_number text;
  v_expiry date;
  v_sites text;
  v_doc_action text;
  v_doc_seen text[];
  v_doc_key text;
  v_counts jsonb := jsonb_build_object(
    'new', 0, 'update', 0, 'unchanged', 0, 'problem', 0,
    'documents_new', 0, 'documents_renewed', 0, 'documents_updated', 0
  );
  v_seen text[] := '{}';
  v_row_number integer;
begin
  if v_records is null or jsonb_typeof(v_records) <> 'array'
    or jsonb_array_length(v_records) not between 1 and 1000 then
    raise exception 'V1_COMPANY_DOCS_IMPORT_INVALID' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(v_records) loop
    v_problems := '[]'::jsonb;
    v_changes := '[]'::jsonb;
    v_record_id := null;
    v_record := null;
    v_doc_seen := '{}';
    v_row_number := nullif(v_entry ->> 'row', '')::integer;
    v_kind := nullif(v_entry ->> 'kind', '');
    v_name := btrim(regexp_replace(
      coalesce(v_entry ->> 'name', ''), '\s+', ' ', 'g'
    ));
    v_reference := nullif(btrim(coalesce(v_entry ->> 'reference', '')), '');
    v_owner := nullif(btrim(regexp_replace(
      coalesce(v_entry ->> 'owner', ''), '\s+', ' ', 'g'
    )), '');
    v_details := '{}'::jsonb;

    if v_kind is null or v_kind not in (
      'entity', 'item', 'vehicle', 'policy', 'contract'
    ) then
      v_problems := v_problems || '"kind"'::jsonb;
      v_kind := coalesce(v_kind, 'item');
    end if;
    if v_name = '' or char_length(v_name) > 180 then
      v_problems := v_problems || '"name"'::jsonb;
    end if;
    if char_length(coalesce(v_reference, '')) > 80
      or char_length(coalesce(v_owner, '')) > 120 then
      v_problems := v_problems || '"too_long"'::jsonb;
    end if;
    begin
      v_details := public.v1_company_docs_details(v_kind, v_entry -> 'details');
    exception when others then
      v_problems := v_problems || '"details"'::jsonb;
    end;
    v_identity := public.v1_company_docs_identity(
      v_kind, v_name, v_reference, v_owner
    );
    if v_identity = any(v_seen) then
      v_problems := v_problems || '"repeated"'::jsonb;
    end if;
    v_seen := v_seen || v_identity;

    if jsonb_array_length(v_problems) = 0 then
      select coalesce(array_agg(record.id), '{}') into v_matches
      from public.v1_company_docs_records record
      where public.v1_company_docs_identity(
          record.kind, record.name, record.reference, record.owner
        ) = v_identity;
      if cardinality(v_matches) > 1 then
        v_problems := v_problems || '"ambiguous"'::jsonb;
      elsif cardinality(v_matches) = 1 then
        v_record_id := v_matches[1];
      end if;
    end if;

    if jsonb_array_length(v_problems) > 0 then
      v_action := 'problem';
    elsif v_record_id is null then
      v_action := 'new';
      if p_commit then
        insert into public.v1_company_docs_records (
          kind, name, reference, owner, details, source_note,
          created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
        ) values (
          v_kind, v_name, v_reference, v_owner, v_details,
          nullif(btrim(coalesce(v_entry ->> 'source_note', '')), ''),
          p_actor, p_actor, p_role
        ) returning id into v_record_id;
      end if;
    else
      v_action := 'unchanged';
      select record.* into v_record
      from public.v1_company_docs_records record
      where record.id = v_record_id
      for update;
      -- A filled cell that differs updates; a blank keeps.
      if (v_reference is not null
          and v_reference is distinct from v_record.reference)
        or (v_owner is not null and v_owner is distinct from v_record.owner)
        or (v_details <> '{}'::jsonb
          and (v_record.details || v_details) <> v_record.details)
      then
        v_action := 'update';
        v_changes := v_changes || '"record"'::jsonb;
        if p_commit then
          update public.v1_company_docs_records set
            reference = coalesce(v_reference, reference),
            owner = coalesce(v_owner, owner),
            details = details || v_details,
            record_version = record_version + 1,
            updated_by_auth_user_id = p_actor,
            updated_by_role = p_role,
            updated_at = clock_timestamp()
          where id = v_record_id;
        end if;
      end if;
    end if;

    if v_action <> 'problem' then
      for v_document in
        select value from jsonb_array_elements(
          coalesce(v_entry -> 'documents', '[]'::jsonb)
        )
      loop
        v_doc_kind := v_document ->> 'kind';
        v_label := nullif(btrim(coalesce(v_document ->> 'label', '')), '');
        v_number := nullif(btrim(coalesce(v_document ->> 'number', '')), '');
        v_sites := nullif(btrim(coalesce(v_document ->> 'sites', '')), '');
        begin
          v_expiry := nullif(v_document ->> 'expiry_date', '')::date;
        exception when others then
          v_problems := v_problems || '"document_date"'::jsonb;
          continue;
        end;
        if v_doc_kind is null or v_doc_kind not in (
            'licence', 'establishment_card', 'labour_file', 'pro_card',
            'certificate', 'registration', 'asateel_permit', 'cicpa_pass',
            'insurance', 'contract', 'other'
          )
          or (v_doc_kind = 'other' and v_label is null)
          or (v_number is null and v_expiry is null
            and not (v_doc_kind = 'cicpa_pass' and v_sites is not null))
          or char_length(coalesce(v_number, '')) > 60
          or char_length(coalesce(v_label, '')) > 120
          or char_length(coalesce(v_sites, '')) > 500 then
          v_problems := v_problems || '"document"'::jsonb;
          continue;
        end if;
        v_doc_key := v_doc_kind || '|' || public.v1_people_key(v_label);
        if v_doc_key = any(v_doc_seen) then
          v_problems := v_problems || '"document_repeated"'::jsonb;
          continue;
        end if;
        v_doc_seen := v_doc_seen || v_doc_key;

        v_current := null;
        if v_record_id is not null then
          select document.* into v_current
          from public.v1_company_docs_documents document
          where document.record_id = v_record_id
            and document.kind = v_doc_kind and document.is_current
            and public.v1_people_key(document.label)
              = public.v1_people_key(v_label)
          order by document.created_at
          limit 1
          for update;
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
          v_changes := v_changes || to_jsonb(v_doc_kind || ':' || v_doc_action);
          v_counts := jsonb_set(v_counts, array['documents_' || v_doc_action],
            to_jsonb((v_counts ->> ('documents_' || v_doc_action))::integer
              + 1));
        end if;

        if p_commit and v_doc_action <> 'unchanged' then
          if v_doc_action = 'new' then
            insert into public.v1_company_docs_documents (
              record_id, kind, label, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_record_id, v_doc_kind, v_label, v_number, v_expiry, v_sites,
              p_actor, p_actor, p_role
            ) returning * into v_saved;
          elsif v_doc_action = 'renewed' then
            update public.v1_company_docs_documents set
              is_current = false, ended_at = clock_timestamp(),
              ended_reason = 'renewed',
              record_version = record_version + 1,
              updated_by_auth_user_id = p_actor, updated_by_role = p_role,
              updated_at = clock_timestamp()
            where id = v_current.id;
            insert into public.v1_company_docs_documents (
              record_id, kind, label, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_record_id, v_doc_kind, v_current.label,
              coalesce(v_number, v_current.document_number), v_expiry,
              coalesce(v_sites, v_current.sites), p_actor, p_actor, p_role
            ) returning * into v_saved;
            update public.v1_company_docs_documents
            set replaced_by_document_id = v_saved.id
            where id = v_current.id;
          else
            update public.v1_company_docs_documents set
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
      perform public.v1_company_docs_revision(
        v_record_id, 'record', v_record_id, 'imported', null,
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
      'sheet', nullif(v_entry ->> 'sheet', ''),
      'kind', v_kind,
      'name', v_name,
      'reference', v_reference,
      'owner', v_owner,
      'action', v_action,
      'record_id', v_record_id,
      'changes', v_changes,
      'problems', v_problems
    );
  end loop;

  return jsonb_build_object(
    'schema_version', 'yorks.company.import.v1',
    'counts', v_counts,
    'rows', v_rows
  );
end;
$$;

create or replace function public.v1_company_docs_preview_import(p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
begin
  perform public.v1_assert_object_keys(
    p_payload, array['source_name', 'records'], 'company_import_payload'
  );
  return public.v1_company_docs_import_plan(
    p_payload, false, v_actor, public.v1_current_exact_role(), null
  );
end;
$$;

create or replace function public.v1_company_docs_import(
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_result jsonb;
begin
  perform public.v1_assert_object_keys(
    p_payload, array['source_name', 'records'], 'company_import_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_import', p_idempotency_key, p_payload
  );
  if v_existing is not null then
    return v_existing;
  end if;
  perform pg_advisory_xact_lock(hashtext('v1_company_docs_import'));
  v_result := public.v1_company_docs_import_plan(
    p_payload, false, v_actor, v_role, p_idempotency_key
  );
  if (v_result -> 'counts' ->> 'problem')::integer > 0 then
    raise exception 'V1_COMPANY_DOCS_IMPORT_HAS_PROBLEMS' using errcode = '22023';
  end if;
  v_result := public.v1_company_docs_import_plan(
    p_payload, true, v_actor, v_role, p_idempotency_key
  );
  perform public.v1_write_audit_event(
    'company_documents_imported', 'company_docs_import', p_idempotency_key, null,
    null, v_result -> 'counts', nullif(p_payload ->> 'source_name', ''),
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_import', p_idempotency_key, v_result
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------

revoke all on function
  public.v1_company_docs_assert(text),
  public.v1_company_docs_kind_order(text),
  public.v1_company_docs_identity(text, text, text, text),
  public.v1_company_docs_document_json(public.v1_company_docs_documents, date),
  public.v1_company_docs_record_json(uuid, boolean),
  public.v1_company_docs_revision(uuid, text, uuid, text, jsonb, jsonb, text, uuid,
    text, uuid),
  public.v1_company_docs_details(text, jsonb),
  public.v1_company_docs_import_plan(jsonb, boolean, uuid, text, uuid),
  public.v1_company_docs_block_history_change()
  from public, anon, authenticated;

revoke all on function
  public.v1_company_docs_overview(),
  public.v1_company_docs_list(jsonb),
  public.v1_company_docs_get(uuid),
  public.v1_company_docs_save_record(jsonb, bigint, uuid),
  public.v1_company_docs_set_archived(uuid, boolean, text, bigint, uuid),
  public.v1_company_docs_save_document(jsonb, bigint, uuid),
  public.v1_company_docs_end_document(uuid, text, bigint, uuid),
  public.v1_company_docs_preview_import(jsonb),
  public.v1_company_docs_import(jsonb, uuid)
  from public, anon;
grant execute on function
  public.v1_company_docs_overview(),
  public.v1_company_docs_list(jsonb),
  public.v1_company_docs_get(uuid),
  public.v1_company_docs_save_record(jsonb, bigint, uuid),
  public.v1_company_docs_set_archived(uuid, boolean, text, bigint, uuid),
  public.v1_company_docs_save_document(jsonb, bigint, uuid),
  public.v1_company_docs_end_document(uuid, text, bigint, uuid),
  public.v1_company_docs_preview_import(jsonb),
  public.v1_company_docs_import(jsonb, uuid)
  to authenticated;

commit;

notify pgrst, 'reload schema';

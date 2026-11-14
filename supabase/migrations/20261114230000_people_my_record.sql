-- My Yorks from the People record (owner decision, 14 November 2026;
-- PRODUCT_DECISIONS section 54).
--
--   * HR/PRO and Admin link an app account to the one People record of the
--     person who signs in with it (`v1_workforce_workers.linked_auth_user_id`,
--     already unique). Suggestions match account names to People names. A
--     link and an unlink are recorded in the person's history and the audit
--     trail.
--   * Everyone can read their own record, and only their own, through
--     `v1_people_get_mine`: names, position, the profession on the visa and
--     ID, current documents with expiry and status and only the last four
--     characters of each number, crew, this month's attendance, and their
--     projects. No date of birth or unified number. No People capability is
--     granted to anyone.
--   * A person cannot edit their record. They send HR/PRO a note instead;
--     PR and Admin are notified, read it on the record and mark it done.
--   * Each linked person also gets their own reminder when their documents
--     expire or are within 60 days, at most once a day and only on a change.
--
-- Data preservation: additive (two tables, functions, a schedule). The
-- person JSON gains `account` and `notes`; nothing else changes. No account
-- is linked by this migration. The three notification functions are
-- wrapped, keeping the previous ones as *_before_my_people.
-- Rollback: cron.unschedule('yorks-people-my-reminders'); restore the three
-- notification functions from their *_before_my_people versions,
-- v1_people_person_json from 20261114220000 and v1_people_get from
-- 20261114120000 (volatile); keep every row.

begin;

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

-- A note a person sends HR/PRO about their own record.
create table if not exists public.v1_people_notes (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  author_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  message text not null check (
    btrim(message) <> '' and char_length(message) <= 1000
  ),
  created_at timestamptz not null default clock_timestamp(),
  done_at timestamptz,
  done_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  done_by_role text check (done_by_role is null or btrim(done_by_role) <> ''),
  check ((done_at is null) = (done_by_auth_user_id is null)),
  check ((done_at is null) = (done_by_role is null))
);
create index if not exists v1_people_notes_worker_idx
  on public.v1_people_notes (worker_id, created_at desc);
create index if not exists v1_people_notes_author_idx
  on public.v1_people_notes (author_auth_user_id, created_at desc);

-- A note is never deleted, and only marking it done changes it.
create or replace function public.v1_people_notes_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    or old.done_at is not null
    or new.id <> old.id
    or new.worker_id <> old.worker_id
    or new.author_auth_user_id <> old.author_auth_user_id
    or new.message <> old.message
    or new.created_at <> old.created_at
  then
    raise exception 'V1_PEOPLE_HISTORY_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists v1_people_notes_guard on public.v1_people_notes;
create trigger v1_people_notes_guard
  before update or delete on public.v1_people_notes
  for each row execute function public.v1_people_notes_guard();

-- One personal expiry reminder per person per day.
create table if not exists public.v1_people_my_reminders (
  id uuid primary key default gen_random_uuid(),
  recipient_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  sent_on date not null,
  expired_count integer not null check (expired_count >= 0),
  expiring_count integer not null check (expiring_count >= 0),
  -- Which documents needed attention, so the next one is sent on a change.
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{32}$'),
  notification_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (recipient_auth_user_id, sent_on),
  check (expired_count + expiring_count > 0)
);
create index if not exists v1_people_my_reminders_recipient_idx
  on public.v1_people_my_reminders (recipient_auth_user_id, sent_on desc);

drop trigger if exists v1_people_my_reminders_no_delete
  on public.v1_people_my_reminders;
create trigger v1_people_my_reminders_no_delete
  before delete on public.v1_people_my_reminders
  for each row execute function public.v1_people_block_history_change();

alter table public.v1_people_notes enable row level security;
alter table public.v1_people_my_reminders enable row level security;
revoke all on table public.v1_people_notes, public.v1_people_my_reminders
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------

-- An app account as People shows it: name, email and role.
create or replace function public.v1_people_account_json(
  p_auth_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'auth_user_id', profile.auth_user_id,
    'name', coalesce(
      nullif(btrim(profile.display_name), ''), users.email::text, ''
    ),
    'email', users.email,
    'role', public.v1_permission_exact_role(profile.auth_user_id),
    'active', profile.is_active
  )
  from public.v1_profiles profile
  left join auth.users users on users.id = profile.auth_user_id
  where profile.auth_user_id = p_auth_user_id;
$$;

-- Only HR/PRO and Admin link accounts to people.
create or replace function public.v1_people_may_link()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.v1_permission_exact_role(auth.uid()) in ('pr', 'admin')
    and public.v1_current_user_has_capability('people_records.manage', null);
$$;

-- The last four letters or digits of a document number; nothing when the
-- number is four or fewer, so a short number is never shown whole.
create or replace function public.v1_people_last4(p_number text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when char_length(regexp_replace(coalesce(p_number, ''), '[^[:alnum:]]', '', 'g')) <= 4
      then null
    else right(regexp_replace(p_number, '[^[:alnum:]]', '', 'g'), 4)
  end;
$$;

-- The account owner's own view: what they may see of their record.
create or replace function public.v1_people_mine_json(p_worker_id uuid)
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
    'arabic_name', profile.arabic_name,
    'company', worker.employer_company,
    'position', worker.designation,
    'id_profession', profile.id_profession,
    'category', coalesce(profile.category, 'labour'),
    'status', worker.current_status,
    'joining_date', worker.joining_date,
    'documents', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'kind', document.kind,
          'label', document.label,
          'number_last4', public.v1_people_last4(document.document_number),
          'expiry_date', document.expiry_date,
          'days_left', case when document.expiry_date is null then null
            else document.expiry_date - today.day end,
          'status', public.v1_people_status(document.expiry_date, today.day),
          'sites', document.sites
        )
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
    'crew', (
      select jsonb_build_object('id', team.id, 'name', team.team_name)
      from public.v1_workforce_crew_members member
      join public.v1_workforce_teams team on team.id = member.team_id
      where member.worker_id = worker.id and member.removed_at is null
      limit 1
    ),
    -- This month so far, from the crew day sheets.
    'attendance', (
      select jsonb_build_object(
        'month', to_char(today.day, 'YYYY-MM'),
        'recorded_days', count(*)::integer,
        'present_days',
          count(*) filter (where row.attendance_status = 'P')::integer,
        'absent_days',
          count(*) filter (where row.attendance_status = 'A')::integer,
        'leave_days', count(*) filter (
          where row.attendance_status in ('AL', 'SL', 'OL', 'UL')
        )::integer,
        'off_days',
          count(*) filter (where row.attendance_status = 'OFF')::integer,
        'worked_minutes', coalesce(sum(row.worked_minutes), 0)::integer,
        'overtime_minutes', coalesce(sum(
          row.normal_overtime_minutes + row.holiday_overtime_minutes
        ), 0)::integer
      )
      from public.v1_workforce_day_rows row
      where row.worker_id = worker.id
        and row.work_date >= date_trunc('month', today.day)::date
        and row.work_date <= today.day
    ),
    'notes', coalesce((
      select jsonb_agg(item order by item ->> 'at' desc)
      from (
        select jsonb_build_object(
          'id', note.id,
          'message', note.message,
          'at', note.created_at,
          'done_at', note.done_at
        ) as item
        from public.v1_people_notes note
        where note.worker_id = worker.id
          and note.author_auth_user_id = worker.linked_auth_user_id
        order by note.created_at desc
        limit 5
      ) recent
    ), '[]'::jsonb)
  )
  from public.v1_workforce_workers worker
  cross join today
  left join public.v1_people_profiles profile
    on profile.worker_id = worker.id
  where worker.id = p_worker_id;
$$;

-- ---------------------------------------------------------------------------
-- 3. The person record gains its account and the person's notes.
-- ---------------------------------------------------------------------------

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
    'id_profession', profile.id_profession,
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
    -- The app account this person signs in with, when linked.
    'account', public.v1_people_account_json(worker.linked_auth_user_id),
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
    -- Notes the person sent HR/PRO about their own record.
    'notes', case when p_detail then coalesce((
      select jsonb_agg(item order by item ->> 'at' desc)
      from (
        select jsonb_build_object(
          'id', note.id,
          'message', note.message,
          'at', note.created_at,
          'done_at', note.done_at,
          'done_by', public.v1_wf_display_name(note.done_by_auth_user_id)
        ) as item
        from public.v1_people_notes note
        where note.worker_id = worker.id
        order by note.created_at desc
        limit 20
      ) recent
    ), '[]'::jsonb) end,
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

create or replace function public.v1_people_get(p_worker_id uuid)
returns jsonb
language plpgsql
volatile
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
    ),
    'can_link', public.v1_people_may_link()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Linking an account to a person (HR/PRO and Admin)
-- ---------------------------------------------------------------------------

-- Link [p_auth_user_id] to the person, or unlink when it is null. An account
-- belongs to one person; a person has one account.
create or replace function public.v1_people_set_account(
  p_worker_id uuid,
  p_auth_user_id uuid,
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
  v_worker public.v1_workforce_workers%rowtype;
  v_profile public.v1_people_profiles%rowtype;
  v_before jsonb;
  v_after jsonb;
begin
  if not public.v1_people_may_link() then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_set_account', p_idempotency_key,
    jsonb_build_object(
      'worker_id', p_worker_id, 'auth_user_id', p_auth_user_id,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_people_get((v_existing ->> 'worker_id')::uuid);
  end if;

  select worker.* into v_worker
  from public.v1_workforce_workers worker
  where worker.id = p_worker_id
  for update;
  select profile.* into v_profile
  from public.v1_people_profiles profile
  where profile.worker_id = p_worker_id
  for update;
  if v_worker.id is null or v_profile.worker_id is null then
    raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if coalesce(p_expected_version, -1) <> v_profile.record_version then
    perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
  end if;
  if p_auth_user_id is not null then
    if not exists (
      select 1 from public.v1_profiles profile
      where profile.auth_user_id = p_auth_user_id and profile.is_active
    ) then
      raise exception 'V1_PEOPLE_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
    end if;
    if exists (
      select 1 from public.v1_workforce_workers other
      where other.linked_auth_user_id = p_auth_user_id
        and other.id <> p_worker_id
    ) then
      raise exception 'V1_PEOPLE_ACCOUNT_TAKEN' using errcode = '23505';
    end if;
  end if;

  if v_worker.linked_auth_user_id is distinct from p_auth_user_id then
    v_before := jsonb_build_object(
      'account', public.v1_people_account_json(v_worker.linked_auth_user_id),
      'record_version', v_profile.record_version
    );
    update public.v1_workforce_workers set
      linked_auth_user_id = p_auth_user_id,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_at = clock_timestamp()
    where id = p_worker_id;
    update public.v1_people_profiles set
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_by_role = v_role,
      updated_at = clock_timestamp()
    where worker_id = p_worker_id;
    v_after := jsonb_build_object(
      'account', public.v1_people_account_json(p_auth_user_id),
      'record_version', v_profile.record_version + 1
    );
    perform public.v1_people_revision(
      p_worker_id, 'person', p_worker_id, 'updated', v_before, v_after,
      null, v_actor, v_role, p_idempotency_key
    );
    perform public.v1_write_audit_event(
      case when p_auth_user_id is null then 'people_account_unlinked'
        else 'people_account_linked' end,
      'people_person', p_worker_id, null,
      jsonb_build_object(
        'auth_user_id', v_worker.linked_auth_user_id
      ),
      jsonb_build_object(
        'auth_user_id', p_auth_user_id,
        'record_version', v_profile.record_version + 1
      ),
      null, p_idempotency_key
    );
  end if;

  perform public.v1_complete_idempotency(
    'v1_people_set_account', p_idempotency_key,
    jsonb_build_object('worker_id', p_worker_id)
  );
  return public.v1_people_get(p_worker_id);
end;
$$;

-- Every active account not yet linked, each with up to three People records
-- whose name matches its name.
create or replace function public.v1_people_link_suggestions()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform public.v1_people_assert('people_records.manage');
  if not public.v1_people_may_link() then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  with accounts as (
    select
      profile.auth_user_id,
      coalesce(nullif(btrim(profile.display_name), ''), users.email::text, '')
        as name,
      users.email::text as email,
      public.v1_permission_exact_role(profile.auth_user_id) as role,
      array(
        select distinct token
        from unnest(string_to_array(public.v1_people_key(
          coalesce(
            nullif(btrim(profile.display_name), ''),
            regexp_replace(split_part(users.email, '@', 1), '[._-]+', ' ', 'g')
          )
        ), ' ')) token
        where char_length(token) >= 2
      ) as tokens
    from public.v1_profiles profile
    left join auth.users users on users.id = profile.auth_user_id
    where profile.is_active
      and not exists (
        select 1 from public.v1_workforce_workers worker
        where worker.linked_auth_user_id = profile.auth_user_id
      )
  ),
  people as (
    select
      worker.id, worker.worker_number, worker.full_name,
      worker.employer_company, worker.designation, profile.category,
      string_to_array(public.v1_people_key(worker.full_name), ' ') as tokens
    from public.v1_workforce_workers worker
    join public.v1_people_profiles profile on profile.worker_id = worker.id
    where worker.linked_auth_user_id is null
      and worker.current_status = 'active'
  ),
  matches as (
    select
      account.auth_user_id, account.tokens as account_tokens, person.*,
      (
        select count(*) from unnest(account.tokens) token
        where token = any(person.tokens)
      ) as matched,
      cardinality(account.tokens) as wanted
    from accounts account
    cross join people person
    where account.tokens && person.tokens
  ),
  ranked as (
    select match.*,
      row_number() over (
        partition by match.auth_user_id
        order by match.matched desc, cardinality(match.tokens),
          match.full_name, match.id
      ) as rank
    from matches match
    -- Two names in common, or the account's only name (four letters or
    -- more) in the person's name.
    where match.matched >= 2
      or (match.wanted = 1 and match.matched = 1
        and char_length(match.account_tokens[1]) >= 4)
  )
  select jsonb_build_object(
    'linked_count', (
      select count(*) from public.v1_workforce_workers worker
      join public.v1_profiles profile
        on profile.auth_user_id = worker.linked_auth_user_id
      where profile.is_active
    ),
    'accounts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'auth_user_id', account.auth_user_id,
          'name', account.name,
          'email', account.email,
          'role', account.role,
          'suggestions', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'worker_id', ranked.id,
                'number', ranked.worker_number,
                'name', ranked.full_name,
                'company', ranked.employer_company,
                'position', ranked.designation,
                'category', ranked.category
              )
              order by ranked.rank
            )
            from ranked
            where ranked.auth_user_id = account.auth_user_id
              and ranked.rank <= 3
          ), '[]'::jsonb)
        )
        order by
          exists (
            select 1 from ranked
            where ranked.auth_user_id = account.auth_user_id
          ) desc,
          lower(account.name), account.auth_user_id
      )
      from accounts account
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. My record
-- ---------------------------------------------------------------------------

-- The caller's own record and work. Anyone signed in may call it; it only
-- ever reads the caller's own linked person.
create or replace function public.v1_people_get_mine()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_worker_id uuid;
begin
  if v_actor is null then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  perform public.v1_sync_profile_from_auth(v_actor);
  if not public.v1_current_actor_is_active()
    or public.v1_permission_exact_role(v_actor) = ''
  then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;

  select worker.id into v_worker_id
  from public.v1_workforce_workers worker
  where worker.linked_auth_user_id = v_actor;

  return jsonb_build_object(
    'state', case when v_worker_id is null then 'unlinked' else 'linked' end,
    'person', case when v_worker_id is null then null
      else public.v1_people_mine_json(v_worker_id) end,
    -- Projects the caller is a dated member of today.
    'projects', coalesce((
      select jsonb_agg(item order by item ->> 'name', item ->> 'id')
      from (
        select distinct on (project.id) jsonb_build_object(
          'id', project.id,
          'ref', project.project_ref,
          'name', project.name,
          'state', project.state,
          'role', membership.project_role
        ) as item
        from public.v1_project_members membership
        join public.v1_projects project on project.id = membership.project_id
        where membership.member_auth_user_id = v_actor
          and membership.effective_from <= statement_timestamp()
          and (membership.effective_to is null
            or membership.effective_to > statement_timestamp())
          and project.state <> 'archived'
        order by project.id,
          (membership.project_role = 'project_engineer') desc
      ) memberships
    ), '[]'::jsonb),
    'today', public.v1_wf_today()
  );
end;
$$;

-- A note to HR/PRO about the caller's own record. PR and Admin are told.
create or replace function public.v1_people_send_note(
  p_message text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_message text := btrim(coalesce(p_message, ''));
  v_existing jsonb;
  v_worker_id uuid;
  v_note uuid;
  v_recipient uuid;
begin
  if v_actor is null then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  perform public.v1_sync_profile_from_auth(v_actor);
  if not public.v1_current_actor_is_active()
    or public.v1_permission_exact_role(v_actor) = ''
  then
    raise exception 'V1_PEOPLE_DENIED' using errcode = '42501';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_send_note', p_idempotency_key,
    jsonb_build_object('message', p_message)
  );
  if v_existing is not null then
    return public.v1_people_get_mine();
  end if;
  if v_message = '' or char_length(v_message) > 1000 then
    raise exception 'V1_PEOPLE_INVALID' using errcode = '22023';
  end if;
  select worker.id into v_worker_id
  from public.v1_workforce_workers worker
  where worker.linked_auth_user_id = v_actor
  for update;
  if v_worker_id is null then
    raise exception 'V1_PEOPLE_NOT_LINKED' using errcode = 'P0002';
  end if;
  -- Five a day is plenty for corrections.
  if (
    select count(*) from public.v1_people_notes note
    where note.author_auth_user_id = v_actor
      and note.created_at > clock_timestamp() - interval '1 day'
  ) >= 5 then
    raise exception 'V1_PEOPLE_NOTE_LIMIT' using errcode = '22023';
  end if;

  insert into public.v1_people_notes (
    worker_id, author_auth_user_id, message
  ) values (
    v_worker_id, v_actor, v_message
  ) returning id into v_note;

  for v_recipient in
    select recipient from public.v1_people_expiry_recipients() recipient
    where recipient <> v_actor
  loop
    insert into public.v1_notifications (
      recipient_auth_user_id, event_code, entity_type, entity_id, project_id
    ) values (
      v_recipient, 'people_note_received', 'people_note', v_note, null
    );
  end loop;
  -- The audit trail records that a note was sent, never what it says.
  perform public.v1_write_audit_event(
    'people_note_sent', 'people_person', v_worker_id, null, null,
    jsonb_build_object('note_id', v_note), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_send_note', p_idempotency_key,
    jsonb_build_object('note_id', v_note)
  );
  return public.v1_people_get_mine();
end;
$$;

-- HR/PRO marks a note done once the record is corrected.
create or replace function public.v1_people_note_done(
  p_note_id uuid,
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
  v_note public.v1_people_notes%rowtype;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_note_done', p_idempotency_key,
    jsonb_build_object('note_id', p_note_id)
  );
  if v_existing is not null then
    return public.v1_people_get((v_existing ->> 'worker_id')::uuid);
  end if;
  select note.* into v_note
  from public.v1_people_notes note
  where note.id = p_note_id
  for update;
  if v_note.id is null then
    raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_note.done_at is null then
    update public.v1_people_notes set
      done_at = clock_timestamp(),
      done_by_auth_user_id = v_actor,
      done_by_role = v_role
    where id = p_note_id;
    perform public.v1_write_audit_event(
      'people_note_done', 'people_person', v_note.worker_id, null, null,
      jsonb_build_object('note_id', p_note_id), null, p_idempotency_key
    );
  end if;
  perform public.v1_complete_idempotency(
    'v1_people_note_done', p_idempotency_key,
    jsonb_build_object('worker_id', v_note.worker_id)
  );
  return public.v1_people_get(v_note.worker_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Each person's own expiry reminder
-- ---------------------------------------------------------------------------

-- The daily job. Returns how many reminders it sent.
create or replace function public.v1_people_send_my_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_item record;
  v_last text;
  v_reminder uuid;
  v_notification uuid;
  v_count integer := 0;
begin
  for v_item in
    select
      worker.id as worker_id,
      worker.linked_auth_user_id as recipient,
      count(*) filter (
        where public.v1_people_status(document.expiry_date, v_today) = 'expired'
      )::integer as expired,
      count(*) filter (
        where public.v1_people_status(document.expiry_date, v_today) = 'expiring'
      )::integer as expiring,
      md5(string_agg(
        document.id::text || ':'
          || public.v1_people_status(document.expiry_date, v_today),
        ',' order by document.id
      )) as fingerprint
    from public.v1_workforce_workers worker
    join public.v1_profiles profile
      on profile.auth_user_id = worker.linked_auth_user_id
    join public.v1_people_documents document
      on document.worker_id = worker.id
    where worker.linked_auth_user_id is not null
      and worker.current_status = 'active'
      and profile.is_active
      and document.is_current
      and document.expiry_date <= v_today + 60
    group by worker.id, worker.linked_auth_user_id
  loop
    select reminder.fingerprint into v_last
    from public.v1_people_my_reminders reminder
    where reminder.recipient_auth_user_id = v_item.recipient
    order by reminder.sent_on desc
    limit 1;
    -- Nothing changed since this person's last reminder.
    if v_last is not distinct from v_item.fingerprint then
      continue;
    end if;
    v_reminder := null;
    insert into public.v1_people_my_reminders (
      recipient_auth_user_id, worker_id, sent_on, expired_count,
      expiring_count, fingerprint
    ) values (
      v_item.recipient, v_item.worker_id, v_today, v_item.expired,
      v_item.expiring, v_item.fingerprint
    )
    on conflict (recipient_auth_user_id, sent_on) do nothing
    returning id into v_reminder;
    if v_reminder is null then
      continue;
    end if;
    v_notification := gen_random_uuid();
    insert into public.v1_notifications (
      id, recipient_auth_user_id, event_code, entity_type, entity_id,
      project_id
    ) values (
      v_notification, v_item.recipient,
      case when v_item.expired > 0 then 'people_my_documents_overdue'
        else 'people_my_documents_due' end,
      'people_my_reminder', v_reminder, null
    );
    update public.v1_people_my_reminders
    set notification_id = v_notification
    where id = v_reminder;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Notification link, label and delivery.
-- ---------------------------------------------------------------------------

do $wrap$
begin
  if to_regprocedure(
    'public.v1_notification_module_route_before_my_people(public.v1_notifications)'
  ) is null then
    alter function public.v1_notification_module_route(public.v1_notifications)
      rename to v1_notification_module_route_before_my_people;
    alter function public.v1_notification_record_label(public.v1_notifications)
      rename to v1_notification_record_label_before_my_people;
    alter function public.v1_push_notification_entity_allowed(public.v1_notifications)
      rename to v1_push_notification_entity_allowed_before_my_people;
  end if;
end;
$wrap$;

create or replace function public.v1_people_notification_kind(
  n public.v1_notifications
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when n.event_code in (
      'people_my_documents_overdue', 'people_my_documents_due'
    ) and n.entity_type = 'people_my_reminder' then 'my_documents'
    when n.event_code = 'people_note_received'
      and n.entity_type = 'people_note' then 'note'
  end;
$$;

create or replace function public.v1_notification_module_route(
  n public.v1_notifications
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_worker uuid;
begin
  case public.v1_people_notification_kind(n)
    when 'my_documents' then
      return '/profile';
    when 'note' then
      select note.worker_id into v_worker
      from public.v1_people_notes note
      where note.id = n.entity_id;
      if v_worker is null then
        return '/yorks/people';
      end if;
      return '/yorks/people/' || v_worker::text;
    else
      return public.v1_notification_module_route_before_my_people(n);
  end case;
end;
$$;

create or replace function public.v1_notification_record_label(
  n public.v1_notifications
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_label text;
begin
  case public.v1_people_notification_kind(n)
    when 'my_documents' then
      if auth.uid() is distinct from n.recipient_auth_user_id then
        return null;
      end if;
      select (reminder.expired_count + reminder.expiring_count)::text
      into v_label
      from public.v1_people_my_reminders reminder
      where reminder.id = n.entity_id
        and reminder.recipient_auth_user_id = n.recipient_auth_user_id;
      return v_label;
    when 'note' then
      if auth.uid() is distinct from n.recipient_auth_user_id then
        return null;
      end if;
      select worker.full_name into v_label
      from public.v1_people_notes note
      join public.v1_workforce_workers worker on worker.id = note.worker_id
      where note.id = n.entity_id;
      return v_label;
    else
      return public.v1_notification_record_label_before_my_people(n);
  end case;
end;
$$;

create or replace function public.v1_push_notification_entity_allowed(
  n public.v1_notifications
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.v1_people_notification_kind(n) is not null then
    return true;
  end if;
  return public.v1_push_notification_entity_allowed_before_my_people(n);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants and schedule.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_people_notes_guard()',
    'v1_people_account_json(uuid)',
    'v1_people_may_link()',
    'v1_people_last4(text)',
    'v1_people_mine_json(uuid)',
    'v1_people_send_my_reminders()',
    'v1_people_notification_kind(public.v1_notifications)',
    'v1_notification_module_route(public.v1_notifications)',
    'v1_notification_record_label(public.v1_notifications)',
    'v1_push_notification_entity_allowed(public.v1_notifications)',
    'v1_notification_module_route_before_my_people(public.v1_notifications)',
    'v1_notification_record_label_before_my_people(public.v1_notifications)',
    'v1_push_notification_entity_allowed_before_my_people(public.v1_notifications)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated, service_role',
      v_signature
    );
  end loop;
end;
$grants$;

revoke all on function
  public.v1_people_get(uuid),
  public.v1_people_set_account(uuid, uuid, bigint, uuid),
  public.v1_people_link_suggestions(),
  public.v1_people_get_mine(),
  public.v1_people_send_note(text, uuid),
  public.v1_people_note_done(uuid, uuid)
  from public, anon;
grant execute on function
  public.v1_people_get(uuid),
  public.v1_people_set_account(uuid, uuid, bigint, uuid),
  public.v1_people_link_suggestions(),
  public.v1_people_get_mine(),
  public.v1_people_send_note(text, uuid),
  public.v1_people_note_done(uuid, uuid)
  to authenticated;

-- Daily at 04:20 UTC (08:20 in Dubai), after the HR/PRO summary.
do $schedule$
begin
  perform cron.schedule(
    'yorks-people-my-reminders', '20 4 * * *',
    'select public.v1_people_send_my_reminders();'
  );
end;
$schedule$;

commit;

notify pgrst, 'reload schema';

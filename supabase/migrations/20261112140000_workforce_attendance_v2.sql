-- Workforce attendance V2: crews, day sheets, month confirmation
-- (owner decision, 12 November 2026, PRODUCT_DECISIONS.md section 37).
--
-- Replaces the experience of the T03-T10 per-worker-minute attendance and
-- multi-actor monthly approval chain with the approved prototype model:
--
--   * A crew is a Workforce team with a crew profile (project or workshop,
--     usual shift, whether its month needs confirmation) and current members.
--   * An attendance taker saves a whole crew day at once: every member gets
--     Present (with In / Break / Back / Out), Absent, Rest day or a leave.
--     The server computes hours: a normal day is 8 hours, the rest of a
--     working day is normal overtime, and every hour on a Sunday or public
--     holiday is holiday overtime.
--   * Saved days stay editable until the month is confirmed. Changing a day
--     someone else entered needs a reason, is logged and notifies them.
--   * A confirmer may ask the taker a question about a day.
--   * On the last day of the month a confirmer locks the month once every
--     working day is entered. Only Admin or PR may reopen it, with a reason.
--
-- Access mirrors Material Requests: Site/Project Engineers on the crew's
-- project take attendance, the project's Project Engineer confirms, the
-- organization-wide engineers act on every crew, Admin and PR manage
-- everything and Accountant reads. Each command also requires its Workforce
-- capability, so a per-person deny still works.
--
-- Data preservation: additive only. The T03-T10 tables, rows and functions
-- are untouched (production holds no attendance). No pay field is added.
-- Rollback: revoke execute on the v1_wf_* functions and turn the
-- YORKS_V1_WORKFORCE_ATTENDANCE_V2 flag off; keep every table and row.

begin;

-- ---------------------------------------------------------------------------
-- 0. Capability rule. Attendance V2 access comes from role and project
--    membership, like Material Requests, so no role template changes and the
--    T03-T10 commands keep their per-person grants. Admin and PR hold the
--    Workforce keys by default and are checked through the resolver; for
--    everyone else an explicit per-person deny of the key still removes the
--    right.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_allowed(p_capability_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.v1_current_exact_role() in ('admin', 'pr') then
      public.v1_current_user_has_capability(p_capability_key, null)
    else not exists (
      select 1
      from public.v1_permission_assignments assignment
      where assignment.auth_user_id = auth.uid()
        and assignment.capability_key = p_capability_key
        and assignment.effect = 'deny'
        and assignment.origin = 'permission_management'
        and assignment.scope_kind = 'organization'
        and assignment.effective_from <= clock_timestamp()
        and (assignment.effective_until is null
          or assignment.effective_until > clock_timestamp())
    )
  end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------------

create table public.v1_workforce_public_holidays (
  holiday_date date primary key,
  holiday_name text not null check (
    btrim(holiday_name) <> '' and char_length(holiday_name) <= 120
  ),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.v1_workforce_crew_profiles (
  team_id uuid primary key
    references public.v1_workforce_teams (id) on delete restrict,
  crew_kind text not null check (crew_kind in ('project', 'workshop')),
  project_id uuid references public.v1_projects (id) on delete restrict,
  work_label text check (
    work_label is null
    or (btrim(work_label) <> '' and char_length(work_label) <= 160)
  ),
  needs_confirmation boolean not null default true,
  shift_start_minute integer not null check (
    shift_start_minute between 0 and 1439
  ),
  shift_finish_minute integer not null check (
    shift_finish_minute between 1 and 1439
  ),
  break_start_minute integer check (break_start_minute between 0 and 1439),
  break_finish_minute integer check (break_finish_minute between 1 and 1439),
  is_active boolean not null default true,
  record_version bigint not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (shift_finish_minute > shift_start_minute),
  check ((break_start_minute is null) = (break_finish_minute is null)),
  check (
    break_start_minute is null or break_finish_minute > break_start_minute
  ),
  check ((crew_kind = 'project') = (project_id is not null))
);
create index v1_workforce_crew_profiles_project_idx
  on public.v1_workforce_crew_profiles (project_id, is_active);

create table public.v1_workforce_crew_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  added_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  added_at timestamptz not null default clock_timestamp(),
  removed_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  removed_at timestamptz,
  check ((removed_at is null) = (removed_by_auth_user_id is null))
);
-- A worker belongs to one crew at a time.
create unique index v1_workforce_crew_members_current_uidx
  on public.v1_workforce_crew_members (worker_id)
  where removed_at is null;
create index v1_workforce_crew_members_team_idx
  on public.v1_workforce_crew_members (team_id)
  where removed_at is null;

create table public.v1_workforce_day_sheets (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  work_date date not null,
  entered_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  entered_at timestamptz not null,
  entered_late boolean not null default false,
  last_saved_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  last_saved_at timestamptz not null,
  record_version bigint not null default 1 check (record_version > 0),
  unique (team_id, work_date)
);
create index v1_workforce_day_sheets_month_idx
  on public.v1_workforce_day_sheets (team_id, work_date desc);

create table public.v1_workforce_day_rows (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null
    references public.v1_workforce_day_sheets (id) on delete restrict,
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  work_date date not null,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  attendance_status text not null check (attendance_status in (
    'P', 'A', 'OFF', 'AL', 'SL', 'OL', 'UL'
  )),
  start_minute integer check (start_minute between 0 and 1439),
  break_start_minute integer check (break_start_minute between 0 and 1439),
  break_finish_minute integer check (break_finish_minute between 0 and 1439),
  finish_minute integer check (finish_minute between 0 and 1439),
  work_project_id uuid references public.v1_projects (id) on delete restrict,
  work_label text check (
    work_label is null
    or (btrim(work_label) <> '' and char_length(work_label) <= 160)
  ),
  overtime_note text check (
    overtime_note is null
    or (btrim(overtime_note) <> '' and char_length(overtime_note) <= 300)
  ),
  copied boolean not null default false,
  changed_after_entry boolean not null default false,
  worked_minutes integer not null default 0 check (worked_minutes >= 0),
  regular_minutes integer not null default 0 check (regular_minutes >= 0),
  normal_overtime_minutes integer not null default 0
    check (normal_overtime_minutes >= 0),
  holiday_overtime_minutes integer not null default 0
    check (holiday_overtime_minutes >= 0),
  updated_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  unique (sheet_id, worker_id),
  -- A worker is recorded on one crew sheet per day.
  unique (worker_id, work_date),
  check (
    attendance_status <> 'P'
    or (start_minute is not null and finish_minute is not null
      and finish_minute > start_minute)
  ),
  check (
    attendance_status = 'P'
    or (start_minute is null and finish_minute is null
      and break_start_minute is null and break_finish_minute is null)
  ),
  check ((break_start_minute is null) = (break_finish_minute is null)),
  check (
    break_start_minute is null or break_finish_minute > break_start_minute
  )
);
create index v1_workforce_day_rows_team_month_idx
  on public.v1_workforce_day_rows (team_id, work_date);

create table public.v1_workforce_day_changes (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null
    references public.v1_workforce_day_sheets (id) on delete restrict,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  before_data jsonb,
  after_data jsonb,
  reason text not null check (
    btrim(reason) <> '' and char_length(reason) <= 500
  ),
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_exact_role text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
create index v1_workforce_day_changes_sheet_idx
  on public.v1_workforce_day_changes (sheet_id, occurred_at);

create table public.v1_workforce_day_questions (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null
    references public.v1_workforce_day_sheets (id) on delete restrict,
  question text not null check (
    btrim(question) <> '' and char_length(question) <= 500
  ),
  asked_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  asked_at timestamptz not null default clock_timestamp(),
  answer text check (
    answer is null or (btrim(answer) <> '' and char_length(answer) <= 500)
  ),
  answered_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  answered_at timestamptz,
  check ((answer is null) = (answered_at is null)),
  check ((answer is null) = (answered_by_auth_user_id is null))
);
-- One open question per day.
create unique index v1_workforce_day_questions_open_uidx
  on public.v1_workforce_day_questions (sheet_id)
  where answer is null;

create table public.v1_workforce_month_confirmations (
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  period_month date not null check (
    period_month = date_trunc('month', period_month)::date
  ),
  is_confirmed boolean not null,
  confirmed_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  confirmed_at timestamptz,
  reopened_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  reopened_at timestamptz,
  reopen_reason text check (
    reopen_reason is null
    or (btrim(reopen_reason) <> '' and char_length(reopen_reason) <= 500)
  ),
  record_version bigint not null default 1 check (record_version > 0),
  primary key (team_id, period_month),
  check (not is_confirmed or confirmed_at is not null)
);

-- Append-only activity: "What's happening" and the protected history.
create table public.v1_workforce_attendance_events (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  work_date date,
  period_month date,
  event_kind text not null check (event_kind in (
    'entered', 'changed', 'asked', 'answered', 'confirmed', 'reopened'
  )),
  summary jsonb not null default '{}'::jsonb,
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_exact_role text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
create index v1_workforce_attendance_events_team_idx
  on public.v1_workforce_attendance_events (team_id, occurred_at desc);

create or replace function public.v1_wf_block_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'V1_WORKFORCE_HISTORY_APPEND_ONLY' using errcode = '42501';
end;
$$;
create trigger v1_workforce_day_changes_append_only
before update or delete on public.v1_workforce_day_changes
for each row execute function public.v1_wf_block_history_mutation();
create trigger v1_workforce_attendance_events_append_only
before update or delete on public.v1_workforce_attendance_events
for each row execute function public.v1_wf_block_history_mutation();

-- Retained rows are never hard-deleted. Day rows (a worker added for one
-- day and then taken off, logged in v1_workforce_day_changes) and public
-- holidays (a calendar setting) are the two deliberate exceptions.
do $no_delete$
declare
  v_table text;
begin
  foreach v_table in array array[
    'v1_workforce_crew_profiles', 'v1_workforce_crew_members',
    'v1_workforce_day_sheets', 'v1_workforce_day_changes',
    'v1_workforce_day_questions', 'v1_workforce_month_confirmations',
    'v1_workforce_attendance_events'
  ] loop
    execute format(
      'create trigger %I before delete on public.%I '
      'for each row execute function public.v1_workforce_block_delete()',
      v_table || '_no_delete', v_table
    );
  end loop;
end;
$no_delete$;

-- All access is through the functions below.
do $lock_tables$
declare
  v_table text;
begin
  foreach v_table in array array[
    'v1_workforce_public_holidays', 'v1_workforce_crew_profiles',
    'v1_workforce_crew_members', 'v1_workforce_day_sheets',
    'v1_workforce_day_rows', 'v1_workforce_day_changes',
    'v1_workforce_day_questions', 'v1_workforce_month_confirmations',
    'v1_workforce_attendance_events'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'revoke all on table public.%I from public, anon, authenticated',
      v_table
    );
  end loop;
end;
$lock_tables$;

-- ---------------------------------------------------------------------------
-- 2. Calendar and hours.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (clock_timestamp() at time zone 'Asia/Dubai')::date;
$$;

-- 'work', or 'holiday' for a Sunday or a public holiday.
create or replace function public.v1_wf_day_type(p_date date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when extract(isodow from p_date) = 7 then 'holiday'
    when exists (
      select 1 from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date = p_date
    ) then 'holiday'
    else 'work'
  end;
$$;

-- Hours from the paper DAILY TIME SHEET. Returns worked, regular, normal
-- overtime and holiday overtime minutes.
create or replace function public.v1_wf_compute_minutes(
  p_status text,
  p_start integer,
  p_break_start integer,
  p_break_finish integer,
  p_finish integer,
  p_day_type text
)
returns integer[]
language sql
immutable
set search_path = ''
as $$
  with worked as (
    select case
      when p_status <> 'P' or p_start is null or p_finish is null
        or p_finish <= p_start then 0
      else greatest(
        0,
        p_finish - p_start - case
          when p_break_start is not null and p_break_finish is not null
            and p_break_finish > p_break_start
          then p_break_finish - p_break_start else 0 end
      )
    end as minutes
  )
  select case
    when p_day_type = 'holiday' then array[minutes, 0, 0, minutes]
    else array[minutes, least(minutes, 480), greatest(minutes - 480, 0), 0]
  end
  from worked;
$$;

-- ---------------------------------------------------------------------------
-- 3. Access.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_role_is_global(p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_role in (
    'senior_mechanical_engineer', 'project_manager',
    'workshop_in_charge', 'document_controller'
  );
$$;

-- {view, take, confirm, manage, officer} for the signed-in person on one
-- crew. Capabilities are checked on top of role and project membership.
create or replace function public.v1_wf_crew_access(p_team_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_member boolean := false;
  v_pe_member boolean := false;
  v_officer boolean;
  v_global boolean;
  v_view boolean;
  v_take boolean;
  v_confirm boolean;
  v_manage boolean;
begin
  if v_actor is null or v_role = ''
    or not public.v1_current_actor_is_active() then
    return jsonb_build_object(
      'view', false, 'take', false, 'confirm', false, 'manage', false,
      'officer', false
    );
  end if;
  select * into v_profile
  from public.v1_workforce_crew_profiles profile
  where profile.team_id = p_team_id;
  if not found then
    return jsonb_build_object(
      'view', false, 'take', false, 'confirm', false, 'manage', false,
      'officer', false
    );
  end if;

  v_officer := v_role in ('admin', 'pr');
  v_global := public.v1_wf_role_is_global(v_role);
  if v_profile.project_id is not null then
    select
      coalesce(bool_or(true), false),
      coalesce(bool_or(member.project_role = 'project_engineer'), false)
    into v_member, v_pe_member
    from public.v1_project_members member
    where member.project_id = v_profile.project_id
      and member.member_auth_user_id = v_actor
      and member.effective_from <= clock_timestamp()
      and (member.effective_to is null
        or member.effective_to > clock_timestamp());
  end if;

  v_view := (
      v_officer or v_global or v_role = 'accountant'
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
    )
    and public.v1_wf_allowed('workforce.view');
  v_take := v_view
    and (
      v_officer or v_global
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
    )
    and public.v1_wf_allowed('workforce.attendance.maintain');
  v_confirm := v_view
    and v_profile.needs_confirmation
    and (
      v_role = 'admin' or v_global
      or (v_role = 'project_engineer' and v_pe_member)
    )
    and public.v1_wf_allowed('workforce.timesheets.final_approve');
  v_manage := v_view
    and (
      v_officer or v_global
      or (v_role = 'project_engineer' and v_pe_member)
    )
    and public.v1_wf_allowed('workforce.teams.manage');

  return jsonb_build_object(
    'view', v_view,
    'take', v_take,
    'confirm', v_confirm,
    'manage', v_manage,
    'officer', v_officer and v_view
  );
end;
$$;

create or replace function public.v1_wf_assert_crew(
  p_team_id uuid,
  p_right text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_team_id is null
    or not coalesce(
      (public.v1_wf_crew_access(p_team_id) ->> p_right)::boolean, false
    ) then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

create or replace function public.v1_wf_month_locked(
  p_team_id uuid,
  p_date date
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select confirmation.is_confirmed
    from public.v1_workforce_month_confirmations confirmation
    where confirmation.team_id = p_team_id
      and confirmation.period_month = date_trunc('month', p_date)::date
  ), false);
$$;

create or replace function public.v1_wf_display_name(p_auth_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select nullif(btrim(profile.display_name), '')
     from public.v1_profiles profile
     where profile.auth_user_id = p_auth_user_id),
    ''
  );
$$;

create or replace function public.v1_wf_notify(
  p_recipient uuid,
  p_event_code text,
  p_entity_type text,
  p_entity_id uuid,
  p_project_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_recipient = auth.uid() then
    return;
  end if;
  insert into public.v1_notifications (
    id, recipient_auth_user_id, event_code, entity_type, entity_id,
    project_id
  ) values (
    gen_random_uuid(), p_recipient,
    case p_event_code
      when 'workforce_attendance_day_changed'
        then 'workforce_attendance_day_changed'
      when 'workforce_attendance_question'
        then 'workforce_attendance_question'
      when 'workforce_attendance_answered'
        then 'workforce_attendance_answered'
    end,
    p_entity_type, p_entity_id, p_project_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Projections.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_crew_json(p_team_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', team.id,
    'name', team.team_name,
    'code', team.team_code,
    'kind', profile.crew_kind,
    'project_id', profile.project_id,
    'project_ref', project.project_ref,
    'project_name', project.name,
    'work_label', coalesce(
      profile.work_label,
      case when project.id is not null
        then project.name || ' · ' || project.project_ref end,
      team.team_name
    ),
    'needs_confirmation', profile.needs_confirmation,
    'shift_start_minute', profile.shift_start_minute,
    'shift_finish_minute', profile.shift_finish_minute,
    'break_start_minute', profile.break_start_minute,
    'break_finish_minute', profile.break_finish_minute,
    'is_active', profile.is_active and team.is_active,
    'record_version', profile.record_version,
    'member_count', (
      select count(*) from public.v1_workforce_crew_members member
      where member.team_id = team.id and member.removed_at is null
    ),
    'access', public.v1_wf_crew_access(team.id)
  )
  from public.v1_workforce_teams team
  join public.v1_workforce_crew_profiles profile on profile.team_id = team.id
  left join public.v1_projects project on project.id = profile.project_id
  where team.id = p_team_id;
$$;

create or replace function public.v1_wf_worker_json(p_worker_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', worker.id,
    'number', worker.worker_number,
    'name', worker.full_name,
    'designation', worker.designation,
    'company', worker.employer_company,
    'status', worker.current_status,
    'crew_id', member.team_id,
    'crew_name', team.team_name
  )
  from public.v1_workforce_workers worker
  left join public.v1_workforce_crew_members member
    on member.worker_id = worker.id and member.removed_at is null
  left join public.v1_workforce_teams team on team.id = member.team_id
  where worker.id = p_worker_id;
$$;

create or replace function public.v1_wf_row_json(
  p_row public.v1_workforce_day_rows
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'worker_id', p_row.worker_id,
    'status', p_row.attendance_status,
    'start_minute', p_row.start_minute,
    'break_start_minute', p_row.break_start_minute,
    'break_finish_minute', p_row.break_finish_minute,
    'finish_minute', p_row.finish_minute,
    'work_project_id', p_row.work_project_id,
    'work_label', p_row.work_label,
    'overtime_note', p_row.overtime_note,
    'copied', p_row.copied,
    'changed_after_entry', p_row.changed_after_entry,
    'worked_minutes', p_row.worked_minutes,
    'regular_minutes', p_row.regular_minutes,
    'normal_overtime_minutes', p_row.normal_overtime_minutes,
    'holiday_overtime_minutes', p_row.holiday_overtime_minutes
  );
$$;

-- Status of one crew day: future, locked, question, entered, none, off.
create or replace function public.v1_wf_day_state(
  p_team_id uuid,
  p_date date
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_date > public.v1_wf_today() then 'future'
    when public.v1_wf_month_locked(p_team_id, p_date) then 'locked'
    when exists (
      select 1 from public.v1_workforce_day_sheets sheet
      join public.v1_workforce_day_questions question
        on question.sheet_id = sheet.id and question.answer is null
      where sheet.team_id = p_team_id and sheet.work_date = p_date
    ) then 'question'
    when exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where sheet.team_id = p_team_id and sheet.work_date = p_date
    ) then 'entered'
    when public.v1_wf_day_type(p_date) = 'work' then 'none'
    else 'off'
  end;
$$;

create or replace function public.v1_wf_month_json(
  p_team_id uuid,
  p_month date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', p_month)::date;
  v_last date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_today date := public.v1_wf_today();
  v_confirmation public.v1_workforce_month_confirmations%rowtype;
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_days jsonb;
  v_missing jsonb;
  v_totals record;
  v_work_days integer;
  v_entered integer;
begin
  select * into v_profile
  from public.v1_workforce_crew_profiles profile
  where profile.team_id = p_team_id;
  select * into v_confirmation
  from public.v1_workforce_month_confirmations confirmation
  where confirmation.team_id = p_team_id
    and confirmation.period_month = v_month;

  select
    jsonb_agg(jsonb_build_object(
      'date', day_value,
      'state', public.v1_wf_day_state(p_team_id, day_value),
      'day_type', public.v1_wf_day_type(day_value)
    ) order by day_value)
  into v_days
  from generate_series(v_month, v_last, interval '1 day') series(day_ts)
  cross join lateral (select series.day_ts::date as day_value) day_row;

  select coalesce(jsonb_agg(day_value order by day_value), '[]'::jsonb)
  into v_missing
  from generate_series(v_month, least(v_last, v_today), interval '1 day')
    series(day_ts)
  cross join lateral (select series.day_ts::date as day_value) day_row
  where public.v1_wf_day_type(day_value) = 'work'
    and not exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where sheet.team_id = p_team_id and sheet.work_date = day_value
    );

  select count(*) into v_work_days
  from generate_series(v_month, least(v_last, v_today), interval '1 day')
    series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work';

  select count(*) into v_entered
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date between v_month and v_last;

  select
    coalesce(sum(day_row.regular_minutes), 0) as regular,
    coalesce(sum(day_row.normal_overtime_minutes), 0) as normal_ot,
    coalesce(sum(day_row.holiday_overtime_minutes), 0) as holiday_ot
  into v_totals
  from public.v1_workforce_day_rows day_row
  where day_row.team_id = p_team_id
    and day_row.work_date between v_month and v_last;

  return jsonb_build_object(
    'month', v_month,
    'last_day', v_last,
    'state', case
      when not coalesce(v_profile.needs_confirmation, true)
        then 'not_needed'
      when coalesce(v_confirmation.is_confirmed, false) then 'confirmed'
      when v_today >= v_last then 'ready'
      else 'recording'
    end,
    'confirmed_by', public.v1_wf_display_name(
      v_confirmation.confirmed_by_auth_user_id
    ),
    'confirmed_at', v_confirmation.confirmed_at,
    'reopened_by', public.v1_wf_display_name(
      v_confirmation.reopened_by_auth_user_id
    ),
    'reopened_at', v_confirmation.reopened_at,
    'reopen_reason', v_confirmation.reopen_reason,
    'record_version', coalesce(v_confirmation.record_version, 0),
    'days', coalesce(v_days, '[]'::jsonb),
    'missing_days', v_missing,
    'work_days_so_far', v_work_days,
    'days_entered', v_entered,
    'regular_minutes', v_totals.regular,
    'normal_overtime_minutes', v_totals.normal_ot,
    'holiday_overtime_minutes', v_totals.holiday_ot,
    'can_confirm', coalesce(
      (public.v1_wf_crew_access(p_team_id) ->> 'confirm')::boolean, false
    )
      and not coalesce(v_confirmation.is_confirmed, false)
      and v_today >= v_last
      and jsonb_array_length(v_missing) = 0
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Read commands.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_list_crews()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.crews.v2',
    'today', public.v1_wf_today(),
    'can_create_crew', public.v1_current_exact_role() in ('admin', 'pr')
      or public.v1_wf_role_is_global(public.v1_current_exact_role())
      or public.v1_current_exact_role() = 'project_engineer',
    'crews', coalesce((
      select jsonb_agg(public.v1_wf_crew_json(team.id)
        order by lower(team.team_name))
      from public.v1_workforce_teams team
      join public.v1_workforce_crew_profiles profile
        on profile.team_id = team.id
      where profile.is_active
        and (public.v1_wf_crew_access(team.id) ->> 'view')::boolean
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.v1_wf_get_overview(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', coalesce(p_month, public.v1_wf_today()))::date;
  v_crews jsonb;
  v_feed jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    public.v1_wf_crew_json(team.id)
      || jsonb_build_object(
        'month', public.v1_wf_month_json(team.id, v_month)
      )
    order by lower(team.team_name)
  ), '[]'::jsonb)
  into v_crews
  from public.v1_workforce_teams team
  join public.v1_workforce_crew_profiles profile on profile.team_id = team.id
  where profile.is_active
    and (public.v1_wf_crew_access(team.id) ->> 'view')::boolean;

  select coalesce(jsonb_agg(item order by occurred_at desc), '[]'::jsonb)
  into v_feed
  from (
    select
      event.occurred_at,
      jsonb_build_object(
        'id', event.id,
        'kind', event.event_kind,
        'crew_id', event.team_id,
        'crew_name', team.team_name,
        'date', event.work_date,
        'month', event.period_month,
        'summary', event.summary,
        'by', public.v1_wf_display_name(event.actor_auth_user_id),
        'at', event.occurred_at
      ) as item
    from public.v1_workforce_attendance_events event
    join public.v1_workforce_teams team on team.id = event.team_id
    where (public.v1_wf_crew_access(event.team_id) ->> 'view')::boolean
    order by event.occurred_at desc
    limit 12
  ) recent;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.overview.v2',
    'today', public.v1_wf_today(),
    'month', v_month,
    'crews', v_crews,
    'feed', v_feed
  );
end;
$$;

create or replace function public.v1_wf_get_day(
  p_team_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb;
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_has_sheet boolean;
  v_rows jsonb;
  v_previous date;
  v_question jsonb;
  v_changes jsonb;
  v_day_type text;
begin
  perform public.v1_wf_assert_crew(p_team_id, 'view');
  if p_work_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_access := public.v1_wf_crew_access(p_team_id);
  v_day_type := public.v1_wf_day_type(p_work_date);

  select * into v_sheet
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id and sheet.work_date = p_work_date;
  v_has_sheet := found;

  -- Saved rows first; then current members who have no row yet (a new day).
  select coalesce(jsonb_agg(entry order by entry ->> 'sort_name'), '[]'::jsonb)
  into v_rows
  from (
    select public.v1_wf_row_json(day_row)
      || jsonb_build_object(
        'worker', public.v1_wf_worker_json(day_row.worker_id),
        'is_member', exists (
          select 1 from public.v1_workforce_crew_members member
          where member.team_id = p_team_id
            and member.worker_id = day_row.worker_id
            and member.removed_at is null
        ),
        'sort_name', lower(worker.full_name)
      ) as entry
    from public.v1_workforce_day_rows day_row
    join public.v1_workforce_workers worker on worker.id = day_row.worker_id
    where day_row.sheet_id = v_sheet.id
    union all
    select jsonb_build_object(
      'worker_id', member.worker_id,
      'status', null,
      'worker', public.v1_wf_worker_json(member.worker_id),
      'is_member', true,
      'sort_name', lower(worker.full_name)
    )
    from public.v1_workforce_crew_members member
    join public.v1_workforce_workers worker on worker.id = member.worker_id
    where member.team_id = p_team_id
      and member.removed_at is null
      and worker.current_status = 'active'
      and not exists (
        select 1 from public.v1_workforce_day_rows day_row
        where day_row.sheet_id = v_sheet.id
          and day_row.worker_id = member.worker_id
      )
      -- A worker already recorded on another crew that day is not offered.
      and not exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = member.worker_id
          and other_row.work_date = p_work_date
      )
  ) rows_source;

  select max(sheet.work_date) into v_previous
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date < p_work_date
    and public.v1_wf_day_type(sheet.work_date) = v_day_type;

  select jsonb_build_object(
    'id', question.id,
    'question', question.question,
    'asked_by', public.v1_wf_display_name(question.asked_by_auth_user_id),
    'asked_at', question.asked_at,
    'answer', question.answer,
    'answered_by', public.v1_wf_display_name(question.answered_by_auth_user_id),
    'answered_at', question.answered_at,
    'is_open', question.answer is null
  )
  into v_question
  from public.v1_workforce_day_questions question
  where question.sheet_id = v_sheet.id
  order by question.asked_at desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id', change.worker_id,
    'worker_name', worker.full_name,
    'before', change.before_data,
    'after', change.after_data,
    'reason', change.reason,
    'by', public.v1_wf_display_name(change.actor_auth_user_id),
    'at', change.occurred_at
  ) order by change.occurred_at), '[]'::jsonb)
  into v_changes
  from public.v1_workforce_day_changes change
  join public.v1_workforce_workers worker on worker.id = change.worker_id
  where change.sheet_id = v_sheet.id;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.day.v2',
    'crew', public.v1_wf_crew_json(p_team_id),
    'date', p_work_date,
    'today', public.v1_wf_today(),
    'day_type', v_day_type,
    'holiday_name', (
      select holiday.holiday_name
      from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date = p_work_date
    ),
    'saved', v_has_sheet,
    'record_version', case when v_has_sheet then v_sheet.record_version else 0 end,
    'entered_by', case when v_has_sheet
      then public.v1_wf_display_name(v_sheet.entered_by_auth_user_id) end,
    'entered_by_me', v_has_sheet
      and v_sheet.entered_by_auth_user_id = auth.uid(),
    'entered_at', v_sheet.entered_at,
    'entered_late', coalesce(v_sheet.entered_late, false),
    'last_saved_by', case when v_has_sheet
      then public.v1_wf_display_name(v_sheet.last_saved_by_auth_user_id) end,
    'last_saved_at', v_sheet.last_saved_at,
    'locked', public.v1_wf_month_locked(p_team_id, p_work_date),
    'is_future', p_work_date > public.v1_wf_today(),
    'previous_same_type_date', v_previous,
    'rows', v_rows,
    'question', v_question,
    'changes', v_changes,
    'access', v_access,
    'month', public.v1_wf_month_json(p_team_id, p_work_date)
  );
end;
$$;

-- The paper DAILY TIME SHEET for a crew's month: every worker recorded on
-- the crew that month, or a current member, with their days.
create or replace function public.v1_wf_get_month_sheet(
  p_team_id uuid,
  p_month date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', p_month)::date;
  v_last date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_workers jsonb;
  v_takers jsonb;
begin
  perform public.v1_wf_assert_crew(p_team_id, 'view');
  if p_month is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    public.v1_wf_worker_json(worker_ids.worker_id)
      || jsonb_build_object('days', coalesce((
        select jsonb_agg(
          public.v1_wf_row_json(day_row)
            || jsonb_build_object('date', day_row.work_date)
          order by day_row.work_date
        )
        from public.v1_workforce_day_rows day_row
        where day_row.team_id = p_team_id
          and day_row.worker_id = worker_ids.worker_id
          and day_row.work_date between v_month and v_last
      ), '[]'::jsonb))
    order by lower(worker.full_name)
  ), '[]'::jsonb)
  into v_workers
  from (
    select distinct day_row.worker_id
    from public.v1_workforce_day_rows day_row
    where day_row.team_id = p_team_id
      and day_row.work_date between v_month and v_last
    union
    select member.worker_id
    from public.v1_workforce_crew_members member
    where member.team_id = p_team_id and member.removed_at is null
  ) worker_ids
  join public.v1_workforce_workers worker on worker.id = worker_ids.worker_id;

  -- Who entered each date, for the weekly site in-charge line.
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', sheet.work_date,
    'entered_by', public.v1_wf_display_name(sheet.entered_by_auth_user_id),
    'changed', exists (
      select 1 from public.v1_workforce_day_changes change
      where change.sheet_id = sheet.id
    )
  ) order by sheet.work_date), '[]'::jsonb)
  into v_takers
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date between v_month and v_last;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.month_sheet.v2',
    'crew', public.v1_wf_crew_json(p_team_id),
    'month', public.v1_wf_month_json(p_team_id, v_month),
    'workers', v_workers,
    'sheets', v_takers,
    'holidays', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', holiday.holiday_date, 'name', holiday.holiday_name
      ) order by holiday.holiday_date)
      from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date between v_month and v_last
    ), '[]'::jsonb),
    'can_export', public.v1_wf_allowed('workforce.reports.export')
  );
end;
$$;

-- One crew with its current members, for crew setup.
create or replace function public.v1_wf_get_crew(p_team_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.v1_wf_assert_crew(p_team_id, 'view');
  return public.v1_wf_crew_json(p_team_id) || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(public.v1_wf_worker_json(member.worker_id)
        order by lower(worker.full_name))
      from public.v1_workforce_crew_members member
      join public.v1_workforce_workers worker on worker.id = member.worker_id
      where member.team_id = p_team_id and member.removed_at is null
    ), '[]'::jsonb)
  );
end;
$$;

-- Active workers a taker may add to a crew or a day.
create or replace function public.v1_wf_list_workers()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Only people who take attendance or manage crews see the worker list.
  if auth.uid() is null
    or not public.v1_current_actor_is_active()
    or not (
      public.v1_current_exact_role() in (
        'admin', 'pr', 'project_engineer', 'site_engineer'
      )
      or public.v1_wf_role_is_global(public.v1_current_exact_role())
    )
    or not public.v1_wf_allowed('workforce.attendance.maintain') then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.workers.v2',
    'workers', coalesce((
      select jsonb_agg(public.v1_wf_worker_json(worker.id)
        order by lower(worker.full_name))
      from public.v1_workforce_workers worker
      where worker.current_status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.v1_wf_list_public_holidays(p_year integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'year', p_year,
    'can_manage', public.v1_current_exact_role() in ('admin', 'pr')
      and public.v1_wf_allowed('workforce.configuration.manage'),
    'holidays', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', holiday.holiday_date, 'name', holiday.holiday_name
      ) order by holiday.holiday_date)
      from public.v1_workforce_public_holidays holiday
      where extract(year from holiday.holiday_date) = p_year
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Crew setup.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_save_crew(
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
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_team_id uuid;
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_name text := btrim(coalesce(p_payload ->> 'name', ''));
  v_kind text := coalesce(p_payload ->> 'kind', 'project');
  v_project uuid;
  v_label text := nullif(btrim(coalesce(p_payload ->> 'work_label', '')), '');
  v_needs boolean;
  v_start integer;
  v_finish integer;
  v_break_start integer;
  v_break_finish integer;
  v_active boolean := coalesce((p_payload ->> 'is_active')::boolean, true);
  v_pe_member boolean := false;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'crew_id', 'name', 'kind', 'project_id', 'work_label',
      'needs_confirmation', 'shift_start_minute', 'shift_finish_minute',
      'break_start_minute', 'break_finish_minute', 'is_active'
    ],
    'save_workforce_crew_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_save_crew', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_wf_crew_json((v_existing ->> 'crew_id')::uuid);
  end if;

  begin
    v_team_id := nullif(p_payload ->> 'crew_id', '')::uuid;
    v_project := nullif(p_payload ->> 'project_id', '')::uuid;
    v_start := (p_payload ->> 'shift_start_minute')::integer;
    v_finish := (p_payload ->> 'shift_finish_minute')::integer;
    v_break_start := (p_payload ->> 'break_start_minute')::integer;
    v_break_finish := (p_payload ->> 'break_finish_minute')::integer;
  exception when others then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end;
  if v_name = '' or char_length(v_name) > 160
    or v_kind not in ('project', 'workshop')
    or (v_kind = 'project') <> (v_project is not null)
    or v_start is null or v_finish is null or v_finish <= v_start
    or (v_break_start is null) <> (v_break_finish is null)
    or (v_break_start is not null and v_break_finish <= v_break_start) then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end if;
  v_needs := coalesce(
    (p_payload ->> 'needs_confirmation')::boolean, v_kind = 'project'
  );

  if v_project is not null then
    if not exists (select 1 from public.v1_projects project where project.id = v_project) then
      raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
    end if;
    select exists (
      select 1 from public.v1_project_members member
      where member.project_id = v_project
        and member.member_auth_user_id = v_actor
        and member.project_role = 'project_engineer'
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
    ) into v_pe_member;
  end if;
  if not public.v1_wf_allowed('workforce.teams.manage')
    or not (
      v_role in ('admin', 'pr')
      or public.v1_wf_role_is_global(v_role)
      or (v_role = 'project_engineer' and v_pe_member)
    ) then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;

  if v_team_id is null then
    insert into public.v1_workforce_teams (
      team_code, team_name, default_project_id, valid_from,
      created_by_auth_user_id, updated_by_auth_user_id
    ) values (
      'CREW-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      v_name, v_project, public.v1_wf_today(), v_actor, v_actor
    )
    returning id into v_team_id;
    insert into public.v1_workforce_crew_profiles (
      team_id, crew_kind, project_id, work_label, needs_confirmation,
      shift_start_minute, shift_finish_minute, break_start_minute,
      break_finish_minute, is_active, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_team_id, v_kind, v_project, v_label, v_needs, v_start, v_finish,
      v_break_start, v_break_finish, v_active, v_actor, v_actor
    );
  else
    perform public.v1_wf_assert_crew(v_team_id, 'manage');
    select * into v_profile
    from public.v1_workforce_crew_profiles profile
    where profile.team_id = v_team_id
    for update;
    if coalesce(p_expected_version, -1) <> v_profile.record_version then
      perform public.v1_raise_version_conflict(
        'V1_WORKFORCE_CREW_VERSION_CONFLICT'
      );
    end if;
    update public.v1_workforce_teams
    set team_name = v_name,
        default_project_id = v_project,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where id = v_team_id;
    update public.v1_workforce_crew_profiles
    set crew_kind = v_kind,
        project_id = v_project,
        work_label = v_label,
        needs_confirmation = v_needs,
        shift_start_minute = v_start,
        shift_finish_minute = v_finish,
        break_start_minute = v_break_start,
        break_finish_minute = v_break_finish,
        is_active = v_active,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where team_id = v_team_id;
  end if;

  perform public.v1_write_audit_event(
    'workforce_crew_saved', 'workforce_crew', v_team_id, v_project, null,
    jsonb_build_object('name', v_name, 'kind', v_kind), null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_save_crew', p_idempotency_key,
    jsonb_build_object('crew_id', v_team_id)
  );
  return public.v1_wf_crew_json(v_team_id);
exception
  when unique_violation then
    raise exception 'V1_WORKFORCE_CREW_NAME_TAKEN' using errcode = '23505';
end;
$$;

-- Add or remove crew members. Moving a worker from another crew needs the
-- same right on that crew.
create or replace function public.v1_wf_set_crew_members(
  p_team_id uuid,
  p_add_worker_ids uuid[],
  p_remove_worker_ids uuid[],
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'take');
  v_existing jsonb;
  v_worker uuid;
  v_current_team uuid;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_set_crew_members', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'add', p_add_worker_ids,
      'remove', p_remove_worker_ids
    )
  );
  if v_existing is not null then
    return public.v1_wf_crew_json(p_team_id);
  end if;
  if coalesce(cardinality(p_add_worker_ids), 0)
    + coalesce(cardinality(p_remove_worker_ids), 0) > 500 then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end if;

  foreach v_worker in array coalesce(p_remove_worker_ids, array[]::uuid[]) loop
    update public.v1_workforce_crew_members
    set removed_at = clock_timestamp(),
        removed_by_auth_user_id = v_actor
    where team_id = p_team_id
      and worker_id = v_worker
      and removed_at is null;
  end loop;

  foreach v_worker in array coalesce(p_add_worker_ids, array[]::uuid[]) loop
    if not exists (
      select 1 from public.v1_workforce_workers worker
      where worker.id = v_worker and worker.current_status = 'active'
    ) then
      raise exception 'V1_WORKFORCE_WORKER_NOT_ACTIVE' using errcode = '22023';
    end if;
    select member.team_id into v_current_team
    from public.v1_workforce_crew_members member
    where member.worker_id = v_worker and member.removed_at is null
    for update;
    if found and v_current_team = p_team_id then
      continue;
    end if;
    if found then
      perform public.v1_wf_assert_crew(v_current_team, 'take');
      update public.v1_workforce_crew_members
      set removed_at = clock_timestamp(),
          removed_by_auth_user_id = v_actor
      where worker_id = v_worker and removed_at is null;
    end if;
    insert into public.v1_workforce_crew_members (
      team_id, worker_id, added_by_auth_user_id
    ) values (p_team_id, v_worker, v_actor);
  end loop;

  perform public.v1_write_audit_event(
    'workforce_crew_members_changed', 'workforce_crew', p_team_id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id),
    null,
    jsonb_build_object(
      'added', coalesce(cardinality(p_add_worker_ids), 0),
      'removed', coalesce(cardinality(p_remove_worker_ids), 0)
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_set_crew_members', p_idempotency_key,
    jsonb_build_object('crew_id', p_team_id)
  );
  return public.v1_wf_crew_json(p_team_id);
end;
$$;

create or replace function public.v1_wf_save_public_holiday(
  p_holiday_date date,
  p_holiday_name text,
  p_remove boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not public.v1_current_actor_is_active()
    or public.v1_current_exact_role() not in ('admin', 'pr')
    or not public.v1_wf_allowed('workforce.configuration.manage') then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_holiday_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  -- A holiday inside a confirmed month would change locked hours.
  if exists (
    select 1 from public.v1_workforce_month_confirmations confirmation
    where confirmation.period_month = date_trunc('month', p_holiday_date)::date
      and confirmation.is_confirmed
  ) then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  if coalesce(p_remove, false) then
    delete from public.v1_workforce_public_holidays
    where holiday_date = p_holiday_date;
  else
    if btrim(coalesce(p_holiday_name, '')) = '' then
      raise exception 'V1_WORKFORCE_HOLIDAY_INVALID' using errcode = '22023';
    end if;
    insert into public.v1_workforce_public_holidays (
      holiday_date, holiday_name, created_by_auth_user_id
    ) values (p_holiday_date, btrim(p_holiday_name), auth.uid())
    on conflict (holiday_date) do update
    set holiday_name = excluded.holiday_name;
  end if;
  perform public.v1_write_audit_event(
    'workforce_public_holiday_saved', 'workforce_public_holiday',
    md5('workforce_public_holiday:' || p_holiday_date::text)::uuid, null,
    null,
    jsonb_build_object(
      'date', p_holiday_date, 'name', p_holiday_name,
      'removed', coalesce(p_remove, false)
    ),
    null, null
  );
  return public.v1_wf_list_public_holidays(
    extract(year from p_holiday_date)::integer
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Saving a day.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_save_day(
  p_team_id uuid,
  p_work_date date,
  p_rows jsonb,
  p_expected_version bigint,
  p_change_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'take');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_has_sheet boolean;
  v_day_type text := public.v1_wf_day_type(p_work_date);
  v_today date := public.v1_wf_today();
  v_reason text := nullif(btrim(coalesce(p_change_reason, '')), '');
  v_needs_reason boolean;
  v_item jsonb;
  v_worker uuid;
  v_status text;
  v_start integer;
  v_break_start integer;
  v_break_finish integer;
  v_finish integer;
  v_work_project uuid;
  v_label text;
  v_note text;
  v_copied boolean;
  v_minutes integer[];
  v_old public.v1_workforce_day_rows%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_seen uuid[] := array[]::uuid[];
  v_changed_count integer := 0;
  v_project uuid;
  v_counts jsonb;
begin
  if p_work_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_save_day', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'date', p_work_date, 'rows', p_rows,
      'expected', p_expected_version, 'reason', p_change_reason
    )
  );
  if v_existing is not null then
    return public.v1_wf_get_day(p_team_id, p_work_date);
  end if;

  if p_work_date > v_today then
    raise exception 'V1_WORKFORCE_FUTURE_DATE' using errcode = '22023';
  end if;
  if public.v1_wf_month_locked(p_team_id, p_work_date) then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  if jsonb_typeof(p_rows) <> 'array'
    or jsonb_array_length(p_rows) = 0
    or jsonb_array_length(p_rows) > 500 then
    raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
  end if;

  select project_id into v_project
  from public.v1_workforce_crew_profiles where team_id = p_team_id;

  -- Serialize the crew day.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workforce_day:' || p_team_id::text || ':' || p_work_date::text, 0
    )
  );
  select * into v_sheet
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id and sheet.work_date = p_work_date
  for update;
  v_has_sheet := found;
  if coalesce(p_expected_version, -1)
    <> (case when v_has_sheet then v_sheet.record_version else 0 end) then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_DAY_VERSION_CONFLICT'
    );
  end if;
  v_needs_reason := v_has_sheet and v_sheet.entered_by_auth_user_id <> v_actor;
  if v_needs_reason and v_reason is null then
    raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
  end if;

  if not v_has_sheet then
    insert into public.v1_workforce_day_sheets (
      team_id, work_date, entered_by_auth_user_id, entered_at, entered_late,
      last_saved_by_auth_user_id, last_saved_at
    ) values (
      p_team_id, p_work_date, v_actor, clock_timestamp(),
      p_work_date < v_today, v_actor, clock_timestamp()
    )
    returning * into v_sheet;
  else
    update public.v1_workforce_day_sheets
    set last_saved_by_auth_user_id = v_actor,
        last_saved_at = clock_timestamp(),
        record_version = record_version + 1
    where id = v_sheet.id
    returning * into v_sheet;
  end if;

  for v_item in select value from jsonb_array_elements(p_rows) loop
    perform public.v1_assert_object_keys(
      v_item,
      array[
        'worker_id', 'status', 'start_minute', 'break_start_minute',
        'break_finish_minute', 'finish_minute', 'work_project_id',
        'work_label', 'overtime_note', 'copied'
      ],
      'save_workforce_day_row'
    );
    begin
      v_worker := (v_item ->> 'worker_id')::uuid;
      v_status := v_item ->> 'status';
      v_start := (v_item ->> 'start_minute')::integer;
      v_break_start := (v_item ->> 'break_start_minute')::integer;
      v_break_finish := (v_item ->> 'break_finish_minute')::integer;
      v_finish := (v_item ->> 'finish_minute')::integer;
      v_work_project := nullif(v_item ->> 'work_project_id', '')::uuid;
      v_copied := coalesce((v_item ->> 'copied')::boolean, false);
    exception when others then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end;
    v_label := nullif(btrim(coalesce(v_item ->> 'work_label', '')), '');
    v_note := nullif(btrim(coalesce(v_item ->> 'overtime_note', '')), '');
    if v_worker is null or v_worker = any(v_seen) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    v_seen := v_seen || v_worker;
    if v_status is null then
      raise exception 'V1_WORKFORCE_DAY_UNMARKED' using errcode = '22023';
    end if;
    if v_status not in ('P', 'A', 'OFF', 'AL', 'SL', 'OL', 'UL') then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if v_status = 'OFF' and v_day_type = 'work' then
      raise exception 'V1_WORKFORCE_REST_DAY_NOT_ALLOWED' using errcode = '22023';
    end if;
    if v_status = 'P' then
      if v_start is null or v_finish is null or v_finish <= v_start
        or (v_break_start is null) <> (v_break_finish is null)
        or (v_break_start is not null and v_break_finish <= v_break_start)
      then
        raise exception 'V1_WORKFORCE_TIME_MISSING' using errcode = '22023';
      end if;
    else
      v_start := null; v_break_start := null;
      v_break_finish := null; v_finish := null;
    end if;
    if v_work_project is not null and not exists (
      select 1 from public.v1_projects project where project.id = v_work_project
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.v1_workforce_workers worker where worker.id = v_worker
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if exists (
      select 1 from public.v1_workforce_day_rows other_row
      where other_row.worker_id = v_worker
        and other_row.work_date = p_work_date
        and other_row.sheet_id <> v_sheet.id
    ) then
      raise exception 'V1_WORKFORCE_WORKER_ON_OTHER_CREW' using errcode = '23505';
    end if;
    v_minutes := public.v1_wf_compute_minutes(
      v_status, v_start, v_break_start, v_break_finish, v_finish, v_day_type
    );

    select * into v_old
    from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id and day_row.worker_id = v_worker;
    v_before := case when found then jsonb_build_object(
      'status', v_old.attendance_status,
      'start_minute', v_old.start_minute,
      'break_start_minute', v_old.break_start_minute,
      'break_finish_minute', v_old.break_finish_minute,
      'finish_minute', v_old.finish_minute,
      'work_project_id', v_old.work_project_id,
      'work_label', v_old.work_label
    ) end;
    v_after := jsonb_build_object(
      'status', v_status,
      'start_minute', v_start,
      'break_start_minute', v_break_start,
      'break_finish_minute', v_break_finish,
      'finish_minute', v_finish,
      'work_project_id', v_work_project,
      'work_label', v_label
    );

    insert into public.v1_workforce_day_rows (
      sheet_id, team_id, work_date, worker_id, attendance_status,
      start_minute, break_start_minute, break_finish_minute, finish_minute,
      work_project_id, work_label, overtime_note, copied,
      worked_minutes, regular_minutes, normal_overtime_minutes,
      holiday_overtime_minutes, updated_by_auth_user_id
    ) values (
      v_sheet.id, p_team_id, p_work_date, v_worker, v_status,
      v_start, v_break_start, v_break_finish, v_finish,
      v_work_project, v_label, v_note, v_copied,
      v_minutes[1], v_minutes[2], v_minutes[3], v_minutes[4], v_actor
    )
    on conflict (sheet_id, worker_id) do update
    set attendance_status = excluded.attendance_status,
        start_minute = excluded.start_minute,
        break_start_minute = excluded.break_start_minute,
        break_finish_minute = excluded.break_finish_minute,
        finish_minute = excluded.finish_minute,
        work_project_id = excluded.work_project_id,
        work_label = excluded.work_label,
        overtime_note = excluded.overtime_note,
        copied = excluded.copied,
        changed_after_entry = public.v1_workforce_day_rows.changed_after_entry
          or (v_needs_reason and v_before is distinct from v_after),
        worked_minutes = excluded.worked_minutes,
        regular_minutes = excluded.regular_minutes,
        normal_overtime_minutes = excluded.normal_overtime_minutes,
        holiday_overtime_minutes = excluded.holiday_overtime_minutes,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp();

    if v_needs_reason and v_before is distinct from v_after then
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_worker, v_before, v_after, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    end if;
  end loop;

  -- Every current crew member must be on the day.
  if exists (
    select 1
    from public.v1_workforce_crew_members member
    join public.v1_workforce_workers worker on worker.id = member.worker_id
    where member.team_id = p_team_id
      and member.removed_at is null
      and worker.current_status = 'active'
      and not (member.worker_id = any(v_seen))
      and not exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = member.worker_id
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
      )
  ) then
    raise exception 'V1_WORKFORCE_DAY_UNMARKED' using errcode = '22023';
  end if;

  -- Rows left out of this save (a worker added for the day only) are removed
  -- and, when the day belonged to someone else, logged.
  for v_old in
    select * from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id
      and not (day_row.worker_id = any(v_seen))
  loop
    if v_needs_reason then
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_old.worker_id,
        jsonb_build_object('status', v_old.attendance_status),
        null, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    end if;
    delete from public.v1_workforce_day_rows where id = v_old.id;
  end loop;

  select jsonb_build_object(
    'present', count(*) filter (where attendance_status = 'P'),
    'absent', count(*) filter (where attendance_status = 'A'),
    'leave', count(*) filter (
      where attendance_status in ('AL', 'SL', 'OL', 'UL')
    ),
    'normal_overtime_minutes', coalesce(sum(normal_overtime_minutes), 0),
    'holiday_overtime_minutes', coalesce(sum(holiday_overtime_minutes), 0)
  )
  into v_counts
  from public.v1_workforce_day_rows
  where sheet_id = v_sheet.id;

  if not v_has_sheet then
    insert into public.v1_workforce_attendance_events (
      team_id, work_date, event_kind, summary, actor_auth_user_id,
      actor_exact_role
    ) values (
      p_team_id, p_work_date, 'entered', v_counts, v_actor, v_role
    );
  elsif v_changed_count > 0 then
    insert into public.v1_workforce_attendance_events (
      team_id, work_date, event_kind, summary, actor_auth_user_id,
      actor_exact_role
    ) values (
      p_team_id, p_work_date, 'changed',
      v_counts || jsonb_build_object(
        'changed_rows', v_changed_count, 'reason', v_reason
      ),
      v_actor, v_role
    );
    perform public.v1_wf_notify(
      v_sheet.entered_by_auth_user_id, 'workforce_attendance_day_changed',
      'workforce_day_sheet', v_sheet.id, v_project
    );
  end if;

  perform public.v1_write_audit_event(
    case when v_has_sheet then 'workforce_day_updated'
      else 'workforce_day_entered' end,
    'workforce_day_sheet', v_sheet.id, v_project, null,
    v_counts || jsonb_build_object(
      'work_date', p_work_date, 'changed_rows', v_changed_count
    ),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_save_day', p_idempotency_key,
    jsonb_build_object('sheet_id', v_sheet.id)
  );
  return public.v1_wf_get_day(p_team_id, p_work_date);
exception
  when unique_violation then
    if sqlerrm like '%v1_workforce_day_rows_worker_id_work_date_key%' then
      raise exception 'V1_WORKFORCE_WORKER_ON_OTHER_CREW' using errcode = '23505';
    end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Questions.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_ask_day(
  p_team_id uuid,
  p_work_date date,
  p_question text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'confirm');
  v_existing jsonb;
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_question text := btrim(coalesce(p_question, ''));
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_ask_day', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'date', p_work_date, 'question', p_question
    )
  );
  if v_existing is not null then
    return public.v1_wf_get_day(p_team_id, p_work_date);
  end if;
  if v_question = '' or char_length(v_question) > 500 then
    raise exception 'V1_WORKFORCE_QUESTION_INVALID' using errcode = '22023';
  end if;
  if public.v1_wf_month_locked(p_team_id, p_work_date) then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  select * into v_sheet
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id and sheet.work_date = p_work_date
  for update;
  if not found then
    raise exception 'V1_WORKFORCE_DAY_NOT_ENTERED' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.v1_workforce_day_questions question
    where question.sheet_id = v_sheet.id and question.answer is null
  ) then
    raise exception 'V1_WORKFORCE_QUESTION_ALREADY_OPEN' using errcode = '55000';
  end if;
  insert into public.v1_workforce_day_questions (
    sheet_id, question, asked_by_auth_user_id
  ) values (v_sheet.id, v_question, v_actor);
  insert into public.v1_workforce_attendance_events (
    team_id, work_date, event_kind, summary, actor_auth_user_id,
    actor_exact_role
  ) values (
    p_team_id, p_work_date, 'asked',
    jsonb_build_object('question', v_question),
    v_actor, public.v1_current_exact_role()
  );
  perform public.v1_wf_notify(
    v_sheet.entered_by_auth_user_id, 'workforce_attendance_question',
    'workforce_day_sheet', v_sheet.id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id)
  );
  perform public.v1_write_audit_event(
    'workforce_day_question_asked', 'workforce_day_sheet', v_sheet.id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id),
    null, jsonb_build_object('work_date', p_work_date), null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_ask_day', p_idempotency_key,
    jsonb_build_object('sheet_id', v_sheet.id)
  );
  return public.v1_wf_get_day(p_team_id, p_work_date);
end;
$$;

create or replace function public.v1_wf_answer_day(
  p_team_id uuid,
  p_work_date date,
  p_answer text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'take');
  v_existing jsonb;
  v_question public.v1_workforce_day_questions%rowtype;
  v_answer text := btrim(coalesce(p_answer, ''));
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_answer_day', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'date', p_work_date, 'answer', p_answer
    )
  );
  if v_existing is not null then
    return public.v1_wf_get_day(p_team_id, p_work_date);
  end if;
  if v_answer = '' or char_length(v_answer) > 500 then
    raise exception 'V1_WORKFORCE_QUESTION_INVALID' using errcode = '22023';
  end if;
  select question.* into v_question
  from public.v1_workforce_day_questions question
  join public.v1_workforce_day_sheets sheet on sheet.id = question.sheet_id
  where sheet.team_id = p_team_id
    and sheet.work_date = p_work_date
    and question.answer is null
  for update of question;
  if not found then
    raise exception 'V1_WORKFORCE_QUESTION_NOT_OPEN' using errcode = 'P0002';
  end if;
  update public.v1_workforce_day_questions
  set answer = v_answer,
      answered_by_auth_user_id = v_actor,
      answered_at = clock_timestamp()
  where id = v_question.id;
  insert into public.v1_workforce_attendance_events (
    team_id, work_date, event_kind, summary, actor_auth_user_id,
    actor_exact_role
  ) values (
    p_team_id, p_work_date, 'answered',
    jsonb_build_object('answer', v_answer),
    v_actor, public.v1_current_exact_role()
  );
  perform public.v1_wf_notify(
    v_question.asked_by_auth_user_id, 'workforce_attendance_answered',
    'workforce_day_sheet', v_question.sheet_id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id)
  );
  perform public.v1_write_audit_event(
    'workforce_day_question_answered', 'workforce_day_sheet',
    v_question.sheet_id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id),
    null, jsonb_build_object('work_date', p_work_date), null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_answer_day', p_idempotency_key,
    jsonb_build_object('question_id', v_question.id)
  );
  return public.v1_wf_get_day(p_team_id, p_work_date);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Month confirmation.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_confirm_month(
  p_team_id uuid,
  p_month date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'confirm');
  v_month date := date_trunc('month', p_month)::date;
  v_last date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_existing jsonb;
  v_row public.v1_workforce_month_confirmations%rowtype;
  v_missing integer;
  v_project uuid;
begin
  if p_month is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_confirm_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month)
  );
  if v_existing is not null then
    return public.v1_wf_month_json(p_team_id, v_month);
  end if;
  if public.v1_wf_today() < v_last then
    raise exception 'V1_WORKFORCE_MONTH_NOT_ENDED' using errcode = '55000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workforce_month:' || p_team_id::text || ':' || v_month::text, 0
    )
  );
  select count(*) into v_missing
  from generate_series(v_month, v_last, interval '1 day') series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
    and not exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where sheet.team_id = p_team_id
        and sheet.work_date = series.day_ts::date
    );
  if v_missing > 0 then
    raise exception 'V1_WORKFORCE_MONTH_INCOMPLETE' using errcode = '55000';
  end if;
  select * into v_row
  from public.v1_workforce_month_confirmations confirmation
  where confirmation.team_id = p_team_id
    and confirmation.period_month = v_month
  for update;
  if found and v_row.is_confirmed then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  insert into public.v1_workforce_month_confirmations (
    team_id, period_month, is_confirmed, confirmed_by_auth_user_id,
    confirmed_at
  ) values (p_team_id, v_month, true, v_actor, clock_timestamp())
  on conflict (team_id, period_month) do update
  set is_confirmed = true,
      confirmed_by_auth_user_id = v_actor,
      confirmed_at = clock_timestamp(),
      record_version = public.v1_workforce_month_confirmations.record_version + 1;

  select project_id into v_project
  from public.v1_workforce_crew_profiles where team_id = p_team_id;
  insert into public.v1_workforce_attendance_events (
    team_id, period_month, event_kind, summary, actor_auth_user_id,
    actor_exact_role
  ) values (
    p_team_id, v_month, 'confirmed', '{}'::jsonb, v_actor,
    public.v1_current_exact_role()
  );
  perform public.v1_write_audit_event(
    'workforce_month_confirmed', 'workforce_crew', p_team_id, v_project,
    null, jsonb_build_object('month', v_month), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_confirm_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month)
  );
  return public.v1_wf_month_json(p_team_id, v_month);
end;
$$;

create or replace function public.v1_wf_reopen_month(
  p_team_id uuid,
  p_month date,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'officer');
  v_month date := date_trunc('month', p_month)::date;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_existing jsonb;
  v_project uuid;
begin
  if not public.v1_wf_allowed('workforce.periods.reopen') then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_reopen_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month, 'reason', p_reason)
  );
  if v_existing is not null then
    return public.v1_wf_month_json(p_team_id, v_month);
  end if;
  if v_reason = '' or char_length(v_reason) > 500 then
    raise exception 'V1_WORKFORCE_REASON_REQUIRED' using errcode = '22023';
  end if;
  update public.v1_workforce_month_confirmations
  set is_confirmed = false,
      reopened_by_auth_user_id = v_actor,
      reopened_at = clock_timestamp(),
      reopen_reason = v_reason,
      record_version = record_version + 1
  where team_id = p_team_id
    and period_month = v_month
    and is_confirmed;
  if not found then
    raise exception 'V1_WORKFORCE_MONTH_NOT_CONFIRMED' using errcode = '55000';
  end if;
  select project_id into v_project
  from public.v1_workforce_crew_profiles where team_id = p_team_id;
  insert into public.v1_workforce_attendance_events (
    team_id, period_month, event_kind, summary, actor_auth_user_id,
    actor_exact_role
  ) values (
    p_team_id, v_month, 'reopened', jsonb_build_object('reason', v_reason),
    v_actor, public.v1_current_exact_role()
  );
  perform public.v1_write_audit_event(
    'workforce_month_reopened', 'workforce_crew', p_team_id, v_project,
    null, jsonb_build_object('month', v_month), v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_reopen_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month)
  );
  return public.v1_wf_month_json(p_team_id, v_month);
end;
$$;

-- Month-end reminder for confirmers (run daily by the scheduler, or on
-- demand by Admin). Idempotent per crew, month and recipient.
create table public.v1_workforce_month_reminders (
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  period_month date not null,
  recipient_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  sent_at timestamptz not null default clock_timestamp(),
  primary key (team_id, period_month, recipient_auth_user_id)
);
create trigger v1_workforce_month_reminders_no_delete
before delete on public.v1_workforce_month_reminders
for each row execute function public.v1_workforce_block_delete();
alter table public.v1_workforce_month_reminders enable row level security;
revoke all on table public.v1_workforce_month_reminders
  from public, anon, authenticated;

create or replace function public.v1_wf_send_month_end_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_month date := date_trunc('month', v_today)::date;
  v_last date := (date_trunc('month', v_today) + interval '1 month - 1 day')::date;
  v_count integer := 0;
  v_row record;
begin
  if v_today <> v_last then
    return 0;
  end if;
  for v_row in
    select profile.team_id, profile.project_id, recipient.auth_user_id
    from public.v1_workforce_crew_profiles profile
    cross join lateral (
      select member.member_auth_user_id as auth_user_id
      from public.v1_project_members member
      where member.project_id = profile.project_id
        and member.project_role = 'project_engineer'
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
    ) recipient
    where profile.is_active and profile.needs_confirmation
      and not public.v1_wf_month_locked(profile.team_id, v_today)
  loop
    insert into public.v1_workforce_month_reminders (
      team_id, period_month, recipient_auth_user_id
    ) values (v_row.team_id, v_month, v_row.auth_user_id)
    on conflict do nothing;
    if found then
      insert into public.v1_notifications (
        id, recipient_auth_user_id, event_code, entity_type, entity_id,
        project_id
      ) values (
        gen_random_uuid(), v_row.auth_user_id,
        'workforce_attendance_month_ready', 'workforce_crew',
        v_row.team_id, v_row.project_id
      );
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Notification links. Attendance notifications open the crew day (or
--     Month confirmation) through narrowly scoped wrappers that keep every
--     other module's behaviour, in the same way the Rentals wrappers do.
-- ---------------------------------------------------------------------------

do $wrap$ begin
  if to_regprocedure('public.v1_notification_module_route_before_attendance(public.v1_notifications)') is null then
    alter function public.v1_push_notification_entity_allowed(public.v1_notifications) rename to v1_push_notification_entity_allowed_before_attendance;
    alter function public.v1_notification_module_route(public.v1_notifications) rename to v1_notification_module_route_before_attendance;
    alter function public.v1_notification_record_label(public.v1_notifications) rename to v1_notification_record_label_before_attendance;
  end if;
end; $wrap$;
revoke all on function
  public.v1_push_notification_entity_allowed_before_attendance(public.v1_notifications),
  public.v1_notification_module_route_before_attendance(public.v1_notifications),
  public.v1_notification_record_label_before_attendance(public.v1_notifications)
  from public, anon, authenticated, service_role;

create or replace function public.v1_wf_notification_is_attendance(
  n public.v1_notifications
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select n.event_code like 'workforce_attendance_%'
    and n.entity_type in ('workforce_day_sheet', 'workforce_crew');
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
  if public.v1_wf_notification_is_attendance(n) then
    return true;
  end if;
  return public.v1_push_notification_entity_allowed_before_attendance(n);
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
  v_team uuid;
  v_date date;
begin
  if public.v1_wf_notification_is_attendance(n) then
    if n.entity_type = 'workforce_crew' then
      return '/yorks/workforce/confirm';
    end if;
    select sheet.team_id, sheet.work_date into v_team, v_date
    from public.v1_workforce_day_sheets sheet
    where sheet.id = n.entity_id;
    if v_team is null then
      return '/yorks/workforce';
    end if;
    return '/yorks/workforce/attendance?crew=' || v_team::text
      || '&date=' || to_char(v_date, 'YYYY-MM-DD');
  end if;
  return public.v1_notification_module_route_before_attendance(n);
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
  if public.v1_wf_notification_is_attendance(n) then
    if auth.uid() is distinct from n.recipient_auth_user_id then
      return null;
    end if;
    if n.entity_type = 'workforce_crew' then
      select team.team_name into v_label
      from public.v1_workforce_teams team
      where team.id = n.entity_id;
    else
      select team.team_name || ' · ' || to_char(sheet.work_date, 'DD Mon')
      into v_label
      from public.v1_workforce_day_sheets sheet
      join public.v1_workforce_teams team on team.id = sheet.team_id
      where sheet.id = n.entity_id;
    end if;
    return nullif(
      left(btrim(regexp_replace(v_label, '[[:cntrl:]]', ' ', 'g')), 180),
      ''
    );
  end if;
  return public.v1_notification_record_label_before_attendance(n);
end;
$$;

revoke all on function
  public.v1_wf_notification_is_attendance(public.v1_notifications),
  public.v1_push_notification_entity_allowed(public.v1_notifications),
  public.v1_notification_module_route(public.v1_notifications),
  public.v1_notification_record_label(public.v1_notifications)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11. Grants.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_today()',
    'v1_wf_allowed(text)',
    'v1_wf_day_type(date)',
    'v1_wf_compute_minutes(text,integer,integer,integer,integer,text)',
    'v1_wf_role_is_global(text)',
    'v1_wf_crew_access(uuid)',
    'v1_wf_assert_crew(uuid,text)',
    'v1_wf_month_locked(uuid,date)',
    'v1_wf_display_name(uuid)',
    'v1_wf_notify(uuid,text,text,uuid,uuid)',
    'v1_wf_crew_json(uuid)',
    'v1_wf_worker_json(uuid)',
    'v1_wf_row_json(public.v1_workforce_day_rows)',
    'v1_wf_day_state(uuid,date)',
    'v1_wf_month_json(uuid,date)',
    'v1_wf_send_month_end_reminders()',
    'v1_wf_block_history_mutation()'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'v1_wf_list_crews()',
    'v1_wf_get_crew(uuid)',
    'v1_wf_get_overview(date)',
    'v1_wf_get_day(uuid,date)',
    'v1_wf_get_month_sheet(uuid,date)',
    'v1_wf_list_workers()',
    'v1_wf_list_public_holidays(integer)',
    'v1_wf_save_crew(jsonb,bigint,uuid)',
    'v1_wf_set_crew_members(uuid,uuid[],uuid[],uuid)',
    'v1_wf_save_public_holiday(date,text,boolean)',
    'v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)',
    'v1_wf_ask_day(uuid,date,text,uuid)',
    'v1_wf_answer_day(uuid,date,text,uuid)',
    'v1_wf_confirm_month(uuid,date,uuid)',
    'v1_wf_reopen_month(uuid,date,text,uuid)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon', v_signature
    );
    execute format(
      'grant execute on function public.%s to authenticated', v_signature
    );
  end loop;
end;
$grants$;

notify pgrst, 'reload schema';

commit;

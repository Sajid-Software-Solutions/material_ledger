-- Release bundle: attendance terminals, a check-in puts the labourer on the
-- place's day (PRODUCT_DECISIONS.md section 65). Applies migration
-- 20261118090000 in one transaction, after checking what it replaces and
-- before checking itself.
--
-- What changes for people: nothing. Every terminal starts (and stays)
-- watching, so no line is added to any day until a terminal is switched to
-- adding with v1_wf_set_terminal_mode, on the owner's word. The app in
-- production keeps working unchanged: v1_wf_save_day only gains an optional
-- argument.
--
-- It replaces eight functions (v1_wf_row_json, v1_wf_get_day,
-- v1_wf_today_json, v1_wf_get_month_sheet, v1_wf_save_day,
-- v1_wf_terminal_json, v1_wf_register_terminal, v1_wf_terminal_punches). It
-- first checks that each is exactly the one on main (or already this
-- release) and stops, changing nothing, if one is not: production has run
-- unmerged work before.
--
-- Re-running it is harmless: tables, columns and constraints are created
-- only if missing, and every terminal, match and day is left as it is.
-- Apply by hand (staging, then production, each with the owner's OK):
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/terminal_attendance_bundle.sql
-- No Edge Function or app deploy is needed. Like the other hand-applied
-- bundles it does not write supabase_migrations.schema_migrations.
-- Rollback: supabase/release/terminal_attendance_rollback.sql

begin;

-- ---------------------------------------------------------------------------
-- 0. Before anything changes.
-- ---------------------------------------------------------------------------

do $preflight$
declare
  v_row record;
  v_found text;
  v_wrong text := '';
begin
  -- The receiver and the punch log (section 64) must be there.
  if to_regclass('public.v1_workforce_terminals') is null
    or to_regclass('public.v1_workforce_terminal_punches') is null
    or to_regprocedure('public.v1_wf_terminal_gate(text)') is null
    or to_regprocedure('public.v1_wf_recompute_worker_day(uuid,date)') is null
    or to_regprocedure('public.v1_wf_is_labour(uuid)') is null then
    raise exception
      'terminal attendance bundle: apply attendance_terminals_bundle.sql first';
  end if;
  -- Each function replaced here is the one on main, or already this release.
  for v_row in
    select * from (values
    ('v1_wf_row_json', '478f36ba11b2b692951b9f8e08475645', 'f9b0d84264ab5c69b538ddd2c88831ab'),
    ('v1_wf_get_day', '1233808a752c669d9d5a7c53e7024d3b', '8ea1462e90735c9ad0df529be89bee27'),
    ('v1_wf_today_json', 'f980192e7bc88a70eaddc8ffea6d4be9', 'adfdec19a2da2e32cf618dcc93be0740'),
    ('v1_wf_get_month_sheet', 'd66854c2f82862b4742f14ee2c52f586', 'ebc8c97018ce71f90f887781510f3992'),
    ('v1_wf_save_day', '6463f40ed4c6407128988ec251ab24ab', '8e3abd9a37db283729c188045cc49e9f'),
    ('v1_wf_terminal_json', 'f28c44ba93562c7b1788f9a18d74fda8', 'c85223bb85ac96b4cebc6f2c9456411e'),
    ('v1_wf_register_terminal', 'f32084f0c222d591052f970230437345', '38870a9278f0ae2cd69396ef6564ac7b'),
    ('v1_wf_terminal_punches', '756b565d1219fd36f71eadf7bdcca39d', '53f589c5778f5b26aabae12913177f48')
    ) expected(function_name, main_md5, release_md5)
  loop
    select string_agg(md5(procedure.prosrc), ',')
    into v_found
    from pg_catalog.pg_proc procedure
    where procedure.pronamespace = 'public'::regnamespace
      and procedure.proname = v_row.function_name;
    if v_found is null
      or v_found not in (v_row.main_md5, v_row.release_md5) then
      v_wrong := v_wrong || format(
        ' %s (found %s)', v_row.function_name, coalesce(v_found, 'none'));
    end if;
  end loop;
  if v_wrong <> '' then
    raise exception
      'terminal attendance bundle: not the functions on main, nothing changed:%',
      v_wrong;
  end if;
end;
$preflight$;


-- ---------------------------------------------------------------------------
-- 1. Schema.
-- ---------------------------------------------------------------------------

-- A terminal watches (the default) or adds.
alter table public.v1_workforce_terminals
  add column if not exists attendance_mode text not null default 'watch';

-- A sheet may be opened by a terminal; a line may be a terminal's.
alter table public.v1_workforce_day_sheets
  add column if not exists entered_by_terminal_id uuid,
  -- Labourers a person removed from this day: a terminal does not add them
  -- to it again.
  add column if not exists hand_removed_worker_ids uuid[]
    not null default '{}'::uuid[];
alter table public.v1_workforce_day_sheets
  alter column entered_by_auth_user_id drop not null,
  alter column last_saved_by_auth_user_id drop not null;

alter table public.v1_workforce_day_rows
  add column if not exists terminal_id uuid;
alter table public.v1_workforce_day_rows
  alter column updated_by_auth_user_id drop not null;

-- A sheet's version counts the saves made by people. A sheet a terminal
-- opened starts at 0, so an app that loaded the day before the terminal's
-- line still saves against the version it holds.
alter table public.v1_workforce_day_sheets
  drop constraint if exists v1_workforce_day_sheets_record_version_check;

do $schema$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_terminals_attendance_mode_check'
  ) then
    alter table public.v1_workforce_terminals
      add constraint v1_workforce_terminals_attendance_mode_check check (
        attendance_mode in ('watch', 'add')
        -- Only a terminal that serves a place can add.
        and (attendance_mode = 'watch' or team_id is not null)
      );
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_sheets_entered_by_terminal_fkey'
  ) then
    alter table public.v1_workforce_day_sheets
      add constraint v1_workforce_day_sheets_entered_by_terminal_fkey
      foreign key (entered_by_terminal_id)
      references public.v1_workforce_terminals (id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_sheets_saved_by_check'
  ) then
    -- Either a person has saved the day (version 1 or more), or only a
    -- terminal has written on it (version 0).
    alter table public.v1_workforce_day_sheets
      add constraint v1_workforce_day_sheets_saved_by_check check (
        (
          entered_by_auth_user_id is not null
          and last_saved_by_auth_user_id is not null
          and record_version > 0
        )
        or (
          entered_by_auth_user_id is null
          and last_saved_by_auth_user_id is null
          and entered_by_terminal_id is not null
          and record_version = 0
        )
      );
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_rows_terminal_fkey'
  ) then
    alter table public.v1_workforce_day_rows
      add constraint v1_workforce_day_rows_terminal_fkey
      foreign key (terminal_id)
      references public.v1_workforce_terminals (id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_rows_saved_by_check'
  ) then
    -- A line is a person's, or a terminal's: Present, at most 8 hours.
    alter table public.v1_workforce_day_rows
      add constraint v1_workforce_day_rows_saved_by_check check (
        updated_by_auth_user_id is not null
        or (
          terminal_id is not null
          and attendance_status = 'P'
          and worked_minutes <= 480
        )
      );
  end if;
end;
$schema$;

-- A terminal user ID matched to a labourer, confirmed by HR/PRO or Admin.
-- A match is ended, never deleted.
create table if not exists public.v1_workforce_terminal_users (
  id uuid primary key default gen_random_uuid(),
  -- The terminal's user ID; a number is kept without leading zeros.
  device_user_id text not null check (
    device_user_id ~ '^[0-9A-Za-z]{1,24}$'
    and device_user_id !~ '^0[0-9]*$'
  ),
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  -- The ID is the digits of the labourer's number (418 for WR-000418).
  follows_number boolean not null,
  confirmed_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  confirmed_by_role text not null,
  confirmed_at timestamptz not null default clock_timestamp(),
  ended_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  ended_by_role text,
  ended_at timestamptz,
  end_reason text check (
    end_reason is null
    or (btrim(end_reason) <> '' and char_length(end_reason) <= 500)
  ),
  check ((ended_at is null) = (ended_by_auth_user_id is null)),
  check ((ended_at is null) = (ended_by_role is null)),
  check ((ended_at is null) = (end_reason is null))
);
-- One labourer per ID and one ID per labourer, among current matches.
create unique index if not exists v1_workforce_terminal_users_id_uidx
  on public.v1_workforce_terminal_users (device_user_id)
  where ended_at is null;
create unique index if not exists v1_workforce_terminal_users_worker_uidx
  on public.v1_workforce_terminal_users (worker_id)
  where ended_at is null;

-- What a terminal's check-ins did on a day, one row per terminal, day and
-- terminal user ID: the first and last check-in, the labourer, what the rules
-- found and whether a line was added.
create table if not exists public.v1_workforce_terminal_days (
  id uuid primary key default gen_random_uuid(),
  terminal_id uuid not null
    references public.v1_workforce_terminals (id) on delete restrict,
  work_date date not null,
  device_user_id text not null check (
    device_user_id ~ '^[0-9A-Za-z]{1,24}$'
  ),
  -- The place the terminal served and the labourer the ID was matched to,
  -- when this was last decided.
  team_id uuid
    references public.v1_workforce_crew_profiles (team_id) on delete restrict,
  worker_id uuid
    references public.v1_workforce_workers (id) on delete restrict,
  first_punched_at_local timestamp without time zone not null,
  last_punched_at_local timestamp without time zone not null,
  punch_count integer not null check (punch_count > 0),
  -- 'add': a line on the usual shift (added, or what would be added while
  -- the terminal watches). 'on_day': the labourer already had a line there.
  -- Anything else is why no line was added.
  finding text not null check (finding in (
    'add', 'on_day', 'no_place', 'unmatched', 'clock', 'staff', 'not_active',
    'removed_by_hand', 'late', 'month_confirmed', 'rest_day', 'elsewhere',
    'outside_shift', 'error'
  )),
  -- The terminal added the line. It stays true if a person later changes or
  -- removes that line.
  added boolean not null default false,
  -- The terminal was watching when this was decided.
  watching boolean not null,
  decided_at timestamptz not null default clock_timestamp(),
  unique (terminal_id, work_date, device_user_id),
  check (last_punched_at_local >= first_punched_at_local),
  check (
    first_punched_at_local::date = work_date
    and last_punched_at_local::date = work_date
  ),
  check (
    not added
    or (finding = 'add' and not watching
      and team_id is not null and worker_id is not null)
  )
);
create index if not exists v1_workforce_terminal_days_place_idx
  on public.v1_workforce_terminal_days (team_id, work_date)
  where team_id is not null;
create index if not exists v1_workforce_terminal_days_worker_idx
  on public.v1_workforce_terminal_days (worker_id, work_date)
  where worker_id is not null;
create index if not exists v1_workforce_terminal_days_retry_idx
  on public.v1_workforce_terminal_days (terminal_id, work_date)
  where finding = 'error';

create or replace trigger v1_workforce_terminal_users_no_delete
before delete on public.v1_workforce_terminal_users
for each row execute function public.v1_workforce_block_delete();
create or replace trigger v1_workforce_terminal_days_no_delete
before delete on public.v1_workforce_terminal_days
for each row execute function public.v1_workforce_block_delete();

do $lock_tables$
declare
  v_table text;
begin
  foreach v_table in array array[
    'v1_workforce_terminal_users', 'v1_workforce_terminal_days'
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
-- 2. Small helpers.
-- ---------------------------------------------------------------------------

-- A terminal user ID as it is matched: a number without its leading zeros
-- ("0418" is "418"), anything else as sent. Null when it is not an ID.
create or replace function public.v1_wf_terminal_user_key(
  p_device_user_id text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_device_user_id ~ '^[0-9]{1,24}$'
      then nullif(ltrim(p_device_user_id, '0'), '')
    when p_device_user_id ~ '^[0-9A-Za-z]{1,24}$' then p_device_user_id
  end;
$$;

-- The terminal user ID a labourer's number gives: the digits it ends with,
-- without leading zeros ("WR-000418" is "418"). Null when it ends with none.
create or replace function public.v1_wf_terminal_number_id(
  p_worker_number text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when digits.value ~ '^[1-9][0-9]{0,8}$' then digits.value end
  from (
    select ltrim(
      substring(btrim(coalesce(p_worker_number, '')) from '([0-9]+)$'), '0'
    ) as value
  ) digits;
$$;

-- Who saved a line or entered a day: the person, else the terminal.
create or replace function public.v1_wf_saved_by(
  p_auth_user_id uuid,
  p_terminal_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_auth_user_id is not null
      then public.v1_wf_display_name(p_auth_user_id)
    else coalesce((
      select terminal.terminal_name
      from public.v1_workforce_terminals terminal
      where terminal.id = p_terminal_id
    ), '')
  end;
$$;

-- Minutes after midnight of a terminal's time.
create or replace function public.v1_wf_terminal_minute(
  p_at timestamp without time zone
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (extract(hour from p_at) * 60 + extract(minute from p_at))::integer;
$$;

-- ---------------------------------------------------------------------------
-- 3. What a day and a line say about terminals.
-- ---------------------------------------------------------------------------

-- A line as every reader gets it. A terminal's line names the terminal as
-- who saved it and is never "mine"; the day's first and last check-in at the
-- place are beside it and are not the sheet's times.
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
    'work_scope_id', p_row.work_scope_id,
    'work_scope_name', (
      select scope.name from public.v1_project_scopes scope
      where scope.id = p_row.work_scope_id
    ),
    'work_scope_kind', (
      select scope.scope_kind from public.v1_project_scopes scope
      where scope.id = p_row.work_scope_id
    ),
    'updated_by', public.v1_wf_saved_by(
      p_row.updated_by_auth_user_id, p_row.terminal_id
    ),
    'updated_by_me', coalesce(p_row.updated_by_auth_user_id = auth.uid(), false),
    -- Saved by a terminal and not changed by a person since.
    'by_terminal', p_row.updated_by_auth_user_id is null,
    -- The terminal that added the line, kept after a person changes it.
    'terminal_name', (
      select terminal.terminal_name
      from public.v1_workforce_terminals terminal
      where terminal.id = p_row.terminal_id
    ),
    'check_in_minute', public.v1_wf_terminal_minute(punched.first_at),
    'check_out_minute', case when punched.last_at > punched.first_at
      then public.v1_wf_terminal_minute(punched.last_at) end,
    'check_ins', coalesce(punched.punches, 0),
    'overtime_note', p_row.overtime_note,
    'copied', p_row.copied,
    'changed_after_entry', p_row.changed_after_entry,
    'worked_minutes', p_row.worked_minutes,
    'regular_minutes', p_row.regular_minutes,
    'normal_overtime_minutes', p_row.normal_overtime_minutes,
    'holiday_overtime_minutes', p_row.holiday_overtime_minutes
  )
  from (
    select
      min(day.first_punched_at_local) as first_at,
      max(day.last_punched_at_local) as last_at,
      sum(day.punch_count) as punches
    from public.v1_workforce_terminal_days day
    where day.team_id = p_row.team_id
      and day.work_date = p_row.work_date
      and day.worker_id = p_row.worker_id
  ) punched;
$$;

-- The check-ins at a place on a day that are not a line on it: listed for
-- the keeper. Null when the place has no terminal and no check-in that day.
create or replace function public.v1_wf_terminal_day_json(
  p_team_id uuid,
  p_work_date date
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not exists (
      select 1 from public.v1_workforce_terminals terminal
      where terminal.team_id = p_team_id
    ) and not exists (
      select 1 from public.v1_workforce_terminal_days day
      where day.team_id = p_team_id and day.work_date = p_work_date
    ) then null
    else jsonb_build_object(
      -- A terminal here adds lines now.
      'adding', exists (
        select 1 from public.v1_workforce_terminals terminal
        where terminal.team_id = p_team_id
          and terminal.is_active
          and terminal.attendance_mode = 'add'
      ),
      'terminals', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', terminal.terminal_name,
          'adding', terminal.attendance_mode = 'add',
          'is_active', terminal.is_active,
          'last_seen_at', terminal.last_seen_at
        ) order by lower(terminal.terminal_name), terminal.id)
        from public.v1_workforce_terminals terminal
        where terminal.team_id = p_team_id
      ), '[]'::jsonb),
      'entries', coalesce((
        select jsonb_agg(jsonb_build_object(
          'device_user_id', day.device_user_id,
          'worker', case when day.worker_id is not null
            then public.v1_wf_worker_json(day.worker_id) end,
          'finding', day.finding,
          'added', day.added,
          'watching', day.watching,
          'check_in_minute',
            public.v1_wf_terminal_minute(day.first_punched_at_local),
          'check_out_minute', case
            when day.last_punched_at_local > day.first_punched_at_local
              then public.v1_wf_terminal_minute(day.last_punched_at_local)
          end,
          'check_ins', day.punch_count,
          'terminal_name', terminal.terminal_name
        ) order by day.first_punched_at_local, day.device_user_id)
        from public.v1_workforce_terminal_days day
        join public.v1_workforce_terminals terminal
          on terminal.id = day.terminal_id
        where day.team_id = p_team_id
          and day.work_date = p_work_date
          and not exists (
            select 1 from public.v1_workforce_day_rows day_row
            where day_row.team_id = p_team_id
              and day_row.work_date = p_work_date
              and day_row.worker_id = day.worker_id
          )
      ), '[]'::jsonb)
    )
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

  -- Saved rows first; then current members who have no row yet.
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
        'elsewhere', public.v1_wf_elsewhere_json(
          day_row.worker_id, p_work_date, p_team_id
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
      'elsewhere', public.v1_wf_elsewhere_json(
        member.worker_id, p_work_date, p_team_id
      ),
      'sort_name', lower(worker.full_name)
    )
    from public.v1_workforce_crew_members member
    join public.v1_workforce_workers worker on worker.id = member.worker_id
    where member.team_id = p_team_id
      and member.removed_at is null
      and worker.current_status = 'active'
      and not exists (
        select 1 from public.v1_workforce_crew_profiles place
        where place.team_id = p_team_id and place.place_key is not null
      )
      and not exists (
        select 1 from public.v1_workforce_day_rows day_row
        where day_row.sheet_id = v_sheet.id
          and day_row.worker_id = member.worker_id
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
    -- Saves made by people: 0 for a day only a terminal has written on.
    'record_version', case when v_has_sheet then v_sheet.record_version else 0 end,
    -- The first person who saved the day; the terminal that opened it until
    -- a person has.
    'entered_by', case when v_has_sheet then public.v1_wf_saved_by(
      v_sheet.entered_by_auth_user_id, v_sheet.entered_by_terminal_id
    ) end,
    'entered_by_me', v_has_sheet
      and coalesce(v_sheet.entered_by_auth_user_id = auth.uid(), false),
    -- The terminal that opened the day, whoever saved it since.
    'entered_by_terminal', (
      select terminal.terminal_name
      from public.v1_workforce_terminals terminal
      where terminal.id = v_sheet.entered_by_terminal_id
    ),
    'entered_at', v_sheet.entered_at,
    'entered_late', coalesce(v_sheet.entered_late, false),
    'last_saved_by', case when v_has_sheet then public.v1_wf_saved_by(
      v_sheet.last_saved_by_auth_user_id, v_sheet.entered_by_terminal_id
    ) end,
    'last_saved_at', v_sheet.last_saved_at,
    'locked', public.v1_wf_month_locked(p_team_id, p_work_date),
    'is_future', p_work_date > public.v1_wf_today(),
    'previous_same_type_date', v_previous,
    'rows', v_rows,
    'question', v_question,
    'changes', v_changes,
    'access', v_access,
    'month', public.v1_wf_month_json(p_team_id, p_work_date),
    'terminal', public.v1_wf_terminal_day_json(p_team_id, p_work_date)
  );
end;
$$;

-- One sheet's day: saved or not, by whom, and its counts by status.
create or replace function public.v1_wf_today_json(
  p_team_id uuid,
  p_work_date date
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'date', p_work_date,
    'entered', sheet.id is not null,
    'entered_by', case when sheet.id is not null
      then public.v1_wf_saved_by(
        sheet.entered_by_auth_user_id, sheet.entered_by_terminal_id
      ) end,
    'last_saved_by', case when sheet.id is not null
      then public.v1_wf_saved_by(
        sheet.last_saved_by_auth_user_id, sheet.entered_by_terminal_id
      ) end,
    'last_saved_at', sheet.last_saved_at,
    'present', coalesce(counted.present, 0),
    'absent', coalesce(counted.absent, 0),
    'leave', coalesce(counted.on_leave, 0),
    'rest', coalesce(counted.rest, 0)
  )
  from (select 1) anchor
  left join public.v1_workforce_day_sheets sheet
    on sheet.team_id = p_team_id and sheet.work_date = p_work_date
  left join lateral (
    select
      count(*) filter (where day_row.attendance_status = 'P') as present,
      count(*) filter (where day_row.attendance_status = 'A') as absent,
      count(*) filter (
        where day_row.attendance_status in ('AL', 'SL', 'OL', 'UL')
      ) as on_leave,
      count(*) filter (where day_row.attendance_status = 'OFF') as rest
    from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = sheet.id
  ) counted on true;
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

  -- Who entered each date, for the weekly site in-charge line: the first
  -- person who saved it, else the terminal that opened it.
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', sheet.work_date,
    'entered_by', public.v1_wf_saved_by(
      sheet.entered_by_auth_user_id, sheet.entered_by_terminal_id
    ),
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

-- ---------------------------------------------------------------------------
-- 4. Saving a day by hand. Unchanged for people's lines. A terminal's line
--    the app did not send stays, unless the app names it as removed.
-- ---------------------------------------------------------------------------

-- The new optional argument changes the signature; the six-argument function
-- is replaced, not kept beside it, so a call has one function to reach.
drop function if exists public.v1_wf_save_day(
  uuid, date, jsonb, bigint, text, uuid
);

create or replace function public.v1_wf_save_day(
  p_team_id uuid,
  p_work_date date,
  p_rows jsonb,
  p_expected_version bigint,
  p_change_reason text,
  p_idempotency_key uuid,
  p_removed_terminal_worker_ids uuid[] default null
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
  v_first_save boolean;
  v_day_type text := public.v1_wf_day_type(p_work_date);
  v_today date := public.v1_wf_today();
  v_reason text := nullif(btrim(coalesce(p_change_reason, '')), '');
  v_removed uuid[] := coalesce(p_removed_terminal_worker_ids, array[]::uuid[]);
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
  v_touched uuid[] := array[]::uuid[];
  v_gone uuid[] := array[]::uuid[];
  v_changed_count integer := 0;
  v_project uuid;
  v_counts jsonb;
  v_work_scope uuid;
  v_place text;
  v_found boolean;
  v_by_other boolean;
  v_notify uuid[] := array[]::uuid[];
  v_recipient uuid;
begin
  if p_work_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  -- The request is the same as before for an app that names no removed
  -- terminal line, so a retry across this release still finds its answer.
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_save_day', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'date', p_work_date, 'rows', p_rows,
      'expected', p_expected_version, 'reason', p_change_reason
    ) || case
      when p_removed_terminal_worker_ids is null then '{}'::jsonb
      else jsonb_build_object(
        'removed_terminal', to_jsonb(p_removed_terminal_worker_ids)
      )
    end
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
  -- No rows is a day when every member worked at another place (the
  -- member check below still requires everyone else).
  if jsonb_typeof(p_rows) <> 'array'
    or jsonb_array_length(p_rows) > 500
    or cardinality(v_removed) > 500
    or array_position(v_removed, null) is not null then
    raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
  end if;

  select project_id, place_key into v_project, v_place
  from public.v1_workforce_crew_profiles where team_id = p_team_id;

  -- Serialize the sheet's day, then each worker's day across every place
  -- (in one order, so two places saving the same workers cannot deadlock).
  -- A terminal's check-in takes the same locks in the same order.
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
  -- The first save by a person: a new day, or one only a terminal has
  -- written on.
  v_first_save := not v_has_sheet or v_sheet.record_version = 0;
  for v_worker in
    select distinct worker_id from (
      select (entry.value ->> 'worker_id')::uuid as worker_id
      from jsonb_array_elements(p_rows) entry
      where (entry.value ->> 'worker_id')
        ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      union
      select day_row.worker_id
      from public.v1_workforce_day_rows day_row
      where v_has_sheet and day_row.sheet_id = v_sheet.id
    ) workers
    order by worker_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'workforce_worker_day:' || v_worker::text || ':'
          || p_work_date::text, 0
      )
    );
  end loop;

  -- A reason is needed only to change or remove a row someone else saved,
  -- or to remove a terminal's line or mark it not present (checked row by
  -- row below). Adding a row never needs one.
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
    -- The first person to save a day a terminal opened enters it.
    update public.v1_workforce_day_sheets
    set entered_by_auth_user_id = coalesce(entered_by_auth_user_id, v_actor),
        entered_at = case when entered_by_auth_user_id is null
          then clock_timestamp() else entered_at end,
        last_saved_by_auth_user_id = v_actor,
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
        'work_label', 'overtime_note', 'copied', 'work_scope_id'
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
      v_work_scope := nullif(v_item ->> 'work_scope_id', '')::uuid;
      v_copied := coalesce((v_item ->> 'copied')::boolean, false);
    exception when others then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end;
    v_label := nullif(btrim(coalesce(v_item ->> 'work_label', '')), '');
    v_note := nullif(btrim(coalesce(v_item ->> 'overtime_note', '')), '');
    -- A line is sent or named as removed, never both.
    if v_worker is null or v_worker = any(v_seen)
      or v_worker = any(v_removed) then
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
    -- Every row on a project's place is on that project.
    if v_place like 'project:%' then
      v_work_project := v_project;
    end if;
    if v_work_project is not null and not exists (
      select 1 from public.v1_projects project where project.id = v_work_project
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    -- The building (or Common) belongs to the row's project.
    if v_work_scope is not null and (
      v_work_project is null
      or not exists (
        select 1 from public.v1_project_scopes scope
        where scope.id = v_work_scope and scope.project_id = v_work_project
      )
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.v1_workforce_workers worker where worker.id = v_worker
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    -- Only labour goes on attendance sheets. A staff row saved on this day
    -- before the rule may be kept as it was; no new one is accepted.
    if not public.v1_wf_is_labour(v_worker) and not exists (
      select 1 from public.v1_workforce_day_rows saved_row
      where saved_row.sheet_id = v_sheet.id
        and saved_row.worker_id = v_worker
    ) then
      raise exception 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS' using errcode = '22023';
    end if;

    -- The same worker at other places that day.
    if v_status = 'P' then
      if exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status in ('AL', 'SL', 'OL', 'UL')
      ) then
        raise exception 'V1_WORKFORCE_WORKER_ON_LEAVE_ELSEWHERE'
          using errcode = '22023';
      end if;
      if exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status = 'P'
          and other_row.start_minute < v_finish
          and v_start < other_row.finish_minute
      ) then
        raise exception 'V1_WORKFORCE_TIME_OVERLAP' using errcode = '22023';
      end if;
      if (
        select count(*) from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status = 'P'
      ) >= 3 then
        raise exception 'V1_WORKFORCE_TOO_MANY_PLACES' using errcode = '22023';
      end if;
    elsif v_status in ('AL', 'SL', 'OL', 'UL') and exists (
      select 1 from public.v1_workforce_day_rows other_row
      where other_row.worker_id = v_worker
        and other_row.work_date = p_work_date
        and other_row.sheet_id <> v_sheet.id
        and other_row.attendance_status = 'P'
    ) then
      raise exception 'V1_WORKFORCE_WORKER_PRESENT_ELSEWHERE'
        using errcode = '22023';
    end if;

    v_minutes := public.v1_wf_compute_minutes(
      v_status, v_start, v_break_start, v_break_finish, v_finish, v_day_type
    );

    select * into v_old
    from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id and day_row.worker_id = v_worker;
    v_found := found;
    v_before := case when v_found then jsonb_build_object(
      'status', v_old.attendance_status,
      'start_minute', v_old.start_minute,
      'break_start_minute', v_old.break_start_minute,
      'break_finish_minute', v_old.break_finish_minute,
      'finish_minute', v_old.finish_minute,
      'work_project_id', v_old.work_project_id,
      'work_label', v_old.work_label,
      'work_scope_id', v_old.work_scope_id
    ) end;
    v_after := jsonb_build_object(
      'status', v_status,
      'start_minute', v_start,
      'break_start_minute', v_break_start,
      'break_finish_minute', v_break_finish,
      'finish_minute', v_finish,
      'work_project_id', v_work_project,
      'work_label', v_label,
      'work_scope_id', v_work_scope
    );
    -- A row saved again unchanged keeps who saved it: a person, or the
    -- terminal.
    if v_found
      and v_before is not distinct from v_after
      and v_old.overtime_note is not distinct from v_note then
      continue;
    end if;
    -- Changing a row someone else saved needs a reason, is logged and tells
    -- them. A terminal's line is changed freely while the labourer stays
    -- Present (times, building); marking them not present needs a reason.
    v_by_other := v_found
      and v_before is distinct from v_after
      and case
        when v_old.updated_by_auth_user_id is null then v_status <> 'P'
        else v_old.updated_by_auth_user_id <> v_actor
      end;
    if v_by_other and v_reason is null then
      raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED'
        using errcode = '22023';
    end if;

    -- From here the line is this person's; it keeps the terminal it came
    -- from (terminal_id).
    insert into public.v1_workforce_day_rows (
      sheet_id, team_id, work_date, worker_id, attendance_status,
      start_minute, break_start_minute, break_finish_minute, finish_minute,
      work_project_id, work_scope_id, work_label, overtime_note, copied,
      worked_minutes, regular_minutes, normal_overtime_minutes,
      holiday_overtime_minutes, updated_by_auth_user_id
    ) values (
      v_sheet.id, p_team_id, p_work_date, v_worker, v_status,
      v_start, v_break_start, v_break_finish, v_finish,
      v_work_project, v_work_scope, v_label, v_note, v_copied,
      v_minutes[1], v_minutes[2], v_minutes[3], v_minutes[4], v_actor
    )
    on conflict (sheet_id, worker_id) do update
    set attendance_status = excluded.attendance_status,
        start_minute = excluded.start_minute,
        break_start_minute = excluded.break_start_minute,
        break_finish_minute = excluded.break_finish_minute,
        finish_minute = excluded.finish_minute,
        work_project_id = excluded.work_project_id,
        work_scope_id = excluded.work_scope_id,
        work_label = excluded.work_label,
        overtime_note = excluded.overtime_note,
        copied = excluded.copied,
        changed_after_entry = public.v1_workforce_day_rows.changed_after_entry
          or v_by_other,
        worked_minutes = excluded.worked_minutes,
        regular_minutes = excluded.regular_minutes,
        normal_overtime_minutes = excluded.normal_overtime_minutes,
        holiday_overtime_minutes = excluded.holiday_overtime_minutes,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp();

    if v_by_other then
      if v_old.updated_by_auth_user_id is not null then
        v_notify := v_notify || v_old.updated_by_auth_user_id;
      end if;
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_worker, v_before, v_after, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    end if;
  end loop;

  -- Every current member must be on the day, unless they are recorded
  -- present, resting or on leave at another place that day.
  if v_place is null and exists (
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
          and other_row.attendance_status in (
            'P', 'OFF', 'AL', 'SL', 'OL', 'UL'
          )
      )
  ) then
    raise exception 'V1_WORKFORCE_DAY_UNMARKED' using errcode = '22023';
  end if;

  -- Rows left out of this save are removed and, when the row belonged to
  -- someone else, logged. A terminal's line that was left out stays: the app
  -- may simply not have seen it yet. It goes only when the app names it as
  -- removed, with a reason.
  for v_old in
    select * from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id
      and not (day_row.worker_id = any(v_seen))
  loop
    if v_old.updated_by_auth_user_id is null then
      if not (v_old.worker_id = any(v_removed)) then
        continue;
      end if;
      if v_reason is null then
        raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED'
          using errcode = '22023';
      end if;
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_old.worker_id,
        jsonb_build_object('status', v_old.attendance_status),
        null, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    elsif v_old.updated_by_auth_user_id <> v_actor then
      if v_reason is null then
        raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED'
          using errcode = '22023';
      end if;
      v_notify := v_notify || v_old.updated_by_auth_user_id;
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
    v_touched := v_touched || v_old.worker_id;
    v_gone := v_gone || v_old.worker_id;
    delete from public.v1_workforce_day_rows where id = v_old.id;
  end loop;

  -- A labourer a person removed from the day is not added to it again by a
  -- terminal.
  if cardinality(v_gone) > 0 then
    update public.v1_workforce_day_sheets sheet
    set hand_removed_worker_ids = array(
      select distinct removed.worker_id
      from unnest(sheet.hand_removed_worker_ids || v_gone)
        as removed(worker_id)
      order by removed.worker_id
    )
    where sheet.id = v_sheet.id;
  end if;

  -- Normal hours and overtime over each worker's whole day.
  for v_worker in
    select distinct worker_id
    from unnest(v_seen || v_touched) as touched(worker_id)
    order by worker_id
  loop
    perform public.v1_wf_recompute_worker_day(v_worker, p_work_date);
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

  if v_first_save then
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
    -- Everyone whose rows were changed or removed is told once.
    for v_recipient in
      select distinct recipient from unnest(v_notify) as changed(recipient)
      where recipient <> v_actor
    loop
      perform public.v1_wf_notify(
        v_recipient, 'workforce_attendance_day_changed',
        'workforce_day_sheet', v_sheet.id, v_project
      );
    end loop;
  end if;

  perform public.v1_write_audit_event(
    case when v_first_save then 'workforce_day_entered'
      else 'workforce_day_updated' end,
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
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Matching a terminal user ID to a labourer (HR/PRO and Admin).
-- ---------------------------------------------------------------------------

-- HR/PRO and Admin, each with the worker-management capability.
create or replace function public.v1_wf_terminal_users_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not public.v1_current_actor_is_active()
    or public.v1_current_exact_role() not in ('admin', 'pr')
    or not public.v1_wf_allowed('workforce.workers.manage') then
    raise exception 'V1_WORKFORCE_TERMINAL_USERS_DENIED'
      using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

-- Every active labourer with the ID their number gives and the ID confirmed
-- for them, and every ID terminals have sent that is matched to nobody.
create or replace function public.v1_wf_list_terminal_users()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.v1_wf_terminal_users_actor();
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.terminal_users.v1',
    'labourers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'worker_id', worker.id,
        'number', worker.worker_number,
        'name', worker.full_name,
        'designation', worker.designation,
        'status', worker.current_status,
        -- The ID this labourer's number gives.
        'number_id', public.v1_wf_terminal_number_id(worker.worker_number),
        -- The ID confirmed for them, when one is.
        'device_user_id', match.device_user_id,
        'follows_number', match.follows_number,
        'confirmed_by',
          public.v1_wf_display_name(match.confirmed_by_auth_user_id),
        'confirmed_at', match.confirmed_at
      ) order by lower(worker.worker_number), worker.id)
      from public.v1_workforce_workers worker
      left join public.v1_workforce_terminal_users match
        on match.worker_id = worker.id and match.ended_at is null
      where match.id is not null
        or (
          worker.current_status = 'active'
          and public.v1_wf_is_labour(worker.id)
        )
    ), '[]'::jsonb),
    'unmatched', coalesce((
      select jsonb_agg(jsonb_build_object(
        'device_user_id', seen.user_key,
        'check_ins', seen.punches,
        'first_at', seen.first_at,
        'last_at', seen.last_at,
        -- The one labourer whose number gives this ID, when free to match.
        'proposed_worker_id', (
          select case when count(*) = 1 then (array_agg(worker.id))[1] end
          from public.v1_workforce_workers worker
          where public.v1_wf_terminal_number_id(worker.worker_number)
              = seen.user_key
            and worker.current_status = 'active'
            and public.v1_wf_is_labour(worker.id)
            and not exists (
              select 1 from public.v1_workforce_terminal_users taken
              where taken.worker_id = worker.id and taken.ended_at is null
            )
        )
      ) order by seen.last_at desc, seen.user_key)
      from (
        -- Check-ins of the last 90 days, the newest 500 IDs.
        select
          public.v1_wf_terminal_user_key(punch.device_user_id) as user_key,
          count(*) as punches,
          min(punch.punched_at_local) as first_at,
          max(punch.punched_at_local) as last_at
        from public.v1_workforce_terminal_punches punch
        where punch.work_date >= public.v1_wf_today() - 90
          and public.v1_wf_terminal_user_key(punch.device_user_id) is not null
          and not exists (
            select 1 from public.v1_workforce_terminal_users match
            where match.device_user_id
                = public.v1_wf_terminal_user_key(punch.device_user_id)
              and match.ended_at is null
          )
        group by 1
        order by max(punch.punched_at_local) desc
        limit 500
      ) seen
    ), '[]'::jsonb)
  );
end;
$$;

-- Confirms terminal user IDs for labourers: [{device_user_id, worker_id}].
-- A match already confirmed for the same labourer is left as it is. Each new
-- match writes an audit event. Nothing already on a day changes.
create or replace function public.v1_wf_confirm_terminal_users(
  p_matches jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_terminal_users_actor();
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_item jsonb;
  v_key text;
  v_worker public.v1_workforce_workers%rowtype;
  v_match public.v1_workforce_terminal_users%rowtype;
  v_follows boolean;
  v_seen_keys text[] := array[]::text[];
  v_seen_workers uuid[] := array[]::uuid[];
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_confirm_terminal_users', p_idempotency_key,
    jsonb_build_object('matches', p_matches)
  );
  if v_existing is not null then
    return public.v1_wf_list_terminal_users();
  end if;
  if p_matches is null
    or jsonb_typeof(p_matches) <> 'array'
    or jsonb_array_length(p_matches) not between 1 and 500 then
    raise exception 'V1_WORKFORCE_TERMINAL_USER_INVALID'
      using errcode = '22023';
  end if;

  -- One change to the matches at a time.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workforce_terminal_users', 0)
  );

  for v_item in select value from jsonb_array_elements(p_matches) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'V1_WORKFORCE_TERMINAL_USER_INVALID'
        using errcode = '22023';
    end if;
    perform public.v1_assert_object_keys(
      v_item, array['device_user_id', 'worker_id'],
      'confirm_workforce_terminal_user'
    );
    v_key := public.v1_wf_terminal_user_key(v_item ->> 'device_user_id');
    if v_key is null
      or (v_item ->> 'worker_id') is null
      or (v_item ->> 'worker_id')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then
      raise exception 'V1_WORKFORCE_TERMINAL_USER_INVALID'
        using errcode = '22023';
    end if;
    select * into v_worker
    from public.v1_workforce_workers worker
    where worker.id = (v_item ->> 'worker_id')::uuid;
    if not found then
      raise exception 'V1_WORKFORCE_WORKER_NOT_FOUND' using errcode = 'P0002';
    end if;
    -- An ID or a labourer named twice in one request is a mistake.
    if v_key = any(v_seen_keys) or v_worker.id = any(v_seen_workers) then
      raise exception 'V1_WORKFORCE_TERMINAL_USER_INVALID'
        using errcode = '22023';
    end if;
    v_seen_keys := v_seen_keys || v_key;
    v_seen_workers := v_seen_workers || v_worker.id;
    -- Labour only, and only labourers who are active.
    if not public.v1_wf_is_labour(v_worker.id) then
      raise exception 'V1_WORKFORCE_TERMINAL_USER_STAFF'
        using errcode = '22023';
    end if;
    if v_worker.current_status <> 'active' then
      raise exception 'V1_WORKFORCE_TERMINAL_USER_NOT_ACTIVE'
        using errcode = '22023';
    end if;

    select * into v_match
    from public.v1_workforce_terminal_users match
    where match.device_user_id = v_key and match.ended_at is null;
    if found then
      if v_match.worker_id = v_worker.id then
        continue;
      end if;
      -- The ID belongs to another labourer: end that match first.
      raise exception 'V1_WORKFORCE_TERMINAL_USER_TAKEN'
        using errcode = '22023';
    end if;
    if exists (
      select 1 from public.v1_workforce_terminal_users match
      where match.worker_id = v_worker.id and match.ended_at is null
    ) then
      -- The labourer has another ID: end that match first.
      raise exception 'V1_WORKFORCE_TERMINAL_WORKER_MATCHED'
        using errcode = '22023';
    end if;

    v_follows := coalesce(
      public.v1_wf_terminal_number_id(v_worker.worker_number) = v_key, false
    );
    insert into public.v1_workforce_terminal_users (
      device_user_id, worker_id, follows_number,
      confirmed_by_auth_user_id, confirmed_by_role
    ) values (v_key, v_worker.id, v_follows, v_actor, v_role);

    -- One event per labourer. They share one request, so they carry no
    -- request key (the audit log allows one event of a kind per key).
    perform public.v1_write_audit_event(
      'workforce_terminal_user_confirmed', 'workforce_worker', v_worker.id,
      null, null,
      jsonb_build_object(
        'device_user_id', v_key,
        'worker_number', v_worker.worker_number,
        'follows_number', v_follows
      ),
      null, null
    );
  end loop;

  perform public.v1_complete_idempotency(
    'v1_wf_confirm_terminal_users', p_idempotency_key,
    jsonb_build_object('matches', jsonb_array_length(p_matches))
  );
  return public.v1_wf_list_terminal_users();
end;
$$;

-- Ends a wrong match, with a reason. From then on that ID's check-ins are
-- only listed. Lines already on a day stay; they are corrected by hand.
create or replace function public.v1_wf_end_terminal_user(
  p_device_user_id text,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_terminal_users_actor();
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_key text := public.v1_wf_terminal_user_key(p_device_user_id);
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_match public.v1_workforce_terminal_users%rowtype;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_end_terminal_user', p_idempotency_key,
    jsonb_build_object('device_user_id', p_device_user_id, 'reason', p_reason)
  );
  if v_existing is not null then
    return public.v1_wf_list_terminal_users();
  end if;
  if v_key is null then
    raise exception 'V1_WORKFORCE_TERMINAL_USER_INVALID'
      using errcode = '22023';
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'V1_WORKFORCE_REASON_REQUIRED' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workforce_terminal_users', 0)
  );
  select * into v_match
  from public.v1_workforce_terminal_users match
  where match.device_user_id = v_key and match.ended_at is null
  for update;
  if not found then
    raise exception 'V1_WORKFORCE_TERMINAL_USER_NOT_FOUND'
      using errcode = 'P0002';
  end if;
  update public.v1_workforce_terminal_users
  set ended_by_auth_user_id = v_actor,
      ended_by_role = v_role,
      ended_at = clock_timestamp(),
      end_reason = v_reason
  where id = v_match.id;

  perform public.v1_write_audit_event(
    'workforce_terminal_user_ended', 'workforce_worker', v_match.worker_id,
    null,
    jsonb_build_object('device_user_id', v_key),
    null, v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_end_terminal_user', p_idempotency_key,
    jsonb_build_object('device_user_id', v_key)
  );
  return public.v1_wf_list_terminal_users();
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Watching or adding (operator, service role).
-- ---------------------------------------------------------------------------

-- A terminal as the operator functions return it.
create or replace function public.v1_wf_terminal_json(p_terminal_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', terminal.id,
    'serial_number', terminal.serial_number,
    'terminal_name', terminal.terminal_name,
    'place_key', place.place_key,
    'is_active', terminal.is_active,
    'attendance_mode', terminal.attendance_mode,
    'utc_offset_minutes', terminal.utc_offset_minutes,
    'resend_all_requested', terminal.resend_all_requested,
    'device_name', terminal.device_name,
    'firmware_version', terminal.firmware_version,
    'push_version', terminal.push_version,
    'first_seen_at', terminal.first_seen_at,
    'last_seen_at', terminal.last_seen_at,
    'last_handshake_at', terminal.last_handshake_at,
    'last_punch_received_at', terminal.last_punch_received_at,
    'record_version', terminal.record_version
  )
  from public.v1_workforce_terminals terminal
  left join public.v1_workforce_crew_profiles place
    on place.team_id = terminal.team_id
  where terminal.id = p_terminal_id;
$$;

-- Registers a terminal by its serial number, or renames, moves and
-- re-activates one already registered. p_place_key is an attendance place
-- ("location:workshop", "project:<id>") or null for no place yet. A terminal
-- given another place (or none) goes back to watching.
create or replace function public.v1_wf_register_terminal(
  p_serial_number text,
  p_terminal_name text,
  p_place_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_name text := nullif(btrim(coalesce(p_terminal_name, '')), '');
  v_place text := nullif(lower(btrim(coalesce(p_place_key, ''))), '');
  v_team uuid;
  v_id uuid;
begin
  if v_serial is null then
    raise exception 'V1_WORKFORCE_TERMINAL_SERIAL_INVALID'
      using errcode = '22023';
  end if;
  if v_name is null or char_length(v_name) > 80 then
    raise exception 'V1_WORKFORCE_TERMINAL_NAME_INVALID'
      using errcode = '22023';
  end if;
  if v_place is not null then
    select place.team_id into v_team
    from public.v1_workforce_crew_profiles place
    where place.place_key = v_place and place.is_active;
    if not found then
      raise exception 'V1_WORKFORCE_TERMINAL_PLACE_NOT_FOUND'
        using errcode = '22023';
    end if;
  end if;

  insert into public.v1_workforce_terminals (
    serial_number, terminal_name, team_id
  ) values (v_serial, v_name, v_team)
  on conflict (serial_number) do update
  set terminal_name = excluded.terminal_name,
      attendance_mode = case
        when public.v1_workforce_terminals.team_id
          is distinct from excluded.team_id then 'watch'
        else public.v1_workforce_terminals.attendance_mode
      end,
      team_id = excluded.team_id,
      is_active = true,
      record_version = public.v1_workforce_terminals.record_version + 1,
      updated_at = clock_timestamp()
  returning id into v_id;

  return public.v1_wf_terminal_json(v_id);
end;
$$;

-- Switches one terminal between watching ('watch') and adding ('add'). Only
-- a terminal that serves a place can add. Check-ins already stored are not
-- applied again: adding starts with the next check-in.
create or replace function public.v1_wf_set_terminal_mode(
  p_serial_number text,
  p_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_terminal public.v1_workforce_terminals%rowtype;
begin
  if v_serial is null or p_mode is null or p_mode not in ('watch', 'add') then
    raise exception 'V1_WORKFORCE_TERMINAL_INVALID' using errcode = '22023';
  end if;
  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.serial_number = v_serial
  for update;
  if not found then
    raise exception 'V1_WORKFORCE_TERMINAL_NOT_FOUND' using errcode = 'P0002';
  end if;
  if p_mode = 'add' and v_terminal.team_id is null then
    raise exception 'V1_WORKFORCE_TERMINAL_PLACE_REQUIRED'
      using errcode = '22023';
  end if;
  if v_terminal.attendance_mode <> p_mode then
    update public.v1_workforce_terminals terminal
    set attendance_mode = p_mode,
        record_version = terminal.record_version + 1,
        updated_at = clock_timestamp()
    where terminal.id = v_terminal.id;
  end if;
  return public.v1_wf_terminal_json(v_terminal.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. What a check-in does to the place's day.
-- ---------------------------------------------------------------------------

-- What the rules find for a matched, active labourer whose first check-in at
-- a place was at p_first_minute: 'add', or why no line is added. Read again
-- under the day's locks before a line is written.
create or replace function public.v1_wf_terminal_finding(
  p_team_id uuid,
  p_work_date date,
  p_worker_id uuid,
  p_first_minute integer
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_place public.v1_workforce_crew_profiles%rowtype;
begin
  select * into v_place
  from public.v1_workforce_crew_profiles profile
  where profile.team_id = p_team_id;
  if not found then
    return 'no_place';
  end if;
  -- Already on that place's day, by hand or from a terminal.
  if exists (
    select 1 from public.v1_workforce_day_rows day_row
    where day_row.team_id = p_team_id
      and day_row.work_date = p_work_date
      and day_row.worker_id = p_worker_id
  ) then
    return 'on_day';
  end if;
  -- A person removed them from that day.
  if exists (
    select 1 from public.v1_workforce_day_sheets sheet
    where sheet.team_id = p_team_id
      and sheet.work_date = p_work_date
      and p_worker_id = any(sheet.hand_removed_worker_ids)
  ) then
    return 'removed_by_hand';
  end if;
  -- The check-in is more than seven days old.
  if p_work_date < public.v1_wf_today() - 7 then
    return 'late';
  end if;
  if public.v1_wf_month_locked(p_team_id, p_work_date) then
    return 'month_confirmed';
  end if;
  -- A rest day or public holiday: every hour would be holiday overtime.
  if public.v1_wf_day_type(p_work_date) = 'holiday' then
    return 'rest_day';
  end if;
  -- A line at another place that day.
  if exists (
    select 1 from public.v1_workforce_day_rows other_row
    where other_row.worker_id = p_worker_id
      and other_row.work_date = p_work_date
      and other_row.team_id <> p_team_id
  ) then
    return 'elsewhere';
  end if;
  -- More than two hours before the usual start, or after the usual finish.
  if p_first_minute < v_place.shift_start_minute - 120
    or p_first_minute > v_place.shift_finish_minute then
    return 'outside_shift';
  end if;
  return 'add';
end;
$$;

-- Decides what a terminal's check-ins on one day do, for every user ID (or
-- the ones given), and adds the missing lines when the terminal adds.
-- Returns how many lines it added. It only ever adds a line: it never
-- changes or removes one, and never touches the sheet's version.
create or replace function public.v1_wf_terminal_apply(
  p_terminal_id uuid,
  p_work_date date,
  p_device_user_ids text[] default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_terminal public.v1_workforce_terminals%rowtype;
  v_place public.v1_workforce_crew_profiles%rowtype;
  v_has_place boolean := false;
  v_adding boolean;
  v_today date := public.v1_wf_today();
  v_keys text[];
  v_start integer;
  v_finish integer;
  v_break_start integer;
  v_break_finish integer;
  v_scope uuid;
  v_minutes integer[];
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_day_locked boolean := false;
  v_lock_timeout text;
  v_item record;
  v_finding text;
  v_line_added boolean;
  v_added integer := 0;
begin
  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = p_terminal_id;
  if not found or p_work_date is null then
    return 0;
  end if;

  -- The place the terminal serves now: an open attendance place.
  if v_terminal.team_id is not null then
    select profile.* into v_place
    from public.v1_workforce_crew_profiles profile
    join public.v1_workforce_teams team on team.id = profile.team_id
    where profile.team_id = v_terminal.team_id
      and profile.place_key is not null
      and profile.is_active
      and team.is_active;
    v_has_place := found;
  end if;
  v_adding := v_has_place
    and v_terminal.is_active
    and v_terminal.attendance_mode = 'add';

  if p_device_user_ids is not null then
    select coalesce(array_agg(distinct public.v1_wf_terminal_user_key(given.id)),
      array[]::text[])
    into v_keys
    from unnest(p_device_user_ids) as given(id)
    where public.v1_wf_terminal_user_key(given.id) is not null;
  end if;

  if v_has_place then
    -- The usual shift with its break, never more than 8 hours: what Add
    -- workers gives. A break that does not sit inside those hours is left
    -- out.
    v_start := v_place.shift_start_minute;
    v_break_start := v_place.break_start_minute;
    v_break_finish := v_place.break_finish_minute;
    if v_break_start is not null and (
      v_break_start <= v_start
      or v_break_finish >= v_place.shift_finish_minute
      or v_break_start - v_start >= 480
    ) then
      v_break_start := null;
      v_break_finish := null;
    end if;
    v_finish := least(
      v_place.shift_finish_minute,
      v_start + 480 + coalesce(v_break_finish - v_break_start, 0)
    );
    v_minutes := public.v1_wf_compute_minutes(
      'P', v_start, v_break_start, v_break_finish, v_finish, 'work'
    );
    -- The building new lines start with: the project's only building, else
    -- its only scope, else none (left for the keeper).
    if v_place.project_id is not null then
      select case
        when count(*) filter (where scope.scope_kind <> 'common') = 1
          then (array_agg(scope.id)
            filter (where scope.scope_kind <> 'common'))[1]
        when count(*) filter (where scope.scope_kind <> 'common') = 0
          and count(*) = 1 then (array_agg(scope.id))[1]
      end
      into v_scope
      from public.v1_project_scopes scope
      where scope.project_id = v_place.project_id and scope.is_active;
    end if;
  end if;

  -- Labourers in one order, so two terminals (or a terminal and a person)
  -- taking the same labourers' days cannot deadlock.
  for v_item in
    select
      seen.user_key,
      seen.first_at,
      seen.last_at,
      seen.punches,
      seen.suspect,
      match.worker_id,
      worker.current_status,
      decided.id as decided_id,
      -- Added before, for the labourer the ID is still matched to.
      coalesce(decided.added, false)
        and decided.worker_id is not distinct from match.worker_id
        as already_added
    from (
      select
        public.v1_wf_terminal_user_key(punch.device_user_id) as user_key,
        min(punch.punched_at_local) as first_at,
        max(punch.punched_at_local) as last_at,
        count(*)::integer as punches,
        bool_or(punch.clock_suspect) as suspect
      from public.v1_workforce_terminal_punches punch
      where punch.terminal_id = p_terminal_id
        and punch.work_date = p_work_date
      group by 1
    ) seen
    left join public.v1_workforce_terminal_users match
      on match.device_user_id = seen.user_key and match.ended_at is null
    left join public.v1_workforce_workers worker on worker.id = match.worker_id
    left join public.v1_workforce_terminal_days decided
      on decided.terminal_id = p_terminal_id
      and decided.work_date = p_work_date
      and decided.device_user_id = seen.user_key
    where seen.user_key is not null
      and (v_keys is null or seen.user_key = any(v_keys))
    order by match.worker_id nulls last, seen.user_key
  loop
    -- A line this terminal added stays decided; only its times move on.
    -- (If the ID has since been matched to someone else, the day is decided
    -- again for them; the line already added stays for a person to correct.)
    if v_item.already_added then
      update public.v1_workforce_terminal_days day
      set first_punched_at_local = v_item.first_at,
          last_punched_at_local = v_item.last_at,
          punch_count = v_item.punches
      where day.id = v_item.decided_id;
      continue;
    end if;

    v_line_added := false;
    v_finding := case
      when not v_has_place then 'no_place'
      when v_item.worker_id is null then 'unmatched'
      -- A wrong terminal clock: its date and times cannot be relied on.
      when v_item.suspect or p_work_date > v_today then 'clock'
      when not public.v1_wf_is_labour(v_item.worker_id) then 'staff'
      when v_item.current_status <> 'active' then 'not_active'
      else public.v1_wf_terminal_finding(
        v_place.team_id, p_work_date, v_item.worker_id,
        public.v1_wf_terminal_minute(v_item.first_at)
      )
    end;

    if v_finding = 'add' and v_adding then
      -- The same locks v1_wf_save_day takes, in the same order: the place's
      -- day, then the labourer's day. The month comes first so that a
      -- confirmation cannot slip in between. A save that holds the day for
      -- more than two seconds does not hold the terminal: the check-in is
      -- kept and the line is tried again.
      if not v_day_locked then
        v_lock_timeout := current_setting('lock_timeout', true);
        perform set_config('lock_timeout', '2000', true);
        perform pg_catalog.pg_advisory_xact_lock(
          pg_catalog.hashtextextended(
            'workforce_month:' || v_place.team_id::text || ':'
              || date_trunc('month', p_work_date)::date::text, 0
          )
        );
        perform pg_catalog.pg_advisory_xact_lock(
          pg_catalog.hashtextextended(
            'workforce_day:' || v_place.team_id::text || ':'
              || p_work_date::text, 0
          )
        );
        v_day_locked := true;
      end if;
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          'workforce_worker_day:' || v_item.worker_id::text || ':'
            || p_work_date::text, 0
        )
      );
      -- Nothing can change under these locks: decide again, then write.
      v_finding := public.v1_wf_terminal_finding(
        v_place.team_id, p_work_date, v_item.worker_id,
        public.v1_wf_terminal_minute(v_item.first_at)
      );
      if v_finding = 'add' then
        select * into v_sheet
        from public.v1_workforce_day_sheets sheet
        where sheet.team_id = v_place.team_id
          and sheet.work_date = p_work_date;
        if not found then
          -- A day a terminal opens is at version 0: no person has saved it.
          insert into public.v1_workforce_day_sheets (
            team_id, work_date, entered_by_auth_user_id,
            entered_by_terminal_id, entered_at, entered_late,
            last_saved_by_auth_user_id, last_saved_at, record_version
          ) values (
            v_place.team_id, p_work_date, null, v_terminal.id,
            clock_timestamp(), p_work_date < v_today, null,
            clock_timestamp(), 0
          )
          returning * into v_sheet;
        end if;
        insert into public.v1_workforce_day_rows (
          sheet_id, team_id, work_date, worker_id, attendance_status,
          start_minute, break_start_minute, break_finish_minute,
          finish_minute, work_project_id, work_scope_id, copied,
          worked_minutes, regular_minutes, normal_overtime_minutes,
          holiday_overtime_minutes, updated_by_auth_user_id, terminal_id
        ) values (
          v_sheet.id, v_place.team_id, p_work_date, v_item.worker_id, 'P',
          v_start, v_break_start, v_break_finish, v_finish,
          v_place.project_id, v_scope, false,
          v_minutes[1], v_minutes[2], v_minutes[3], v_minutes[4],
          null, v_terminal.id
        );
        perform public.v1_wf_recompute_worker_day(
          v_item.worker_id, p_work_date
        );
        v_line_added := true;
        v_added := v_added + 1;
      end if;
    end if;

    insert into public.v1_workforce_terminal_days as day (
      terminal_id, work_date, device_user_id, team_id, worker_id,
      first_punched_at_local, last_punched_at_local, punch_count,
      finding, added, watching, decided_at
    ) values (
      p_terminal_id, p_work_date, v_item.user_key,
      case when v_has_place then v_place.team_id end, v_item.worker_id,
      v_item.first_at, v_item.last_at, v_item.punches,
      v_finding, v_line_added, not v_adding, clock_timestamp()
    )
    on conflict (terminal_id, work_date, device_user_id) do update
    set team_id = excluded.team_id,
        worker_id = excluded.worker_id,
        first_punched_at_local = excluded.first_punched_at_local,
        last_punched_at_local = excluded.last_punched_at_local,
        punch_count = excluded.punch_count,
        finding = excluded.finding,
        added = excluded.added,
        watching = excluded.watching,
        decided_at = excluded.decided_at;
  end loop;

  if v_day_locked then
    perform set_config('lock_timeout', coalesce(v_lock_timeout, '0'), true);
  end if;
  return v_added;
end;
$$;

-- Check-ins that are more than seven days old or dated in the future never
-- add a line. They are noted in one statement, however many there are, so a
-- terminal sending months of stored check-ins is answered quickly.
create or replace function public.v1_wf_terminal_note_old(
  p_terminal_id uuid,
  p_received_at timestamptz
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_terminal public.v1_workforce_terminals%rowtype;
  v_team uuid;
  v_adding boolean;
  v_count integer;
begin
  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = p_terminal_id;
  if not found then
    return 0;
  end if;
  select profile.team_id into v_team
  from public.v1_workforce_crew_profiles profile
  join public.v1_workforce_teams team on team.id = profile.team_id
  where profile.team_id = v_terminal.team_id
    and profile.place_key is not null
    and profile.is_active
    and team.is_active;
  v_adding := v_team is not null
    and v_terminal.is_active
    and v_terminal.attendance_mode = 'add';

  insert into public.v1_workforce_terminal_days as day (
    terminal_id, work_date, device_user_id, team_id, worker_id,
    first_punched_at_local, last_punched_at_local, punch_count,
    finding, added, watching, decided_at
  )
  select
    p_terminal_id, seen.work_date, seen.user_key, v_team, match.worker_id,
    seen.first_at, seen.last_at, seen.punches,
    case
      when v_team is null then 'no_place'
      when match.worker_id is null then 'unmatched'
      when seen.suspect or seen.work_date > v_today then 'clock'
      else 'late'
    end,
    false, not v_adding, clock_timestamp()
  from (
    select
      punch.work_date,
      public.v1_wf_terminal_user_key(punch.device_user_id) as user_key,
      min(punch.punched_at_local) as first_at,
      max(punch.punched_at_local) as last_at,
      count(*)::integer as punches,
      bool_or(punch.clock_suspect) as suspect
    from public.v1_workforce_terminal_punches punch
    where punch.terminal_id = p_terminal_id
      and (punch.work_date < v_today - 7 or punch.work_date > v_today)
      and (
        punch.work_date,
        public.v1_wf_terminal_user_key(punch.device_user_id)
      ) in (
        select
          fresh.work_date,
          public.v1_wf_terminal_user_key(fresh.device_user_id)
        from public.v1_workforce_terminal_punches fresh
        where fresh.terminal_id = p_terminal_id
          and fresh.received_at = p_received_at
          and (fresh.work_date < v_today - 7 or fresh.work_date > v_today)
      )
    group by 1, 2
  ) seen
  left join public.v1_workforce_terminal_users match
    on match.device_user_id = seen.user_key and match.ended_at is null
  where seen.user_key is not null
  on conflict (terminal_id, work_date, device_user_id) do update
  set first_punched_at_local = excluded.first_punched_at_local,
      last_punched_at_local = excluded.last_punched_at_local,
      punch_count = excluded.punch_count,
      -- A line the terminal added when the day was recent stays decided.
      team_id = case when day.added then day.team_id else excluded.team_id end,
      worker_id = case when day.added then day.worker_id
        else excluded.worker_id end,
      finding = case when day.added then day.finding else excluded.finding end,
      watching = case when day.added then day.watching
        else excluded.watching end,
      decided_at = case when day.added then day.decided_at
        else excluded.decided_at end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Marks a day's check-ins as not applied, so they are tried again with the
-- terminal's next upload.
create or replace function public.v1_wf_terminal_mark_failed(
  p_terminal_id uuid,
  p_work_date date,
  p_device_user_ids text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.v1_workforce_terminal_days as day (
    terminal_id, work_date, device_user_id, team_id, worker_id,
    first_punched_at_local, last_punched_at_local, punch_count,
    finding, added, watching, decided_at
  )
  select
    p_terminal_id, p_work_date, seen.user_key, null, null,
    seen.first_at, seen.last_at, seen.punches,
    'error', false, false, clock_timestamp()
  from (
    select
      public.v1_wf_terminal_user_key(punch.device_user_id) as user_key,
      min(punch.punched_at_local) as first_at,
      max(punch.punched_at_local) as last_at,
      count(*)::integer as punches
    from public.v1_workforce_terminal_punches punch
    where punch.terminal_id = p_terminal_id
      and punch.work_date = p_work_date
      and punch.device_user_id = any(p_device_user_ids)
    group by 1
  ) seen
  where seen.user_key is not null
  on conflict (terminal_id, work_date, device_user_id) do update
  set first_punched_at_local = excluded.first_punched_at_local,
      last_punched_at_local = excluded.last_punched_at_local,
      punch_count = excluded.punch_count,
      finding = case when day.added then day.finding else 'error' end,
      decided_at = case when day.added then day.decided_at
        else excluded.decided_at end;
end;
$$;

-- Runs after a terminal's check-ins are stored. It never raises: a line
-- that could not be added leaves the check-in stored, is marked for another
-- try and is counted, so the terminal is still told "OK".
create or replace function public.v1_wf_terminal_after_punches(
  p_terminal_id uuid,
  p_received_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_started timestamptz := clock_timestamp();
  v_day record;
  v_added integer := 0;
  v_failed integer := 0;
begin
  begin
    perform public.v1_wf_terminal_note_old(p_terminal_id, p_received_at);
  exception when others then
    v_failed := v_failed + 1;
    raise warning 'V1_WORKFORCE_TERMINAL_NOTE_FAILED: %', sqlerrm;
  end;

  -- The last eight days, oldest first.
  for v_day in
    select
      punch.work_date,
      array_agg(distinct punch.device_user_id) as users
    from public.v1_workforce_terminal_punches punch
    where punch.terminal_id = p_terminal_id
      and punch.received_at = p_received_at
      and punch.work_date between v_today - 7 and v_today
    group by punch.work_date
    order by punch.work_date
  loop
    begin
      v_added := v_added + public.v1_wf_terminal_apply(
        p_terminal_id, v_day.work_date, v_day.users
      );
    exception when others then
      v_failed := v_failed + 1;
      raise warning 'V1_WORKFORCE_TERMINAL_APPLY_FAILED % %: %',
        p_terminal_id, v_day.work_date, sqlerrm;
      begin
        perform public.v1_wf_terminal_mark_failed(
          p_terminal_id, v_day.work_date, v_day.users
        );
      exception when others then
        raise warning 'V1_WORKFORCE_TERMINAL_MARK_FAILED: %', sqlerrm;
      end;
    end;
  end loop;

  -- Lines that could not be added by an earlier upload are tried again
  -- (those that failed just now wait for the next one).
  for v_day in
    select
      day.work_date,
      array_agg(day.device_user_id) as users
    from public.v1_workforce_terminal_days day
    where day.terminal_id = p_terminal_id
      and day.finding = 'error'
      and day.work_date between v_today - 7 and v_today
      and day.decided_at < v_started
    group by day.work_date
    order by day.work_date
  loop
    begin
      v_added := v_added + public.v1_wf_terminal_apply(
        p_terminal_id, v_day.work_date, v_day.users
      );
    exception when others then
      v_failed := v_failed + 1;
      raise warning 'V1_WORKFORCE_TERMINAL_RETRY_FAILED % %: %',
        p_terminal_id, v_day.work_date, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('added', v_added, 'failed', v_failed);
end;
$$;

-- Attendance lines from a terminal. Each line is {raw, pin, time, state,
-- verify, work_code}. A line already held is counted as a duplicate; a line
-- that cannot be read is kept in v1_workforce_terminal_rejects. The whole
-- call stores or keeps every line, or fails as a whole. Check-ins stored for
-- the first time are then put to the place's day (v1_wf_terminal_apply); a
-- failure there never fails the call.
create or replace function public.v1_wf_terminal_punches(
  p_serial_number text,
  p_stamp text,
  p_lines jsonb,
  p_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_details jsonb := public.v1_wf_terminal_details(p_details);
  v_gate record;
  v_terminal public.v1_workforce_terminals%rowtype;
  v_now timestamptz := clock_timestamp();
  v_stamp text := case when p_stamp ~ '^[0-9]{1,18}$' then p_stamp end;
  v_received integer := 0;
  v_valid integer := 0;
  v_stored integer := 0;
  v_rejected integer := 0;
  v_future integer := 0;
  v_applied jsonb := '{}'::jsonb;
begin
  select * into v_gate from public.v1_wf_terminal_gate(p_serial_number);
  if v_gate.outcome <> 'ok' then
    if v_gate.outcome <> 'invalid' then
      perform public.v1_wf_terminal_note(
        v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', v_gate.outcome,
        0, 0, 0, 0, v_details
      );
    end if;
    return jsonb_build_object('outcome', v_gate.outcome);
  end if;
  if p_lines is null
    or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) > 50000 then
    perform public.v1_wf_terminal_note(
      v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', 'invalid',
      0, 0, 0, 0, v_details
    );
    return jsonb_build_object('outcome', 'invalid');
  end if;

  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = v_gate.terminal_id;
  v_received := jsonb_array_length(p_lines);

  with lines as (
    select
      left(coalesce(item.value ->> 'raw', ''), 300) as raw_line,
      char_length(coalesce(item.value ->> 'raw', '')) > 300 as truncated,
      jsonb_typeof(item.value) = 'object' as is_object,
      item.value ->> 'pin' as pin,
      public.v1_wf_terminal_time(item.value ->> 'time') as local_time,
      public.v1_wf_terminal_int(item.value ->> 'state') as state,
      public.v1_wf_terminal_int(item.value ->> 'verify') as verify,
      nullif(left(coalesce(item.value ->> 'work_code', ''), 24), '')
        as work_code
    from jsonb_array_elements(p_lines) as item(value)
  ),
  judged as (
    select
      lines.*,
      case
        when not lines.is_object then 'shape'
        when lines.pin is null
          or lines.pin !~ '^[0-9A-Za-z]{1,24}$'
          or lines.pin ~ '^0+$' then 'user_id'
        when lines.local_time is null then 'time'
      end as reason,
      (lines.local_time
        - make_interval(mins => v_terminal.utc_offset_minutes))
        at time zone 'UTC' as moment
    from lines
  ),
  stored as (
    insert into public.v1_workforce_terminal_punches (
      terminal_id, team_id, device_user_id, punched_at_local,
      utc_offset_minutes, punched_at, work_date, punch_state, verify_mode,
      work_code, clock_suspect, raw_line, received_at
    )
    select
      v_terminal.id, v_terminal.team_id, judged.pin, judged.local_time,
      v_terminal.utc_offset_minutes, judged.moment, judged.local_time::date,
      case when judged.state between 0 and 255
        then judged.state::smallint end,
      case when judged.verify between 0 and 999
        then judged.verify::smallint end,
      judged.work_code,
      judged.moment > v_now + interval '10 minutes'
        or judged.local_time < timestamp '2020-01-01 00:00:00',
      judged.raw_line, v_now
    from judged
    where judged.reason is null
    on conflict (terminal_id, device_user_id, punched_at_local) do nothing
    returning 1
  ),
  kept as (
    insert into public.v1_workforce_terminal_rejects (
      terminal_id, raw_line, truncated, reason, received_at
    )
    select v_terminal.id, judged.raw_line, judged.truncated, judged.reason,
      v_now
    from judged
    where judged.reason is not null
    on conflict (terminal_id, raw_line) do nothing
    returning 1
  )
  select
    (select count(*) from judged where judged.reason is null),
    (select count(*) from stored),
    (select count(*) from judged where judged.reason is not null),
    (select count(*) from judged
      where judged.reason is null
        and judged.moment > v_now + interval '10 minutes')
  into v_valid, v_stored, v_rejected, v_future;

  -- The stamp only moves forward, and never on a batch whose clock was
  -- ahead: a wrong future stamp would hide later punches.
  update public.v1_workforce_terminals terminal
  set first_seen_at = coalesce(terminal.first_seen_at, v_now),
      last_seen_at = v_now,
      last_punch_received_at = case
        when v_received > 0 then v_now else terminal.last_punch_received_at
      end,
      attlog_stamp = case
        when v_stamp is null or v_future > 0 then terminal.attlog_stamp
        when terminal.attlog_stamp is null
          or v_stamp::numeric > terminal.attlog_stamp::numeric then v_stamp
        else terminal.attlog_stamp
      end,
      last_remote_ip = coalesce(v_details ->> 'remote_ip', terminal.last_remote_ip)
  where terminal.id = v_terminal.id;

  -- The check-ins are stored. Now, and only for those stored for the first
  -- time, what they do to the place's day. Whatever happens here, the
  -- terminal is told "OK": its check-ins are kept.
  if v_stored > 0 then
    begin
      v_applied := public.v1_wf_terminal_after_punches(v_terminal.id, v_now);
    exception when others then
      v_applied := jsonb_build_object('failed', 1);
      raise warning 'V1_WORKFORCE_TERMINAL_AFTER_PUNCHES_FAILED: %', sqlerrm;
    end;
    if coalesce((v_applied ->> 'failed')::integer, 0) > 0 then
      v_details := v_details
        || jsonb_build_object('note', 'attendance not applied, kept for retry');
    end if;
  end if;

  perform public.v1_wf_terminal_note(
    v_terminal.id, v_serial, 'punches', 'ATTLOG', 'ok',
    v_received, v_stored, v_valid - v_stored, v_rejected, v_details
  );

  return jsonb_build_object(
    'outcome', 'ok',
    'received', v_received,
    'stored', v_stored,
    'duplicates', v_valid - v_stored,
    'rejected', v_rejected
  );
end;
$$;

-- Decides one terminal's day again from the check-ins already stored
-- (operator, service role): after a match was confirmed late, or to try
-- again a line that could not be added. The same rules apply; nothing a
-- person saved is touched. Returns what was found, by kind.
create or replace function public.v1_wf_terminal_apply_day(
  p_serial_number text,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_id uuid;
  v_added integer;
begin
  if v_serial is null or p_work_date is null then
    raise exception 'V1_WORKFORCE_TERMINAL_INVALID' using errcode = '22023';
  end if;
  select terminal.id into v_id
  from public.v1_workforce_terminals terminal
  where terminal.serial_number = v_serial
  for update;
  if v_id is null then
    raise exception 'V1_WORKFORCE_TERMINAL_NOT_FOUND' using errcode = 'P0002';
  end if;
  v_added := public.v1_wf_terminal_apply(v_id, p_work_date, null);
  return jsonb_build_object(
    'serial_number', v_serial,
    'work_date', p_work_date,
    'added_now', v_added,
    'findings', coalesce((
      select jsonb_object_agg(counted.finding, counted.total)
      from (
        select day.finding, count(*) as total
        from public.v1_workforce_terminal_days day
        where day.terminal_id = v_id and day.work_date = p_work_date
        group by day.finding
      ) counted
    ), '{}'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  -- Nothing here is for visitors, and only what follows is for signed-in
  -- people or the service role.
  foreach v_signature in array array[
    'public.v1_wf_terminal_user_key(text)',
    'public.v1_wf_terminal_number_id(text)',
    'public.v1_wf_saved_by(uuid, uuid)',
    'public.v1_wf_terminal_minute(timestamp without time zone)',
    'public.v1_wf_row_json(public.v1_workforce_day_rows)',
    'public.v1_wf_terminal_day_json(uuid, date)',
    'public.v1_wf_get_day(uuid, date)',
    'public.v1_wf_today_json(uuid, date)',
    'public.v1_wf_get_month_sheet(uuid, date)',
    'public.v1_wf_save_day(uuid, date, jsonb, bigint, text, uuid, uuid[])',
    'public.v1_wf_terminal_users_actor()',
    'public.v1_wf_list_terminal_users()',
    'public.v1_wf_confirm_terminal_users(jsonb, uuid)',
    'public.v1_wf_end_terminal_user(text, text, uuid)',
    'public.v1_wf_terminal_json(uuid)',
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_set_terminal_mode(text, text)',
    'public.v1_wf_terminal_finding(uuid, date, uuid, integer)',
    'public.v1_wf_terminal_apply(uuid, date, text[])',
    'public.v1_wf_terminal_note_old(uuid, timestamp with time zone)',
    'public.v1_wf_terminal_mark_failed(uuid, date, text[])',
    'public.v1_wf_terminal_after_punches(uuid, timestamp with time zone)',
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)',
    'public.v1_wf_terminal_apply_day(text, date)'
  ] loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_signature
    );
  end loop;
  -- The app: the day as before, and matching for HR/PRO and Admin (each
  -- function checks the role itself).
  foreach v_signature in array array[
    'public.v1_wf_get_day(uuid, date)',
    'public.v1_wf_get_month_sheet(uuid, date)',
    'public.v1_wf_save_day(uuid, date, jsonb, bigint, text, uuid, uuid[])',
    'public.v1_wf_list_terminal_users()',
    'public.v1_wf_confirm_terminal_users(jsonb, uuid)',
    'public.v1_wf_end_terminal_user(text, text, uuid)'
  ] loop
    execute format(
      'grant execute on function %s to authenticated', v_signature
    );
  end loop;
  -- The receiver and the operator.
  foreach v_signature in array array[
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)',
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_set_terminal_mode(text, text)',
    'public.v1_wf_terminal_apply_day(text, date)'
  ] loop
    execute format(
      'grant execute on function %s to service_role', v_signature
    );
  end loop;
end;
$grants$;


-- ---------------------------------------------------------------------------
-- 9. Self-check.
-- ---------------------------------------------------------------------------

do $check$
begin
  if (select count(*) from pg_catalog.pg_class
      where relnamespace = 'public'::regnamespace
        and relname in (
          'v1_workforce_terminal_users', 'v1_workforce_terminal_days')
        and relrowsecurity) <> 2
    or exists (
      select 1
      from unnest(array[
        'v1_workforce_terminal_users', 'v1_workforce_terminal_days'
      ]) relation,
      unnest(array['anon', 'authenticated']) grantee,
      unnest(array['select', 'insert', 'update', 'delete']) privilege
      where has_table_privilege(grantee, 'public.' || relation, privilege)
    )
    -- One way to save a day, for signed-in people only.
    or (select count(*) from pg_catalog.pg_proc
        where pronamespace = 'public'::regnamespace
          and proname = 'v1_wf_save_day') <> 1
    or exists (
      select 1
      from unnest(array[
        'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid,uuid[])',
        'public.v1_wf_get_day(uuid,date)',
        'public.v1_wf_get_month_sheet(uuid,date)',
        'public.v1_wf_list_terminal_users()',
        'public.v1_wf_confirm_terminal_users(jsonb,uuid)',
        'public.v1_wf_end_terminal_user(text,text,uuid)'
      ]) signature
      where has_function_privilege('anon', signature, 'execute')
        or not has_function_privilege('authenticated', signature, 'execute')
    )
    -- Everything else is for the receiver and the operator.
    or exists (
      select 1
      from unnest(array[
        'public.v1_wf_set_terminal_mode(text,text)',
        'public.v1_wf_terminal_apply_day(text,date)',
        'public.v1_wf_terminal_apply(uuid,date,text[])',
        'public.v1_wf_terminal_after_punches(uuid,timestamp with time zone)',
        'public.v1_wf_terminal_note_old(uuid,timestamp with time zone)',
        'public.v1_wf_terminal_mark_failed(uuid,date,text[])',
        'public.v1_wf_terminal_finding(uuid,date,uuid,integer)',
        'public.v1_wf_terminal_day_json(uuid,date)',
        'public.v1_wf_terminal_users_actor()',
        'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)',
        'public.v1_wf_register_terminal(text,text,text)',
        'public.v1_wf_terminal_json(uuid)',
        'public.v1_wf_row_json(public.v1_workforce_day_rows)',
        'public.v1_wf_today_json(uuid,date)',
        'public.v1_wf_saved_by(uuid,uuid)'
      ]) signature,
      unnest(array['anon', 'authenticated']) grantee
      where has_function_privilege(grantee, signature, 'execute')
    )
    or not has_function_privilege('service_role',
      'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)', 'execute')
    or not has_function_privilege('service_role',
      'public.v1_wf_set_terminal_mode(text,text)', 'execute')
    or not has_function_privilege('service_role',
      'public.v1_wf_terminal_apply_day(text,date)', 'execute')
    -- No terminal adds without a place, and every day is a person's or a
    -- terminal's.
    or exists (
      select 1 from public.v1_workforce_terminals terminal
      where terminal.attendance_mode <> 'watch' and terminal.team_id is null
    )
    or exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where (sheet.entered_by_auth_user_id is null)
        <> (sheet.record_version = 0)
    )
    or exists (
      select 1 from public.v1_workforce_day_rows day_row
      where day_row.updated_by_auth_user_id is null
        and day_row.terminal_id is null
    ) then
    raise exception 'terminal attendance bundle self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';

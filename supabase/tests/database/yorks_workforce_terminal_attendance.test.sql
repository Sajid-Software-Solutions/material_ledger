begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Attendance terminals: a check-in puts the labourer on the place's day
-- (PRODUCT_DECISIONS section 65). Every terminal starts watching; a terminal
-- that adds puts the labourer on the usual shift, never more than 8 hours;
-- ten kinds of check-in are only listed; by hand wins; a terminal's line is
-- the terminal's; an ID counts only once HR/PRO or Admin confirmed it; and a
-- terminal's line never moves the day's version or loses a keeper's work.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- Accountant ...0013, HR/PRO ...0014. Fictional fixtures only.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
end;
$$;

-- What the receiver does with one check-in (runs as the test owner, as the
-- Edge Function's service role does).
create function pg_temp.punch(p_serial text, p_pin text, p_at text)
returns jsonb
language sql
security definer
as $$
  select public.v1_wf_terminal_punches(
    p_serial, null,
    jsonb_build_array(jsonb_build_object(
      'raw', p_pin || E'\t' || p_at || E'\t0\t15\t0\t0',
      'pin', p_pin, 'time', p_at, 'state', '0', 'verify', '15',
      'work_code', '0'
    )),
    '{}'::jsonb
  );
$$;

-- Table rows as the test owner sees them (signed-in people hold no right on
-- these tables).
create function pg_temp.line(p_team text, p_date text, p_worker text)
returns jsonb
language sql
security definer
as $$
  select to_jsonb(day_row)
  from public.v1_workforce_day_rows day_row
  where day_row.team_id = p_team::uuid
    and day_row.work_date = p_date::date
    and day_row.worker_id = p_worker::uuid;
$$;

create function pg_temp.sheet(p_team text, p_date text)
returns jsonb
language sql
security definer
as $$
  select to_jsonb(sheet)
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team::uuid and sheet.work_date = p_date::date;
$$;

create function pg_temp.lines(p_team text, p_date text)
returns integer
language sql
security definer
as $$
  select count(*)::integer
  from public.v1_workforce_day_rows day_row
  where day_row.team_id = p_team::uuid
    and day_row.work_date = p_date::date;
$$;

-- What a terminal's check-ins did for one user ID on one day.
create function pg_temp.found(p_serial text, p_date text, p_pin text)
returns jsonb
language sql
security definer
as $$
  select to_jsonb(day)
  from public.v1_workforce_terminal_days day
  join public.v1_workforce_terminals terminal on terminal.id = day.terminal_id
  where terminal.serial_number = p_serial
    and day.work_date = p_date::date
    and day.device_user_id = p_pin;
$$;

create function pg_temp.changes(p_team text, p_date text)
returns integer
language sql
security definer
as $$
  select count(*)::integer
  from public.v1_workforce_day_changes change
  join public.v1_workforce_day_sheets sheet on sheet.id = change.sheet_id
  where sheet.team_id = p_team::uuid and sheet.work_date = p_date::date;
$$;

-- This session holds the transaction lock with this key.
create function pg_temp.holds(p_key text)
returns boolean
language sql
security definer
as $$
  select exists (
    select 1
    from pg_catalog.pg_locks held
    where held.locktype = 'advisory'
      and held.pid = pg_catalog.pg_backend_pid()
      and held.granted
      and held.objsubid = 1
      and ((held.classid::bigint << 32) | held.objid::bigint)
        = pg_catalog.hashtextextended(p_key, 0)
  );
$$;

-- The day as the app sends it back: every row of the day, without the
-- workers named.
create function pg_temp.day_rows(
  p_team text, p_date text, p_without text[] default array[]::text[]
)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id', entry -> 'worker_id',
    'status', entry -> 'status',
    'start_minute', entry -> 'start_minute',
    'break_start_minute', entry -> 'break_start_minute',
    'break_finish_minute', entry -> 'break_finish_minute',
    'finish_minute', entry -> 'finish_minute',
    'work_project_id', entry -> 'work_project_id',
    'work_label', entry -> 'work_label',
    'work_scope_id', entry -> 'work_scope_id',
    'overtime_note', entry -> 'overtime_note',
    'copied', entry -> 'copied'
  )), '[]'::jsonb)
  from jsonb_array_elements(
    public.v1_wf_get_day(p_team::uuid, p_date::date) -> 'rows'
  ) entry
  where not ((entry ->> 'worker_id') = any(p_without));
$$;

-- The same rows with one worker's row changed.
create function pg_temp.patched(p_rows jsonb, p_worker text, p_patch jsonb)
returns jsonb
language sql
as $$
  select jsonb_agg(case
    when entry ->> 'worker_id' = p_worker then entry || p_patch else entry
  end)
  from jsonb_array_elements(p_rows) entry;
$$;

create function pg_temp.row_p(p_worker text, p_start integer, p_finish integer)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'worker_id', p_worker, 'status', 'P',
    'start_minute', p_start, 'finish_minute', p_finish
  );
$$;

-- Saves a day with the six arguments the app sends today.
create function pg_temp.save(
  p_team text, p_date text, p_rows jsonb, p_version bigint, p_reason text
)
returns jsonb
language sql
as $$
  select public.v1_wf_save_day(
    p_team::uuid, p_date::date, p_rows, p_version, p_reason,
    gen_random_uuid()
  );
$$;

create function pg_temp.day_row(p_team text, p_date text, p_worker text)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(
    public.v1_wf_get_day(p_team::uuid, p_date::date) -> 'rows'
  ) entry
  where entry ->> 'worker_id' = p_worker;
$$;

create function pg_temp.listed(p_team text, p_date text, p_pin text)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(
    public.v1_wf_get_day(p_team::uuid, p_date::date) -> 'terminal' -> 'entries'
  ) entry
  where entry ->> 'device_user_id' = p_pin;
$$;

create function pg_temp.w(p_number integer)
returns text
language sql
immutable
as $$
  select '7a020000-0000-4000-8000-0000000000' || lpad(p_number::text, 2, '0');
$$;

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('7a010000-0000-4000-8000-000000000001', 'TA-001', 'Terminal one',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin'),
  ('7a010000-0000-4000-8000-000000000002', 'TA-002', 'Terminal two',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');

-- Project one has one building; project two has two.
insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values
  ('7a050000-0000-4000-8000-000000000001',
   '7a010000-0000-4000-8000-000000000001', 'common', 'common',
   'Common / All Buildings', true),
  ('7a050000-0000-4000-8000-000000000002',
   '7a010000-0000-4000-8000-000000000001', 'building', 'tower-a',
   'Tower A', false),
  ('7a050000-0000-4000-8000-000000000003',
   '7a010000-0000-4000-8000-000000000002', 'building', 'block-1',
   'Block 1', false),
  ('7a050000-0000-4000-8000-000000000004',
   '7a010000-0000-4000-8000-000000000002', 'building', 'block-2',
   'Block 2', false);

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('7a010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Terminal attendance test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('7a010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'Terminal attendance test',
   '10000000-0000-4000-8000-000000000004', 'admin');

-- Labourers 1 to 26 are numbered TA-910001 to TA-910026, so their terminal
-- IDs are 910001 to 910026. Number 27 has a number with other digits.
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  pg_temp.w(n)::uuid,
  case when n = 27 then 'TB-77' else 'TA-9100' || lpad(n::text, 2, '0') end,
  'Terminal Labourer ' || lpad(n::text, 2, '0'), 'Helper',
  'Example Manpower LLC', 'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 27) n;

-- 21 is staff; 22 is not active.
insert into public.v1_people_profiles (
  worker_id, category, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values (
  pg_temp.w(21)::uuid, 'staff', '10000000-0000-4000-8000-000000000014',
  '10000000-0000-4000-8000-000000000014', 'pr'
);
update public.v1_workforce_workers
set current_status = 'inactive'
where id = pg_temp.w(22)::uuid;

-- Four recent days before today that are working days now: d1 is the newest.
-- d3 is then made a public holiday.
select set_config('ta.d' || picked.position, picked.day::text, true)
from (
  select series.day_ts::date as day,
    row_number() over (order by series.day_ts desc) as position
  from generate_series(
    public.v1_wf_today() - 6, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
) picked
where picked.position <= 4;

select isnt(current_setting('ta.d4', true), null,
  'Four working days are found in the last six');

insert into public.v1_workforce_public_holidays (
  holiday_date, holiday_name, created_by_auth_user_id
) values (
  current_setting('ta.d3')::date, 'Terminal test holiday',
  '10000000-0000-4000-8000-000000000004'
);

-- Places: project one (opened by its Site Engineer), project two, a yard and
-- a store.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('ta.place1', public.v1_wf_open_place(
  '7a010000-0000-4000-8000-000000000001', null) ->> 'id', true);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('ta.place2', public.v1_wf_open_place(
  '7a010000-0000-4000-8000-000000000002', null) ->> 'id', true);
select set_config('ta.yard',
  public.v1_wf_open_place(null, 'Terminal attendance yard') ->> 'id', true);
select set_config('ta.store',
  public.v1_wf_open_place(null, 'Terminal attendance store') ->> 'id', true);
reset role;

select set_config('ta.key_' || place.name, (
  select profile.place_key from public.v1_workforce_crew_profiles profile
  where profile.team_id = current_setting('ta.' || place.name)::uuid
), true)
from (values ('place1'), ('place2'), ('yard'), ('store')) place(name);

select public.v1_wf_terminal_receiver(true);
select public.v1_wf_register_terminal(
  'TAT-0001', 'Site gate', current_setting('ta.key_place1'));
select public.v1_wf_register_terminal(
  'TAT-0002', 'Second gate', current_setting('ta.key_place2'));
select public.v1_wf_register_terminal(
  'TAT-0003', 'Yard gate', current_setting('ta.key_yard'));
select public.v1_wf_register_terminal('TAT-0004', 'Spare terminal');
select public.v1_wf_register_terminal(
  'TAT-0005', 'Store gate', current_setting('ta.key_store'));

-- The personas' names, read once as the test owner.
select set_config('ta.pe_name',
  public.v1_wf_display_name('10000000-0000-4000-8000-000000000001'), true);
select set_config('ta.se_name',
  public.v1_wf_display_name('10000000-0000-4000-8000-000000000002'), true);
select set_config('ta.admin_name',
  public.v1_wf_display_name('10000000-0000-4000-8000-000000000004'), true);

select set_config('ta.events_before', (
  select count(*) from public.v1_workforce_attendance_events
)::text, true);

-- Structure -----------------------------------------------------------------

select is(
  (select count(*)::integer from pg_catalog.pg_class
   where relnamespace = 'public'::regnamespace
     and relname in (
       'v1_workforce_terminal_users', 'v1_workforce_terminal_days')
     and relrowsecurity),
  2,
  'Both new tables have row level security on'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'v1_workforce_terminal_users', 'v1_workforce_terminal_days'
    ]) relation,
    unnest(array['anon', 'authenticated']) grantee,
    unnest(array['select', 'insert', 'update', 'delete']) privilege
    where has_table_privilege(grantee, 'public.' || relation, privilege)
  ),
  'Signed-in people and visitors hold no right on either'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.v1_wf_terminal_user_key(text)',
      'public.v1_wf_terminal_number_id(text)',
      'public.v1_wf_saved_by(uuid,uuid)',
      'public.v1_wf_terminal_minute(timestamp without time zone)',
      'public.v1_wf_terminal_day_json(uuid,date)',
      'public.v1_wf_terminal_users_actor()',
      'public.v1_wf_set_terminal_mode(text,text)',
      'public.v1_wf_terminal_finding(uuid,date,uuid,integer)',
      'public.v1_wf_terminal_apply(uuid,date,text[])',
      'public.v1_wf_terminal_note_old(uuid,timestamp with time zone)',
      'public.v1_wf_terminal_mark_failed(uuid,date,text[])',
      'public.v1_wf_terminal_after_punches(uuid,timestamp with time zone)',
      'public.v1_wf_terminal_apply_day(text,date)',
      'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)',
      'public.v1_wf_register_terminal(text,text,text)'
    ]) signature,
    unnest(array['anon', 'authenticated']) grantee
    where has_function_privilege(grantee, signature, 'execute')
  ),
  'Signed-in people and visitors run none of the terminal functions'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.v1_wf_list_terminal_users()',
      'public.v1_wf_confirm_terminal_users(jsonb,uuid)',
      'public.v1_wf_end_terminal_user(text,text,uuid)',
      'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid,uuid[])'
    ]) signature
    where has_function_privilege('anon', signature, 'execute')
      or not has_function_privilege('authenticated', signature, 'execute')
  ),
  'Matching and saving a day are for signed-in people, never visitors'
);
select is(
  to_regprocedure('public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)'),
  null,
  'Saving a day is one function: the six-argument one is replaced, not kept'
);
select is(
  (select count(*)::integer from pg_catalog.pg_proc
   where pronamespace = 'public'::regnamespace
     and proname = 'v1_wf_save_day'),
  1,
  'so a call has exactly one function to reach'
);
select results_eq(
  $$select distinct attendance_mode from public.v1_workforce_terminals$$,
  $$values ('watch'::text)$$,
  'Every terminal starts watching'
);
select throws_ok(
  $$update public.v1_workforce_terminals set attendance_mode = 'add'
    where serial_number = 'TAT-0004'$$,
  '23514', null,
  'A terminal with no place cannot be set to add, even from the database'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.v1_workforce_terminal_users'::regclass
      and tgname = 'v1_workforce_terminal_users_no_delete'
  ) and exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.v1_workforce_terminal_days'::regclass
      and tgname = 'v1_workforce_terminal_days_no_delete'
  ),
  'Matches and terminal days are never deleted'
);
select is(public.v1_wf_terminal_number_id('WR-000418'), '418',
  'WR-000418 gives the terminal ID 418');
select is(public.v1_wf_terminal_number_id('WR-000000'), null,
  'A number with no digits but zeros gives no ID');
select is(public.v1_wf_terminal_number_id('Helper'), null,
  'A number that ends with no digit gives no ID');
select is(public.v1_wf_terminal_user_key('000418'), '418',
  'An ID sent with leading zeros is the same ID');
select is(public.v1_wf_terminal_user_key('A0418'), 'A0418',
  'An ID with letters is kept as sent');
select is(public.v1_wf_terminal_user_key('000'), null, 'Zero is not an ID');

-- Matching: who may --------------------------------------------------------

set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_wf_list_terminal_users()$$,
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'A Project Engineer does not see the terminal IDs'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'A Project Engineer cannot confirm a terminal ID'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_wf_list_terminal_users()$$,
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'A Site Engineer does not see the terminal IDs'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'A Site Engineer cannot confirm a terminal ID'
);
select throws_ok(
  $$select public.v1_wf_end_terminal_user('910001', 'No', gen_random_uuid())$$,
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'or end a match'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_list_terminal_users()$$,
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'Procurement does not see the terminal IDs'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'Procurement cannot confirm a terminal ID'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  '42501', 'V1_WORKFORCE_TERMINAL_USERS_DENIED',
  'The Accountant keeps attendance but does not confirm terminal IDs'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_users), 0,
  'Nothing was matched by any of them'
);

-- Matching: Admin and HR/PRO -------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');

select is(
  (select entry ->> 'number_id'
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'labourers') entry
   where entry ->> 'worker_id' = pg_temp.w(1)),
  '910001',
  'Admin sees each labourer with the ID their number gives'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'labourers') entry
   where entry ->> 'worker_id' in (pg_temp.w(21), pg_temp.w(22))),
  0,
  'Staff and labourers who are not active are not offered'
);

-- Labourers 1 to 20 in one request; number 3 is sent with leading zeros.
select set_config('ta.confirm_key', gen_random_uuid()::text, true);
select set_config('ta.confirm_body', (
  select jsonb_agg(jsonb_build_object(
    'device_user_id',
      case when n = 3 then '000910003' else '9100' || lpad(n::text, 2, '0') end,
    'worker_id', pg_temp.w(n)
  ))
  from generate_series(1, 20) n
)::text, true);
select lives_ok(
  $$select public.v1_wf_confirm_terminal_users(
    current_setting('ta.confirm_body')::jsonb,
    current_setting('ta.confirm_key')::uuid)$$,
  'Admin confirms twenty terminal IDs at once'
);
select lives_ok(
  $$select public.v1_wf_confirm_terminal_users(
    current_setting('ta.confirm_body')::jsonb,
    current_setting('ta.confirm_key')::uuid)$$,
  'The same request sent again is answered'
);
select lives_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  'and a match already confirmed may be confirmed again'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_users), 20,
  'Each labourer is matched once, however often it is confirmed'
);
select is(
  (select count(*)::integer from public.v1_audit_events
   where event_type = 'workforce_terminal_user_confirmed'
     and entity_type = 'workforce_worker'
     and actor_auth_user_id = '10000000-0000-4000-8000-000000000004'
     and actor_exact_role = 'admin'),
  20,
  'with one audit event each, naming Admin'
);
select results_eq(
  $$select device_user_id, follows_number
    from public.v1_workforce_terminal_users
    where worker_id = pg_temp.w(3)::uuid$$,
  $$values ('910003'::text, true)$$,
  'An ID sent with leading zeros is stored without them and follows the number'
);
set local role authenticated;

select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910001", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_TAKEN',
  'An ID matched to one labourer cannot be given to another'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "999999", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(1)),
  '22023', 'V1_WORKFORCE_TERMINAL_WORKER_MATCHED',
  'A labourer has one terminal ID'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910021", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(21)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_STAFF',
  'Staff are not matched'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910022", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(22)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_NOT_ACTIVE',
  'A labourer who is not active is not matched'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "12 34", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_INVALID',
  'An ID that a terminal could not send is refused'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "000", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_INVALID',
  'Zero is refused'
);
select throws_ok(
  $$select public.v1_wf_confirm_terminal_users(
    '[{"device_user_id": "910023",
       "worker_id": "7a020000-0000-4000-8000-0000000000ff"}]'::jsonb,
    gen_random_uuid())$$,
  'P0002', 'V1_WORKFORCE_WORKER_NOT_FOUND',
  'An unknown labourer is refused'
);
select throws_ok(
  $$select public.v1_wf_confirm_terminal_users('[]'::jsonb, gen_random_uuid())$$,
  '22023', 'V1_WORKFORCE_TERMINAL_USER_INVALID',
  'An empty request is refused'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910023", "worker_id": "%s"},
        {"device_user_id": "910023", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23), pg_temp.w(24)),
  '22023', 'V1_WORKFORCE_TERMINAL_USER_INVALID',
  'One ID for two labourers in one request is refused'
);
select throws_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910023", "worker_id": "%s", "note": "x"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23)),
  '22023', null,
  'An unknown field is refused'
);
-- An ID that is not the labourer's number is allowed, and says so.
select lives_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "4242", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(27)),
  'Admin may confirm an ID that is not the labourer''s number'
);
select is(
  (select (entry ->> 'follows_number')::boolean
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'labourers') entry
   where entry ->> 'worker_id' = pg_temp.w(27)),
  false,
  'and the match says it does not follow the number'
);

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select lives_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910023", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(23)),
  'HR/PRO confirms a terminal ID'
);
select throws_ok(
  $$select public.v1_wf_end_terminal_user('910023', '  ', gen_random_uuid())$$,
  '22023', 'V1_WORKFORCE_REASON_REQUIRED',
  'Ending a match needs a reason'
);
select throws_ok(
  $$select public.v1_wf_end_terminal_user(
    '555555', 'Not ours', gen_random_uuid())$$,
  'P0002', 'V1_WORKFORCE_TERMINAL_USER_NOT_FOUND',
  'An ID that is not matched cannot be ended'
);
select lives_ok(
  $$select public.v1_wf_end_terminal_user(
    '910023', 'Enrolled under the wrong number', gen_random_uuid())$$,
  'HR/PRO ends a wrong match with a reason'
);
select lives_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910023", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(25)),
  'and the ID can then be matched to the right labourer'
);
reset role;
select results_eq(
  $$select worker_id::text, ended_at is not null, end_reason, ended_by_role
    from public.v1_workforce_terminal_users
    where device_user_id = '910023'
    order by confirmed_at$$,
  format(
    $$values ('%s'::text, true, 'Enrolled under the wrong number'::text,
        'pr'::text),
      ('%s'::text, false, null::text, null::text)$$,
    pg_temp.w(23), pg_temp.w(25)),
  'The ended match is kept beside the new one'
);
select is(
  (select reason from public.v1_audit_events
   where event_type = 'workforce_terminal_user_ended'
     and entity_id = pg_temp.w(23)::uuid
     and actor_exact_role = 'pr'),
  'Enrolled under the wrong number',
  'Ending a match is in the audit trail with its reason'
);

-- Watching -------------------------------------------------------------------

select is(
  pg_temp.punch('TAT-0001', '910001', current_setting('ta.d1') || ' 06:20:00'),
  jsonb_build_object(
    'outcome', 'ok', 'received', 1, 'stored', 1, 'duplicates', 0,
    'rejected', 0),
  'A check-in is stored and answered exactly as before'
);
select is(pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d1')),
  null, 'A terminal that watches opens no day');
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d1')),
  0, 'and adds no line');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910001')
    - 'id' - 'terminal_id' - 'decided_at',
  jsonb_build_object(
    'work_date', current_setting('ta.d1'),
    'device_user_id', '910001',
    'team_id', current_setting('ta.place1'),
    'worker_id', pg_temp.w(1),
    'first_punched_at_local', current_setting('ta.d1') || 'T06:20:00',
    'last_punched_at_local', current_setting('ta.d1') || 'T06:20:00',
    'punch_count', 1,
    'finding', 'add', 'added', false, 'watching', true),
  'It records what the check-in would have done: a line, not added'
);
select ok(
  not pg_temp.holds('workforce_day:' || current_setting('ta.place1') || ':'
    || current_setting('ta.d1')),
  'Watching takes no lock on the day'
);
select pg_temp.punch('TAT-0001', '990001',
  current_setting('ta.d1') || ' 06:21:00');
select pg_temp.punch('TAT-0001', '910026',
  current_setting('ta.d1') || ' 06:22:00');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '990001') ->> 'finding',
  'unmatched', 'An ID nobody confirmed is listed as not matched');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910026') ->> 'finding',
  'unmatched',
  'An ID counts only once confirmed, even when a labourer has that number'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  (public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
  ) ->> 'saved')::boolean,
  false, 'The keeper still sees a day nobody saved'
);
select is(
  public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
  ) -> 'terminal' -> 'adding',
  'false'::jsonb, 'and that the place''s terminal is watching'
);
select is(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '910001') - 'worker',
  jsonb_build_object(
    'device_user_id', '910001', 'finding', 'add', 'added', false,
    'watching', true, 'check_in_minute', 380, 'check_out_minute', null,
    'check_ins', 1, 'terminal_name', 'Site gate'),
  'with the check-in listed beside the day'
);
select is(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '910001') -> 'worker' ->> 'name',
  'Terminal Labourer 01', 'naming the labourer');
select is(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '990001') -> 'worker',
  'null'::jsonb, 'An ID that is not matched is listed without a labourer');

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  (select jsonb_agg(entry ->> 'device_user_id' order by entry ->> 'device_user_id')
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'unmatched') entry
   where entry ->> 'device_user_id' in ('990001', '910026', '910001')),
  '["910026", "990001"]'::jsonb,
  'Admin sees the IDs terminals sent that are matched to nobody'
);
select is(
  (select entry ->> 'proposed_worker_id'
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'unmatched') entry
   where entry ->> 'device_user_id' = '910026'),
  pg_temp.w(26),
  'with the labourer whose number gives that ID proposed'
);
select is(
  (select entry -> 'proposed_worker_id'
   from jsonb_array_elements(
     public.v1_wf_list_terminal_users() -> 'unmatched') entry
   where entry ->> 'device_user_id' = '990001'),
  'null'::jsonb, 'and none proposed when no number gives it');

-- The switch -----------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  $$select public.v1_wf_set_terminal_mode('TAT-0001', 'add')$$,
  '42501', null,
  'Admin cannot switch a terminal to adding from the app'
);
select throws_ok(
  $$select public.v1_wf_terminal_apply_day('TAT-0001', public.v1_wf_today())$$,
  '42501', null,
  'or apply a day again'
);
reset role;

select throws_ok(
  $$select public.v1_wf_set_terminal_mode('TAT-0004', 'add')$$,
  '22023', 'V1_WORKFORCE_TERMINAL_PLACE_REQUIRED',
  'A terminal with no place cannot add'
);
select throws_ok(
  $$select public.v1_wf_set_terminal_mode('TAT-0001', 'both')$$,
  '22023', 'V1_WORKFORCE_TERMINAL_INVALID',
  'A terminal watches or adds, nothing else'
);
select throws_ok(
  $$select public.v1_wf_set_terminal_mode('TAT-9999', 'add')$$,
  'P0002', 'V1_WORKFORCE_TERMINAL_NOT_FOUND',
  'An unregistered terminal cannot be switched'
);
-- The operator is the service role (the SQL editor), as for the receiver.
set local role service_role;
select is(
  public.v1_wf_set_terminal_mode('TAT-0001', 'add') ->> 'attendance_mode',
  'add', 'The operator switches a terminal to adding'
);
select is(
  public.v1_wf_set_terminal_mode('TAT-0001', 'add') -> 'record_version',
  '2'::jsonb, 'Switching it to what it already is changes nothing'
);
reset role;
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d1')),
  0, 'Check-ins stored while it watched are not turned into lines');

-- A check-in adds the labourer -----------------------------------------------

-- The labourer's next check-in that day decides the day again, from the
-- first one (06:20).
select pg_temp.punch('TAT-0001', '910001',
  current_setting('ta.d1') || ' 14:40:00');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(1))
    - 'id' - 'sheet_id' - 'updated_at' - 'terminal_id',
  jsonb_build_object(
    'team_id', current_setting('ta.place1'),
    'work_date', current_setting('ta.d1'),
    'worker_id', pg_temp.w(1),
    'attendance_status', 'P',
    'start_minute', 390, 'finish_minute', 870,
    'break_start_minute', null, 'break_finish_minute', null,
    'work_project_id', '7a010000-0000-4000-8000-000000000001',
    'work_scope_id', '7a050000-0000-4000-8000-000000000002',
    'work_label', null, 'overtime_note', null, 'copied', false,
    'changed_after_entry', false,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0, 'holiday_overtime_minutes', 0,
    'updated_by_auth_user_id', null),
  'A check-in adds the labourer as Present on the usual shift, 8 hours, no overtime, in the project''s one building, under no person''s name'
);
select is(
  (select terminal.serial_number
   from public.v1_workforce_terminals terminal
   where terminal.id = (pg_temp.line(current_setting('ta.place1'),
     current_setting('ta.d1'), pg_temp.w(1)) ->> 'terminal_id')::uuid),
  'TAT-0001', 'The line is the terminal''s');
select is(
  pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d1'))
    - 'id' - 'entered_at' - 'last_saved_at' - 'entered_by_terminal_id',
  jsonb_build_object(
    'team_id', current_setting('ta.place1'),
    'work_date', current_setting('ta.d1'),
    'entered_by_auth_user_id', null, 'last_saved_by_auth_user_id', null,
    'entered_late', true, 'record_version', 0,
    'hand_removed_worker_ids', '[]'::jsonb),
  'The day a terminal opens is at version 0: no person has saved it'
);
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910001')
    - 'id' - 'terminal_id' - 'decided_at' - 'work_date' - 'device_user_id'
    - 'team_id' - 'worker_id',
  jsonb_build_object(
    'first_punched_at_local', current_setting('ta.d1') || 'T06:20:00',
    'last_punched_at_local', current_setting('ta.d1') || 'T14:40:00',
    'punch_count', 2, 'finding', 'add', 'added', true, 'watching', false),
  'The first and last check-in are kept, and that the terminal added the line'
);
-- The same locks v1_wf_save_day takes: the day, then the labourer's day; and
-- the month, so a confirmation cannot slip in.
select ok(
  pg_temp.holds('workforce_day:' || current_setting('ta.place1') || ':'
    || current_setting('ta.d1')),
  'Adding a line takes the lock on the place''s day that saving a day takes'
);
select ok(
  pg_temp.holds('workforce_worker_day:' || pg_temp.w(1) || ':'
    || current_setting('ta.d1')),
  'and the lock on the labourer''s day'
);
select ok(
  pg_temp.holds('workforce_month:' || current_setting('ta.place1') || ':'
    || date_trunc('month', current_setting('ta.d1')::date)::date::text),
  'and the lock a month confirmation takes'
);

-- A check-in sent twice adds one line. (Called as the Edge Function calls
-- it: with the service role.)
set local role service_role;
select is(
  public.v1_wf_terminal_punches('TAT-0001', null, jsonb_build_array(
    jsonb_build_object(
      'raw', E'910001\t' || current_setting('ta.d1') || E' 06:20:00\t0\t15\t0\t0',
      'pin', '910001', 'time', current_setting('ta.d1') || ' 06:20:00',
      'state', '0', 'verify', '15', 'work_code', '0'),
    jsonb_build_object(
      'raw', E'910001\t' || current_setting('ta.d1') || E' 14:40:00\t0\t15\t0\t0',
      'pin', '910001', 'time', current_setting('ta.d1') || ' 14:40:00',
      'state', '0', 'verify', '15', 'work_code', '0')
  ), '{}'::jsonb),
  jsonb_build_object(
    'outcome', 'ok', 'received', 2, 'stored', 0, 'duplicates', 2,
    'rejected', 0),
  'The same check-ins sent again are duplicates'
);
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d1')),
  1, 'and the day still has one line');
select is(
  (pg_temp.found('TAT-0001', current_setting('ta.d1'), '910001')
    ->> 'punch_count')::integer,
  2, 'and two check-ins');
select is(
  public.v1_wf_terminal_apply_day('TAT-0001', current_setting('ta.d1')::date)
    ->> 'added_now',
  '0', 'Deciding the day again adds nothing twice');
reset role;
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d1')),
  1, 'One line');

-- What the keeper reads.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
  ) - 'crew' - 'rows' - 'month' - 'access' - 'changes' - 'terminal'
    - 'entered_at' - 'last_saved_at' - 'today' - 'previous_same_type_date'
    - 'holiday_name' - 'question',
  jsonb_build_object(
    'schema_version', 'yorks.workforce.day.v2',
    'date', current_setting('ta.d1'),
    'day_type', 'work',
    'saved', true, 'record_version', 0,
    'entered_by', 'Site gate', 'entered_by_me', false,
    'entered_by_terminal', 'Site gate', 'entered_late', true,
    'last_saved_by', 'Site gate', 'locked', false, 'is_future', false),
  'The Site Engineer reads a day the terminal opened: saved, version 0, entered by the terminal'
);
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(1)) - 'worker' - 'elsewhere' - 'sort_name' - 'is_member'
    - 'work_scope_name' - 'work_scope_kind',
  jsonb_build_object(
    'worker_id', pg_temp.w(1), 'status', 'P',
    'start_minute', 390, 'finish_minute', 870,
    'break_start_minute', null, 'break_finish_minute', null,
    'work_project_id', '7a010000-0000-4000-8000-000000000001',
    'work_scope_id', '7a050000-0000-4000-8000-000000000002',
    'work_label', null, 'overtime_note', null, 'copied', false,
    'changed_after_entry', false,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0, 'holiday_overtime_minutes', 0,
    'updated_by', 'Site gate', 'updated_by_me', false,
    'by_terminal', true, 'terminal_name', 'Site gate',
    'check_in_minute', 380, 'check_out_minute', 880, 'check_ins', 2),
  'The line names the terminal as who saved it, is not "mine", and carries the real check-in (06:20) and check-out (14:40) beside the usual shift'
);
select is(
  public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
  ) -> 'terminal' -> 'adding',
  'true'::jsonb, 'The day says the place''s terminal adds');
select is(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '910001'),
  null, 'A labourer who is on the day is no longer listed beside it');
select isnt(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '990001'),
  null, 'An ID that is not matched still is');

-- A terminal's line never moves the day's version ---------------------------

-- d2: the Site Engineer saves labourer 2 by hand, then the terminal adds 3.
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d2'),
    jsonb_build_array(pg_temp.row_p(pg_temp.w(2), 420, 900)), 0, null)$$,
  'The Site Engineer saves a day by hand with the six arguments the app sends'
);
-- The app keeps what it loaded: version 1 and one row.
select set_config('ta.stale_rows',
  pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d2'))::text,
  true);
reset role;
select pg_temp.punch('TAT-0001', '910003',
  current_setting('ta.d2') || ' 06:25:00');
select pg_temp.punch('TAT-0001', '910002',
  current_setting('ta.d2') || ' 06:26:00');
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d2')),
  2, 'The terminal adds a line to a day a person saved');
select is(
  pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d2'))
    -> 'record_version',
  '1'::jsonb, 'without moving the day''s version');
select is(
  pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d2'))
    ->> 'last_saved_by_auth_user_id',
  '10000000-0000-4000-8000-000000000002',
  'or who saved it last'
);
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d2'), '910002') ->> 'finding',
  'on_day', 'A labourer already on the day by hand gets no second line');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d2'),
    pg_temp.w(2)) - 'id' - 'sheet_id' - 'updated_at' - 'team_id' - 'work_date'
    - 'worker_id' - 'work_project_id' - 'work_scope_id' - 'work_label'
    - 'overtime_note' - 'copied' - 'changed_after_entry'
    - 'break_start_minute' - 'break_finish_minute',
  jsonb_build_object(
    'attendance_status', 'P', 'start_minute', 420, 'finish_minute', 900,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0, 'holiday_overtime_minutes', 0,
    'updated_by_auth_user_id', '10000000-0000-4000-8000-000000000002',
    'terminal_id', null),
  'and the line the person saved is exactly as they saved it'
);

-- The app saves what it loaded before the terminal's line, at the version it
-- holds. Nothing conflicts and the terminal's line stays.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d2'),
    current_setting('ta.stale_rows')::jsonb, 1, null)$$,
  'A save from an app that has not seen the terminal''s line does not conflict'
);
select is(
  (public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d2')::date
  ) ->> 'record_version')::integer,
  2, 'The person''s save moves the version');
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d2'),
    pg_temp.w(3)) -> 'by_terminal',
  'true'::jsonb, 'and the terminal''s line it did not send is still there');
select throws_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d2'),
    current_setting('ta.stale_rows')::jsonb, 1, null)$$,
  '40001', 'V1_WORKFORCE_DAY_VERSION_CONFLICT',
  'A version a person has moved on from is still a conflict'
);
reset role;
select is(pg_temp.changes(current_setting('ta.place1'), current_setting('ta.d2')),
  0, 'Keeping the terminal''s line is not a change');

-- d4: the app loaded a day nobody had saved (version 0); the terminal then
-- opens it; the keeper's save at version 0 still goes through.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  (public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d4')::date
  ) ->> 'record_version')::integer,
  0, 'An unsaved day is at version 0');
reset role;
select pg_temp.punch('TAT-0001', '910004',
  current_setting('ta.d4') || ' 06:10:00');
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d4')),
  1, 'The terminal opens the day while the keeper is typing');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d4'),
    jsonb_build_array(pg_temp.row_p(pg_temp.w(5), 390, 870)), 0, null)$$,
  'The keeper''s first save at version 0 goes through'
);
select is(
  public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d4')::date
  ) - 'crew' - 'rows' - 'month' - 'access' - 'changes' - 'terminal'
    - 'entered_at' - 'last_saved_at' - 'today' - 'previous_same_type_date'
    - 'holiday_name' - 'question' - 'schema_version' - 'date' - 'day_type'
    - 'locked' - 'is_future' - 'entered_late',
  jsonb_build_object(
    'saved', true, 'record_version', 1,
    'entered_by', current_setting('ta.se_name'),
    'entered_by_me', true, 'entered_by_terminal', 'Site gate',
    'last_saved_by', current_setting('ta.se_name')),
  'The first person to save a day a terminal opened enters it; the terminal that opened it is kept'
);
select is(
  (select jsonb_agg(entry -> 'by_terminal' order by entry ->> 'worker_id')
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('ta.place1')::uuid, current_setting('ta.d4')::date
   ) -> 'rows') entry),
  '[true, false]'::jsonb,
  'Both lines are on the day: the terminal''s and the keeper''s'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_attendance_events
   where team_id = current_setting('ta.place1')::uuid
     and work_date = current_setting('ta.d4')::date
     and event_kind = 'entered'
     and actor_auth_user_id = '10000000-0000-4000-8000-000000000002'),
  1, 'That first save is the day''s "entered" event');
select is(
  (select count(*)::integer from public.v1_audit_events
   where event_type = 'workforce_day_entered'
     and entity_id = (pg_temp.sheet(current_setting('ta.place1'),
       current_setting('ta.d4')) ->> 'id')::uuid),
  1, 'and its audit event');

-- By hand wins ---------------------------------------------------------------

select pg_temp.punch('TAT-0001', '910003',
  current_setting('ta.d1') || ' 06:15:00');
select pg_temp.punch('TAT-0001', '910005',
  current_setting('ta.d1') || ' 06:18:00');
select pg_temp.punch('TAT-0001', '910006',
  current_setting('ta.d1') || ' 06:19:00');
select is(pg_temp.lines(current_setting('ta.place1'), current_setting('ta.d1')),
  4, 'Four labourers checked in on d1');

-- Times: no reason.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.patched(
      pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1')),
      pg_temp.w(1), '{"finish_minute": 1020}'::jsonb),
    0, null)$$,
  'The Site Engineer changes a terminal line''s Out time with no reason'
);
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(1)) - 'worker' - 'elsewhere' - 'sort_name' - 'is_member'
    - 'work_scope_name' - 'work_scope_kind' - 'worker_id' - 'status'
    - 'start_minute' - 'break_start_minute' - 'break_finish_minute'
    - 'work_project_id' - 'work_scope_id' - 'work_label' - 'overtime_note'
    - 'copied' - 'holiday_overtime_minutes',
  jsonb_build_object(
    'finish_minute', 1020, 'worked_minutes', 630, 'regular_minutes', 480,
    'normal_overtime_minutes', 150, 'changed_after_entry', false,
    'updated_by', current_setting('ta.se_name'),
    'updated_by_me', true, 'by_terminal', false,
    'terminal_name', 'Site gate',
    'check_in_minute', 380, 'check_out_minute', 880, 'check_ins', 2),
  'The line is now that person''s, with the overtime they entered; it still says which terminal it came from'
);
select is(
  (select jsonb_agg(entry -> 'by_terminal' order by entry ->> 'worker_id')
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
   ) -> 'rows') entry),
  '[false, true, true, true]'::jsonb,
  'The lines sent back unchanged are still the terminal''s'
);
reset role;
select is(pg_temp.changes(current_setting('ta.place1'), current_setting('ta.d1')),
  0, 'Changing a terminal line''s times is not in the change list');
select is(
  (select count(*)::integer from public.v1_workforce_attendance_events
   where team_id = current_setting('ta.place1')::uuid
     and work_date = current_setting('ta.d1')::date
     and event_kind = 'entered'),
  1, 'The first person''s save entered the day');

-- The terminal never touches that line again.
select pg_temp.punch('TAT-0001', '910001',
  current_setting('ta.d1') || ' 15:00:00');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(1)) - 'id' - 'sheet_id' - 'updated_at' - 'team_id' - 'work_date'
    - 'worker_id' - 'work_project_id' - 'work_scope_id' - 'work_label'
    - 'overtime_note' - 'copied' - 'changed_after_entry'
    - 'break_start_minute' - 'break_finish_minute' - 'terminal_id'
    - 'attendance_status' - 'holiday_overtime_minutes',
  jsonb_build_object(
    'start_minute', 390, 'finish_minute', 1020,
    'worked_minutes', 630, 'regular_minutes', 480,
    'normal_overtime_minutes', 150,
    'updated_by_auth_user_id', '10000000-0000-4000-8000-000000000002'),
  'A later check-in leaves a line a person changed exactly as it is'
);
select is(
  (pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d1'))
    ->> 'record_version')::integer,
  1, 'and the day''s version where the person left it');

-- Not present: a reason.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.patched(
      pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1')),
      pg_temp.w(3), '{"status": "A"}'::jsonb),
    1, null)$$,
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'Marking a terminal''s line absent needs a reason'
);
-- The Site Engineer's own line (labourer 1) is someone else's for the
-- Project Engineer, so it is sent back unchanged.
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.patched(
      pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1')),
      pg_temp.w(3), '{"status": "A"}'::jsonb),
    1, 'Sent home at seven')$$,
  'The Project Engineer marks it absent with a reason'
);
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(3)) - 'worker' - 'elsewhere' - 'sort_name' - 'is_member'
    - 'work_scope_name' - 'work_scope_kind' - 'worker_id'
    - 'work_project_id' - 'work_scope_id' - 'work_label' - 'overtime_note'
    - 'copied' - 'check_in_minute' - 'check_out_minute' - 'check_ins'
    - 'terminal_name',
  jsonb_build_object(
    'status', 'A', 'start_minute', null, 'finish_minute', null,
    'break_start_minute', null, 'break_finish_minute', null,
    'worked_minutes', 0, 'regular_minutes', 0,
    'normal_overtime_minutes', 0, 'holiday_overtime_minutes', 0,
    'changed_after_entry', true,
    'updated_by', current_setting('ta.pe_name'),
    'updated_by_me', true, 'by_terminal', false),
  'The line is absent, the Project Engineer''s, and marked changed'
);
reset role;
select results_eq(
  $$select change.worker_id::text, change.before_data ->> 'status',
      change.after_data ->> 'status', change.reason, change.actor_exact_role
    from public.v1_workforce_day_changes change
    join public.v1_workforce_day_sheets sheet on sheet.id = change.sheet_id
    where sheet.team_id = current_setting('ta.place1')::uuid
      and sheet.work_date = current_setting('ta.d1')::date$$,
  format(
    $$values ('%s'::text, 'P'::text, 'A'::text, 'Sent home at seven'::text,
      'project_engineer'::text)$$, pg_temp.w(3)),
  'and the change is in the day''s change list with its reason'
);

-- Removing: named, with a reason.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1'),
      array[pg_temp.w(5)]),
    2, null)$$,
  'Leaving a terminal''s line out of a save needs no reason'
);
select isnt(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(5)),
  null, 'because it does not remove it: the app may not have seen it');
select throws_ok(
  $$select public.v1_wf_save_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date,
    pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1'),
      array[pg_temp.w(5)]),
    3, null, gen_random_uuid(), array[pg_temp.w(5)::uuid])$$,
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'Removing a terminal''s line needs a reason'
);
select throws_ok(
  $$select public.v1_wf_save_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date,
    pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1')),
    3, 'Not here', gen_random_uuid(), array[pg_temp.w(5)::uuid])$$,
  '22023', 'V1_WORKFORCE_DAY_INVALID',
  'A line is sent or named as removed, never both'
);
select lives_ok(
  $$select public.v1_wf_save_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date,
    pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d1'),
      array[pg_temp.w(5)]),
    3, 'Checked in at the wrong site', gen_random_uuid(),
    array[pg_temp.w(5)::uuid])$$,
  'The Site Engineer removes a terminal''s line by naming it, with a reason'
);
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(5)),
  null, 'The line is gone');
select is(
  pg_temp.day_row(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(6)) -> 'by_terminal',
  'true'::jsonb, 'and the other terminal line is untouched');
reset role;
select is(pg_temp.changes(current_setting('ta.place1'), current_setting('ta.d1')),
  2, 'The removal is in the change list too');
select is(
  pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d1'))
    -> 'hand_removed_worker_ids',
  jsonb_build_array(pg_temp.w(5)),
  'The day remembers who a person removed'
);
-- The removed labourer checks out: the terminal does not add them again.
select pg_temp.punch('TAT-0001', '910005',
  current_setting('ta.d1') || ' 14:31:00');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(5)),
  null, 'A labourer a person removed is not added again by a later check-in');
select is(
  public.v1_wf_terminal_apply_day('TAT-0001', current_setting('ta.d1')::date)
    ->> 'added_now',
  '0', 'nor by deciding the day again');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  pg_temp.listed(current_setting('ta.place1'), current_setting('ta.d1'),
    '910005') - 'worker' - 'terminal_name',
  jsonb_build_object(
    'device_user_id', '910005', 'finding', 'add', 'added', true,
    'watching', false, 'check_in_minute', 378, 'check_out_minute', 871,
    'check_ins', 2),
  'Their check-ins are listed beside the day: added by the terminal, no longer on it'
);

-- A line a person added and took off again also keeps the terminal away.
select lives_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d2'),
    pg_temp.day_rows(current_setting('ta.place1'), current_setting('ta.d2'),
      array[pg_temp.w(2)]),
    2, null)$$,
  'A keeper removes their own line with no reason, as before'
);
reset role;
select is(
  pg_temp.sheet(current_setting('ta.place1'), current_setting('ta.d2'))
    -> 'hand_removed_worker_ids',
  jsonb_build_array(pg_temp.w(2)), 'The day remembers that too');
select pg_temp.punch('TAT-0001', '910002',
  current_setting('ta.d2') || ' 14:20:00');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d2'), '910002') ->> 'finding',
  'removed_by_hand',
  'A check-in after a person removed the labourer is listed, not added'
);
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d2'),
    pg_temp.w(2)),
  null, 'No line');

-- Listed, never added --------------------------------------------------------

select public.v1_wf_set_terminal_mode('TAT-0002', 'add');

-- Two hours before the usual start (06:30) is 04:30; the usual finish is
-- 14:30.
select pg_temp.punch('TAT-0002', '910011',
  current_setting('ta.d1') || ' 04:29:59');
select pg_temp.punch('TAT-0002', '910012',
  current_setting('ta.d1') || ' 04:30:00');
select pg_temp.punch('TAT-0002', '910013',
  current_setting('ta.d1') || ' 14:31:00');
select pg_temp.punch('TAT-0002', '910014',
  current_setting('ta.d1') || ' 14:30:59');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910011') ->> 'finding',
  'outside_shift',
  'A first check-in more than two hours before the usual start is listed'
);
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910012') ->> 'finding',
  'add', 'One exactly two hours before is added');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910013') ->> 'finding',
  'outside_shift', 'A first check-in after the usual finish is listed');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910014') ->> 'finding',
  'add', 'One in the usual finish''s minute is added');
select is(pg_temp.lines(current_setting('ta.place2'), current_setting('ta.d1')),
  2, 'Two lines, for the two inside the window');
select is(
  pg_temp.line(current_setting('ta.place2'), current_setting('ta.d1'),
    pg_temp.w(14)) - 'id' - 'sheet_id' - 'updated_at' - 'team_id' - 'work_date'
    - 'worker_id' - 'terminal_id' - 'work_label' - 'overtime_note' - 'copied'
    - 'changed_after_entry' - 'break_start_minute' - 'break_finish_minute'
    - 'updated_by_auth_user_id' - 'holiday_overtime_minutes',
  jsonb_build_object(
    'attendance_status', 'P', 'start_minute', 390, 'finish_minute', 870,
    'work_project_id', '7a010000-0000-4000-8000-000000000002',
    'work_scope_id', null,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0),
  'A labourer who checks in at the end of the shift still gets the usual shift; with two buildings the building is left for the keeper'
);

-- Already at another place that day.
select pg_temp.punch('TAT-0002', '910006',
  current_setting('ta.d1') || ' 06:40:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910006') ->> 'finding',
  'elsewhere',
  'A labourer who already has a line at another place that day is listed'
);
select is(
  pg_temp.line(current_setting('ta.place2'), current_setting('ta.d1'),
    pg_temp.w(6)),
  null, 'and not added at the second place');
-- Absent at another place is a line there too.
select pg_temp.punch('TAT-0002', '910003',
  current_setting('ta.d1') || ' 06:41:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910003') ->> 'finding',
  'elsewhere', 'even when that line says absent');

-- A rest day or public holiday.
select pg_temp.punch('TAT-0002', '910015',
  current_setting('ta.d3') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d3'), '910015') ->> 'finding',
  'rest_day', 'A check-in on a public holiday is listed');
select is(pg_temp.sheet(current_setting('ta.place2'), current_setting('ta.d3')),
  null, 'and opens no day');

-- Not matched.
select pg_temp.punch('TAT-0002', '990002',
  current_setting('ta.d1') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '990002') ->> 'finding',
  'unmatched', 'An ID that is not matched is listed');

-- Staff, and a labourer who is not active (both matched while they could be).
insert into public.v1_people_profiles (
  worker_id, category, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values (
  pg_temp.w(19)::uuid, 'staff', '10000000-0000-4000-8000-000000000014',
  '10000000-0000-4000-8000-000000000014', 'pr'
);
update public.v1_workforce_workers
set current_status = 'suspended'
where id = pg_temp.w(20)::uuid;
select pg_temp.punch('TAT-0002', '910019',
  current_setting('ta.d1') || ' 06:20:00');
select pg_temp.punch('TAT-0002', '910020',
  current_setting('ta.d1') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910019') ->> 'finding',
  'staff', 'Staff are listed');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910020') ->> 'finding',
  'not_active', 'A labourer who is not active is listed');

-- More than seven days late, and a date in the future.
select pg_temp.punch('TAT-0002', '910015',
  (public.v1_wf_today() - 8)::text || ' 06:20:00');
select pg_temp.punch('TAT-0002', '910015',
  (public.v1_wf_today() + 1)::text || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', (public.v1_wf_today() - 8)::text, '910015')
    ->> 'finding',
  'late', 'A check-in more than seven days old is listed');
select is(
  pg_temp.found('TAT-0002', (public.v1_wf_today() + 1)::text, '910015')
    ->> 'finding',
  'clock', 'A check-in dated tomorrow is a wrong clock, and is listed');
select is(
  pg_temp.sheet(current_setting('ta.place2'), (public.v1_wf_today() - 8)::text),
  null, 'Neither opens a day');
select is(
  pg_temp.sheet(current_setting('ta.place2'), (public.v1_wf_today() + 1)::text),
  null, 'in the past or the future');
-- Seven days old is still inside.
select pg_temp.punch('TAT-0002', '910016',
  (public.v1_wf_today() - 7)::text || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', (public.v1_wf_today() - 7)::text, '910016')
    ->> 'finding',
  case
    when public.v1_wf_day_type(public.v1_wf_today() - 7) = 'holiday'
      then 'rest_day' else 'add'
  end,
  'A check-in seven days old is still decided by the ordinary rules'
);

-- A terminal with no place.
select pg_temp.punch('TAT-0004', '910017',
  current_setting('ta.d1') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0004', current_setting('ta.d1'), '910017')
    - 'id' - 'terminal_id' - 'decided_at' - 'work_date'
    - 'first_punched_at_local' - 'last_punched_at_local' - 'punch_count',
  jsonb_build_object(
    'device_user_id', '910017', 'team_id', null,
    'worker_id', pg_temp.w(17), 'finding', 'no_place', 'added', false,
    'watching', true),
  'A check-in on a terminal with no place is listed, at no place'
);

-- A confirmed month.
select public.v1_wf_set_terminal_mode('TAT-0005', 'add');
insert into public.v1_workforce_month_confirmations (
  team_id, period_month, is_confirmed, confirmed_by_auth_user_id, confirmed_at
) values (
  current_setting('ta.store')::uuid,
  date_trunc('month', current_setting('ta.d1')::date)::date, true,
  '10000000-0000-4000-8000-000000000004', clock_timestamp()
);
select pg_temp.punch('TAT-0005', '910017',
  current_setting('ta.d1') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0005', current_setting('ta.d1'), '910017') ->> 'finding',
  'month_confirmed', 'A check-in in a confirmed month is listed');
select is(pg_temp.sheet(current_setting('ta.store'), current_setting('ta.d1')),
  null, 'and the confirmed month gets no day');

-- Never overtime ---------------------------------------------------------------

select public.v1_wf_set_terminal_mode('TAT-0003', 'add');
-- A usual shift of 12 hours with a lunch break: the line stops at 8 worked
-- hours.
update public.v1_workforce_crew_profiles
set shift_start_minute = 360, shift_finish_minute = 1080,
    break_start_minute = 720, break_finish_minute = 780
where team_id = current_setting('ta.yard')::uuid;
select pg_temp.punch('TAT-0003', '910007',
  current_setting('ta.d1') || ' 05:50:00');
select is(
  pg_temp.line(current_setting('ta.yard'), current_setting('ta.d1'),
    pg_temp.w(7)) - 'id' - 'sheet_id' - 'updated_at' - 'team_id' - 'work_date'
    - 'worker_id' - 'terminal_id' - 'work_label' - 'overtime_note' - 'copied'
    - 'changed_after_entry' - 'updated_by_auth_user_id',
  jsonb_build_object(
    'attendance_status', 'P', 'start_minute', 360, 'finish_minute', 900,
    'break_start_minute', 720, 'break_finish_minute', 780,
    'work_project_id', null, 'work_scope_id', null,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0, 'holiday_overtime_minutes', 0),
  'On a 12-hour usual shift the terminal''s line stops at 8 worked hours, break included: no overtime'
);
-- A break that starts after those 8 hours is left out.
update public.v1_workforce_crew_profiles
set break_start_minute = 900, break_finish_minute = 960
where team_id = current_setting('ta.yard')::uuid;
select pg_temp.punch('TAT-0003', '910008',
  current_setting('ta.d1') || ' 06:00:00');
select is(
  pg_temp.line(current_setting('ta.yard'), current_setting('ta.d1'),
    pg_temp.w(8)) - 'id' - 'sheet_id' - 'updated_at' - 'team_id' - 'work_date'
    - 'worker_id' - 'terminal_id' - 'work_label' - 'overtime_note' - 'copied'
    - 'changed_after_entry' - 'updated_by_auth_user_id' - 'work_project_id'
    - 'work_scope_id' - 'holiday_overtime_minutes',
  jsonb_build_object(
    'attendance_status', 'P', 'start_minute', 360, 'finish_minute', 840,
    'break_start_minute', null, 'break_finish_minute', null,
    'worked_minutes', 480, 'regular_minutes', 480,
    'normal_overtime_minutes', 0),
  'A break outside those 8 hours is left out'
);
-- A shorter usual shift stays shorter.
update public.v1_workforce_crew_profiles
set shift_start_minute = 360, shift_finish_minute = 720,
    break_start_minute = null, break_finish_minute = null
where team_id = current_setting('ta.yard')::uuid;
select pg_temp.punch('TAT-0003', '910009',
  current_setting('ta.d1') || ' 06:00:00');
select is(
  (pg_temp.line(current_setting('ta.yard'), current_setting('ta.d1'),
    pg_temp.w(9)) ->> 'worked_minutes')::integer,
  360, 'A usual shift of 6 hours gives a line of 6 hours');
select is(
  (select max(day_row.worked_minutes)
   from public.v1_workforce_day_rows day_row
   where day_row.updated_by_auth_user_id is null),
  480, 'No terminal line anywhere is longer than 8 hours');
select is(
  (select count(*)::integer
   from public.v1_workforce_day_rows day_row
   where day_row.updated_by_auth_user_id is null
     and (day_row.normal_overtime_minutes > 0
       or day_row.holiday_overtime_minutes > 0
       or day_row.attendance_status <> 'P')),
  0, 'and none carries overtime or anything but Present');
select throws_ok(
  format(
    $$insert into public.v1_workforce_day_rows (
        sheet_id, team_id, work_date, worker_id, attendance_status,
        start_minute, finish_minute, worked_minutes, terminal_id)
      select sheet.id, sheet.team_id, sheet.work_date, '%s'::uuid, 'P',
        360, 900, 540, terminal.id
      from public.v1_workforce_day_sheets sheet,
        public.v1_workforce_terminals terminal
      where sheet.team_id = current_setting('ta.yard')::uuid
        and sheet.work_date = current_setting('ta.d1')::date
        and terminal.serial_number = 'TAT-0003'$$, pg_temp.w(10)),
  '23514', null,
  'The table itself refuses a terminal line of more than 8 hours'
);
select throws_ok(
  format(
    $$insert into public.v1_workforce_day_rows (
        sheet_id, team_id, work_date, worker_id, attendance_status,
        terminal_id)
      select sheet.id, sheet.team_id, sheet.work_date, '%s'::uuid, 'A',
        terminal.id
      from public.v1_workforce_day_sheets sheet,
        public.v1_workforce_terminals terminal
      where sheet.team_id = current_setting('ta.yard')::uuid
        and sheet.work_date = current_setting('ta.d1')::date
        and terminal.serial_number = 'TAT-0003'$$, pg_temp.w(10)),
  '23514', null,
  'and a terminal line that is not Present'
);

-- The terminal wrote no history of its own: the punch log is its record.
select is(
  (select count(*)::integer from public.v1_workforce_attendance_events
   where team_id in (
     current_setting('ta.yard')::uuid, current_setting('ta.place2')::uuid)),
  0, 'A terminal writes no attendance event');
select is(
  pg_temp.sheet(current_setting('ta.yard'), current_setting('ta.d1'))
    -> 'record_version',
  '0'::jsonb, 'Three terminal lines later the yard''s day is still at version 0');

-- Who sees and changes a day with terminal lines -----------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement does not read a day, terminal lines or not'
);
select throws_ok(
  $$select pg_temp.save(current_setting('ta.place1'), current_setting('ta.d1'),
    '[]'::jsonb, 4, 'No')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'or save one'
);
select throws_ok(
  $$select public.v1_wf_save_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date,
    '[]'::jsonb, 4, 'No', gen_random_uuid(), array[pg_temp.w(6)::uuid])$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'or remove a terminal''s line'
);
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_days$$,
  '42501', null, 'Procurement cannot read what terminals did from the table');

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_wf_get_day(
    current_setting('ta.place2')::uuid, current_setting('ta.d1')::date)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Engineer does not read the terminal''s day on a project they are not on'
);
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_days$$,
  '42501', null, 'or the table');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_users$$,
  '42501', null, 'or the matches');
select is(
  (public.v1_wf_get_day(
    current_setting('ta.place1')::uuid, current_setting('ta.d1')::date
  ) -> 'terminal' ->> 'adding')::boolean,
  true, 'On their own project they read the day and its terminal');

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_days$$,
  '42501', null, 'A Site Engineer cannot read the table either');
select throws_ok(
  $$insert into public.v1_workforce_terminal_users (
      device_user_id, worker_id, follows_number, confirmed_by_auth_user_id,
      confirmed_by_role)
    values ('31', pg_temp.w(26)::uuid, false,
      '10000000-0000-4000-8000-000000000002', 'site_engineer')$$,
  '42501', null, 'or write a match into it');

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_days$$,
  '42501', null, 'Admin reads it through the day, not the table');
select is(
  (select jsonb_agg(entry ->> 'finding' order by entry ->> 'device_user_id')
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('ta.place2')::uuid, current_setting('ta.d1')::date
   ) -> 'terminal' -> 'entries') entry),
  '["elsewhere", "elsewhere", "outside_shift", "outside_shift", "staff", "not_active", "unmatched"]'::jsonb,
  'Admin reads every check-in that is not a line, with why'
);
select lives_ok(
  $$select public.v1_wf_save_day(
    current_setting('ta.place2')::uuid, current_setting('ta.d1')::date,
    pg_temp.day_rows(current_setting('ta.place2'), current_setting('ta.d1'),
      array[pg_temp.w(12)]),
    0, 'Came for a delivery only', gen_random_uuid(),
    array[pg_temp.w(12)::uuid])$$,
  'Admin removes a terminal''s line with a reason'
);
select is(
  (public.v1_wf_get_day(
    current_setting('ta.place2')::uuid, current_setting('ta.d1')::date
  ) ->> 'entered_by'),
  current_setting('ta.admin_name'),
  'and by saving, enters the day the terminal opened'
);

-- The other readers name the terminal too.
select is(
  (select entry ->> 'entered_by'
   from jsonb_array_elements(public.v1_wf_get_month_sheet(
     current_setting('ta.yard')::uuid, current_setting('ta.d1')::date
   ) -> 'sheets') entry
   where entry ->> 'date' = current_setting('ta.d1')),
  'Yard gate', 'The monthly sheet names the terminal as who entered a day');
select is(
  (select day_entry ->> 'updated_by'
   from jsonb_array_elements(public.v1_wf_get_month_sheet(
     current_setting('ta.yard')::uuid, current_setting('ta.d1')::date
   ) -> 'workers') worker_entry,
   jsonb_array_elements(worker_entry -> 'days') day_entry
   where worker_entry ->> 'id' = pg_temp.w(7)),
  'Yard gate', 'and as who saved a line');
select is(
  (select entry ->> 'updated_by'
   from jsonb_array_elements(public.v1_wf_worker_month(
     pg_temp.w(7)::uuid, current_setting('ta.d1')::date
   ) -> 'rows') entry
   where entry ->> 'date' = current_setting('ta.d1')),
  'Yard gate', 'So does the labourer''s time sheet');
reset role;
select is(
  public.v1_wf_today_json(
    current_setting('ta.yard')::uuid, current_setting('ta.d1')::date
  ) - 'last_saved_at' - 'date',
  jsonb_build_object(
    'entered', true, 'entered_by', 'Yard gate', 'last_saved_by', 'Yard gate',
    'present', 3, 'absent', 0, 'leave', 0, 'rest', 0),
  'and the overview''s line for a place'
);

-- A line that cannot be added never fails the terminal -----------------------

create function pg_temp.refuse_line()
returns trigger
language plpgsql
as $$
begin
  raise exception 'TEST_LINE_REFUSED';
end;
$$;
create trigger ta_refuse_line
before insert on public.v1_workforce_day_rows
for each row
when (new.worker_id = '7a020000-0000-4000-8000-000000000018'::uuid)
execute function pg_temp.refuse_line();

select is(
  pg_temp.punch('TAT-0001', '910018', current_setting('ta.d1') || ' 06:30:00'),
  jsonb_build_object(
    'outcome', 'ok', 'received', 1, 'stored', 1, 'duplicates', 0,
    'rejected', 0),
  'When a line cannot be added the check-in is still stored and the terminal still told OK'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminal_punches
   where device_user_id = '910018'),
  1, 'The check-in is in the punch log');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910018') ->> 'finding',
  'error', 'It is marked as not applied');
select is(
  (select request.details ->> 'note'
   from public.v1_workforce_terminal_requests request
   where request.endpoint = 'punches'
   order by request.id desc limit 1),
  'attendance not applied, kept for retry',
  'and the diagnostic log says so'
);
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(18)),
  null, 'No line was added');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(1)) ->> 'finish_minute',
  '1020', 'and nothing else on the day changed');

drop trigger ta_refuse_line on public.v1_workforce_day_rows;
-- Another labourer checks in: the line that failed is tried again.
select pg_temp.punch('TAT-0001', '910010',
  current_setting('ta.d1') || ' 06:31:00');
select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910018')
    - 'id' - 'terminal_id' - 'decided_at' - 'work_date' - 'device_user_id'
    - 'team_id' - 'worker_id' - 'first_punched_at_local'
    - 'last_punched_at_local' - 'punch_count',
  jsonb_build_object('finding', 'add', 'added', true, 'watching', false),
  'With the terminal''s next upload the line is added'
);
select isnt(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(18)),
  null, 'It is on the day');

-- A match confirmed late; a terminal that moves ------------------------------

select is(
  pg_temp.found('TAT-0001', current_setting('ta.d1'), '910026') ->> 'finding',
  'unmatched', 'Labourer 26 checked in before their ID was confirmed');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select lives_ok(
  format(
    $$select public.v1_wf_confirm_terminal_users(
      '[{"device_user_id": "910026", "worker_id": "%s"}]'::jsonb,
      gen_random_uuid())$$, pg_temp.w(26)),
  'Admin confirms the ID later that day'
);
reset role;
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(26)),
  null, 'Confirming an ID changes no day by itself');
select is(
  public.v1_wf_terminal_apply_day('TAT-0001', current_setting('ta.d1')::date)
    ->> 'added_now',
  '1', 'The operator decides the day again and the line is added');
select is(
  pg_temp.line(current_setting('ta.place1'), current_setting('ta.d1'),
    pg_temp.w(26)) ->> 'start_minute',
  '390', 'on the usual shift');

select is(
  public.v1_wf_register_terminal(
    'TAT-0001', 'Site gate', current_setting('ta.key_place1'))
    ->> 'attendance_mode',
  'add', 'Registering a terminal again at the same place keeps it adding');
select is(
  public.v1_wf_register_terminal(
    'TAT-0002', 'Second gate', current_setting('ta.key_yard'))
    ->> 'attendance_mode',
  'watch', 'A terminal moved to another place goes back to watching');
select is(
  public.v1_wf_register_terminal('TAT-0003', 'Yard gate')
    ->> 'attendance_mode',
  'watch', 'and so does one given no place');
select pg_temp.punch('TAT-0002', '910024',
  current_setting('ta.d1') || ' 06:20:00');
select is(
  pg_temp.found('TAT-0002', current_setting('ta.d1'), '910024') ->> 'finding',
  'unmatched', 'The moved terminal only watches');
select is(
  pg_temp.lines(current_setting('ta.yard'), current_setting('ta.d1')),
  3, 'and adds nothing at its new place');

-- Nothing here wrote under a person's name by mistake.
select is(
  (select count(*)::integer from public.v1_workforce_day_rows day_row
   where day_row.terminal_id is not null
     and day_row.updated_by_auth_user_id is not null
     and day_row.worker_id not in (
       pg_temp.w(1)::uuid, pg_temp.w(3)::uuid)),
  0,
  'Only the two lines people changed carry a person''s name; every other terminal line is the terminal''s'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- A labourer at several places in a day, sheets kept by the people at each
-- place, and the new month confirmers (PRODUCT_DECISIONS section 46).
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- SME ...0009, PM ...0010 (also played as Workshop In-Charge and Document
-- Controller), Accountant ...0013, PR ...0014. Fictional fixtures only.

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

-- Plays the ...0010 persona in another role.
create function pg_temp.as_role(p_role text)
returns void
language plpgsql
as $$
begin
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', p_role)
  where id = '10000000-0000-4000-8000-000000000010';
end;
$$;

-- A sheet's access as the app reads it (the crew list); none when unseen.
create function pg_temp.access(p_team uuid)
returns jsonb
language sql
as $$
  select coalesce(
    (select crew -> 'access'
     from jsonb_array_elements(public.v1_wf_list_crews() -> 'crews') crew
     where crew ->> 'id' = p_team::text),
    '{"view": false, "take": false, "confirm": false, "manage": false, "officer": false, "keeper": false}'::jsonb
  );
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

create function pg_temp.row_s(p_worker text, p_status text)
returns jsonb
language sql
as $$
  select jsonb_build_object('worker_id', p_worker, 'status', p_status);
$$;

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('6d010000-0000-4000-8000-000000000001', 'MP-001', 'Multi place A',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin'),
  ('6d010000-0000-4000-8000-000000000002', 'MP-002', 'Multi place B',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('6d010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Multi place test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('6d010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'Multi place test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  -- The Site Engineer is the Project Engineer of project B.
  ('6d010000-0000-4000-8000-000000000002',
   '10000000-0000-4000-8000-000000000002', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Multi place test',
   '10000000-0000-4000-8000-000000000004', 'admin');

-- Labourers 1-5 and one staff member (6).
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('6d020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'MP-' || n, 'Place Worker ' || n,
  case when n = 6 then 'Engineer' else 'Helper' end,
  'Example Manpower LLC', 'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 6) n;
insert into public.v1_people_profiles (
  worker_id, category, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values
  ('6d020000-0000-4000-8000-000000000005', 'labour',
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('6d020000-0000-4000-8000-000000000006', 'staff',
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');

-- The most recent working day and the most recent Sunday before today.
select set_config('mp.day', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc limit 1
), true);
select set_config('mp.sunday', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where extract(isodow from series.day_ts) = 7
  order by series.day_ts desc limit 1
), true);

-- Who keeps sheets ----------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP site A","kind":"project","project_id":"6d010000-0000-4000-8000-000000000001","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000001')$$,
  'A Site Engineer keeps a sheet for a project they are on, with nobody setting it up'
);
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP store","kind":"workshop","work_label":"Store","needs_confirmation":true,"shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000002')$$,
  'A Site Engineer keeps a sheet for an internal location'
);
select is(
  (public.v1_wf_list_crews() ->> 'can_create_crew')::boolean, true,
  'A Site Engineer may create sheets'
);

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP procurement","kind":"workshop","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000003')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED', 'Procurement does not keep sheets'
);
select is(
  (public.v1_wf_list_crews() ->> 'can_create_crew')::boolean, false,
  'Procurement is not offered New crew'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP accountant","kind":"workshop","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000004')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED', 'The Accountant does not keep sheets'
);

reset role;
select pg_temp.as_role('document_controller');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'document_controller');
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP dc","kind":"workshop","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000005')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED', 'A Document Controller does not keep sheets'
);
reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP workshop","kind":"workshop","work_label":"Workshop","needs_confirmation":false,"shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000006')$$,
  'A Workshop In-Charge keeps the workshop sheet'
);

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"MP site B","kind":"project","project_id":"6d010000-0000-4000-8000-000000000002","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '6d030000-0000-4000-8000-000000000007')$$,
  'Admin keeps a sheet for any project'
);

reset role;
select set_config('mp.a', (select id::text from public.v1_workforce_teams where team_name = 'MP site A'), true);
select set_config('mp.store', (select id::text from public.v1_workforce_teams where team_name = 'MP store'), true);
select set_config('mp.workshop', (select id::text from public.v1_workforce_teams where team_name = 'MP workshop'), true);
select set_config('mp.b', (select id::text from public.v1_workforce_teams where team_name = 'MP site B'), true);
set local role authenticated;

-- Seeing and keeping a sheet ------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  pg_temp.access(current_setting('mp.store')::uuid)
    - 'officer',
  '{"view": true, "take": true, "confirm": false, "manage": true, "keeper": true}'::jsonb,
  'The keeper sees, takes and manages their sheet, and does not confirm it'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  (pg_temp.access(current_setting('mp.store')::uuid) ->> 'view')::boolean,
  false,
  'Another engineer does not see someone else''s location sheet'
);
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'take')::boolean,
  true,
  'An engineer on the project takes attendance on a colleague''s project sheet'
);
reset role;
select pg_temp.as_role('document_controller');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'document_controller');
select is(
  pg_temp.access(current_setting('mp.a')::uuid)
    - 'officer' - 'keeper',
  '{"view": true, "take": false, "confirm": false, "manage": false}'::jsonb,
  'A Document Controller reads every sheet and does not take or confirm'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'take')::boolean,
  false,
  'The Accountant reads and does not take attendance'
);

-- Who confirms the month ----------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'confirm')::boolean,
  true, 'The project''s Project Engineer confirms its sheet'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select ok(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'confirm')::boolean
  and (pg_temp.access(current_setting('mp.store')::uuid) ->> 'confirm')::boolean,
  'A Senior Mechanical Engineer confirms project and location sheets'
);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'confirm')::boolean,
  true, 'Admin confirms as an override'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'confirm')::boolean,
  false, 'A Site Engineer on the project does not confirm'
);
select is(
  (pg_temp.access(current_setting('mp.b')::uuid) ->> 'confirm')::boolean,
  true, 'A Site Engineer who is the project''s Project Engineer confirms'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  (pg_temp.access(current_setting('mp.b')::uuid) ->> 'confirm')::boolean,
  false, 'A Project Engineer of another project does not confirm'
);
reset role;
select pg_temp.as_role('project_manager');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'project_manager');
select is(
  (pg_temp.access(current_setting('mp.a')::uuid) ->> 'confirm')::boolean,
  false, 'A Project Manager no longer confirms'
);
reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select is(
  (pg_temp.access(current_setting('mp.store')::uuid) ->> 'confirm')::boolean,
  false, 'A Workshop In-Charge no longer confirms'
);

-- Labour on several sheets --------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  format($$select public.v1_wf_set_crew_members(%L::uuid, array[
      '6d020000-0000-4000-8000-000000000001',
      '6d020000-0000-4000-8000-000000000002']::uuid[], null,
      '6d030000-0000-4000-8000-000000000011')$$, current_setting('mp.a')),
  'Labourers join the site sheet'
);
select lives_ok(
  format($$select public.v1_wf_set_crew_members(%L::uuid, array[
      '6d020000-0000-4000-8000-000000000001',
      '6d020000-0000-4000-8000-000000000003',
      '6d020000-0000-4000-8000-000000000005']::uuid[], null,
      '6d030000-0000-4000-8000-000000000012')$$, current_setting('mp.store')),
  'The same labourer joins the store sheet without leaving the site'
);
select throws_ok(
  format($$select public.v1_wf_set_crew_members(%L::uuid, array[
      '6d020000-0000-4000-8000-000000000006']::uuid[], null,
      '6d030000-0000-4000-8000-000000000013')$$, current_setting('mp.a')),
  '22023', 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS', 'Staff are not put on attendance sheets'
);
select is(
  jsonb_array_length((
    select worker -> 'crews'
    from jsonb_array_elements(public.v1_wf_list_workers() -> 'workers') worker
    where worker ->> 'id' = '6d020000-0000-4000-8000-000000000001'
  )),
  2, 'The labourer is on both sheets'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.v1_wf_list_workers() -> 'workers') worker
    where worker ->> 'id' = '6d020000-0000-4000-8000-000000000006'
  ) and exists (
    select 1
    from jsonb_array_elements(public.v1_wf_list_workers() -> 'workers') worker
    where worker ->> 'id' = '6d020000-0000-4000-8000-000000000005'
      and worker ->> 'category' = 'labour'
  ),
  'The worker search offers labour only'
);

-- One day at two places -----------------------------------------------------

-- Site: worker 1 from 6:30 to 12:00 (5.5 h); worker 2 absent.
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 390, 720),
      pg_temp.row_s('6d020000-0000-4000-8000-000000000002', 'A')), 0, null,
      '6d030000-0000-4000-8000-000000000021')$$,
    current_setting('mp.a'), current_setting('mp.day')),
  'The site records the morning'
);
-- The store: worker 1 is not required (present at the site) and worker 3 is.
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000005', 390, 1020)), 0, null,
      '6d030000-0000-4000-8000-000000000022')$$,
    current_setting('mp.store'), current_setting('mp.day')),
  '22023', 'V1_WORKFORCE_DAY_UNMARKED',
  'A member with no entry anywhere still has to be marked'
);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000003', 390, 1020),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000005', 390, 1020)), 0, null,
      '6d030000-0000-4000-8000-000000000023')$$,
    current_setting('mp.store'), current_setting('mp.day')),
  'A member recorded at another place may be left off this sheet'
);
select is(
  (select jsonb_array_length(entry -> 'elsewhere')
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('mp.store')::uuid, current_setting('mp.day')::date
   ) -> 'rows') entry
   where entry ->> 'worker_id' = '6d020000-0000-4000-8000-000000000001'),
  1, 'The store sees where else the worker is that day'
);
select is(
  (select entry -> 'elsewhere' -> 0 ->> 'crew_name'
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('mp.store')::uuid, current_setting('mp.day')::date
   ) -> 'rows') entry
   where entry ->> 'worker_id' = '6d020000-0000-4000-8000-000000000001'),
  'MP site A', 'It names the other place'
);
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 660, 900),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000003', 390, 1020),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000005', 390, 1020)), 1, null,
      '6d030000-0000-4000-8000-000000000024')$$,
    current_setting('mp.store'), current_setting('mp.day')),
  '22023', 'V1_WORKFORCE_TIME_OVERLAP',
  'Times at two places cannot overlap'
);
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_s('6d020000-0000-4000-8000-000000000001', 'SL'),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000003', 390, 1020),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000005', 390, 1020)), 1, null,
      '6d030000-0000-4000-8000-000000000025')$$,
    current_setting('mp.store'), current_setting('mp.day')),
  '22023', 'V1_WORKFORCE_WORKER_PRESENT_ELSEWHERE',
  'A worker present at one place cannot be on leave at another'
);
-- The afternoon at the store: 1 PM to 7 PM (6 h). Whole day 11.5 h:
-- 5.5 normal at the site, 2.5 normal + 3.5 overtime at the store.
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 780, 1140),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000003', 390, 1020),
      pg_temp.row_p('6d020000-0000-4000-8000-000000000005', 390, 1020)), 1, null,
      '6d030000-0000-4000-8000-000000000026')$$,
    current_setting('mp.store'), current_setting('mp.day')),
  'The store records the afternoon'
);
reset role;
select is(
  (select array_agg(array[regular_minutes, normal_overtime_minutes]
     order by start_minute)
   from public.v1_workforce_day_rows
   where worker_id = '6d020000-0000-4000-8000-000000000001'
     and work_date = current_setting('mp.day')::date),
  array[array[330, 0], array[150, 210]],
  'The first 8 hours of the day are normal; the rest is overtime at the later place'
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');

-- The site starts earlier: 5 AM to 12 PM (7 h). The store's split follows.
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 300, 720),
      pg_temp.row_s('6d020000-0000-4000-8000-000000000002', 'A')), 1, null,
      '6d030000-0000-4000-8000-000000000027')$$,
    current_setting('mp.a'), current_setting('mp.day')),
  'The site corrects the morning'
);
reset role;
select is(
  (select array_agg(array[regular_minutes, normal_overtime_minutes]
     order by start_minute)
   from public.v1_workforce_day_rows
   where worker_id = '6d020000-0000-4000-8000-000000000001'
     and work_date = current_setting('mp.day')::date),
  array[array[420, 0], array[60, 300]],
  'A change at one place recounts the whole day'
);
select is(
  (select sum(regular_minutes)::integer
   from public.v1_workforce_day_rows
   where worker_id = '6d020000-0000-4000-8000-000000000001'
     and work_date = current_setting('mp.day')::date),
  480, 'Never more than 8 normal hours in a day'
);

-- Up to three places a day.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 1145, 1200)), 0, null,
      '6d030000-0000-4000-8000-000000000028')$$,
    current_setting('mp.b'), current_setting('mp.day')),
  'A third place the same day'
);
reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 1205, 1260)), 0, null,
      '6d030000-0000-4000-8000-000000000029')$$,
    current_setting('mp.workshop'), current_setting('mp.day')),
  '22023', 'V1_WORKFORCE_TOO_MANY_PLACES',
  'A fourth place the same day is refused'
);
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000006', 390, 1020)), 0, null,
      '6d030000-0000-4000-8000-000000000030')$$,
    current_setting('mp.workshop'), current_setting('mp.day')),
  '22023', 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS',
  'Staff cannot be added to a day'
);

-- A confirmed month at one place is never changed by another.
reset role;
insert into public.v1_workforce_month_confirmations (
  team_id, period_month, is_confirmed, confirmed_by_auth_user_id, confirmed_at
) values (
  current_setting('mp.store')::uuid,
  date_trunc('month', current_setting('mp.day')::date)::date,
  true, '10000000-0000-4000-8000-000000000009', clock_timestamp()
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 390, 720),
      pg_temp.row_s('6d020000-0000-4000-8000-000000000002', 'A')), 2, null,
      '6d030000-0000-4000-8000-000000000031')$$,
    current_setting('mp.a'), current_setting('mp.day')),
  '55000', 'V1_WORKFORCE_OTHER_PLACE_LOCKED',
  'A change that would recount a confirmed place is refused'
);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 300, 720),
      pg_temp.row_s('6d020000-0000-4000-8000-000000000002', 'SL')), 2, null,
      '6d030000-0000-4000-8000-000000000032')$$,
    current_setting('mp.a'), current_setting('mp.day')),
  'A change that leaves the confirmed place as it is is saved'
);

-- A Sunday at two places is all holiday overtime.
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 420, 660),
      pg_temp.row_s('6d020000-0000-4000-8000-000000000002', 'OFF')), 0, null,
      '6d030000-0000-4000-8000-000000000033')$$,
    current_setting('mp.a'), current_setting('mp.sunday')),
  'A Sunday morning at the site'
);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, jsonb_build_array(
      pg_temp.row_p('6d020000-0000-4000-8000-000000000001', 720, 960)), 0, null,
      '6d030000-0000-4000-8000-000000000034')$$,
    current_setting('mp.b'), current_setting('mp.sunday')),
  'A Sunday afternoon at another site'
);
reset role;
select is(
  (select array_agg(array[regular_minutes, normal_overtime_minutes,
     holiday_overtime_minutes] order by start_minute)
   from public.v1_workforce_day_rows
   where worker_id = '6d020000-0000-4000-8000-000000000001'
     and work_date = current_setting('mp.sunday')::date),
  array[array[0, 0, 240], array[0, 0, 240]],
  'Every hour on a Sunday is holiday overtime, at every place'
);

-- Nothing new is callable directly.
select ok(
  not has_function_privilege('authenticated',
    'public.v1_wf_recompute_worker_day(uuid,date)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_wf_elsewhere_json(uuid,date,uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_wf_is_labour(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)', 'execute'),
  'The helpers are internal and anonymous callers have nothing'
);

select * from finish();
rollback;

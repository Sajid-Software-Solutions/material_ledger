begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Attendance by role (PRODUCT_DECISIONS section 58): the Accountant keeps
-- attendance as HR/PRO does; internal places (workshop, store, camp) are kept
-- only by the Workshop In-Charge, HR/PRO, the Accountant and Admin; everything
-- else about who sees, takes, confirms and reopens is unchanged.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- Senior Mechanical Engineer ...0009, ...0010 played as Workshop In-Charge,
-- Project Manager and Document Controller, Accountant ...0013, PR ...0014.
-- Fictional fixtures only.

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

-- Plays user ...0010 as p_role (runs as the test owner, then returns).
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

-- Access without the keeper flag, which only says who opened the sheet.
create function pg_temp.access(p_team text)
returns jsonb
language sql
as $$
  select coalesce(
    (select crew -> 'access'
     from jsonb_array_elements(public.v1_wf_list_crews() -> 'crews') crew
     where crew ->> 'id' = p_team),
    '{"view": false, "take": false, "confirm": false, "manage": false, "officer": false}'::jsonb
  ) - 'keeper';
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

create function pg_temp.version(p_team text, p_date text)
returns bigint
language sql
as $$
  select (public.v1_wf_get_day(p_team::uuid, p_date::date)
    ->> 'record_version')::bigint;
$$;

create function pg_temp.expect(
  p_view boolean, p_take boolean, p_confirm boolean, p_manage boolean,
  p_officer boolean
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'view', p_view, 'take', p_take, 'confirm', p_confirm,
    'manage', p_manage, 'officer', p_officer
  );
$$;

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('6f010000-0000-4000-8000-000000000001', 'BR-001', 'Role site one',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin'),
  ('6f010000-0000-4000-8000-000000000002', 'BR-002', 'Role site two',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('6f010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'By role test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('6f010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'By role test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('6f020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'BR-' || n, 'Role Labourer ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 4) n;

-- The two most recent working days before today.
select set_config('br.day', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc limit 1
), true);
select set_config('br.day2', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc offset 1 limit 1
), true);

-- An internal sheet a Site Engineer created before the rule, with a saved
-- day: it stays exactly as saved.
insert into public.v1_workforce_teams (
  id, team_code, team_name, valid_from, created_by_auth_user_id,
  updated_by_auth_user_id
) values (
  '6f040000-0000-4000-8000-000000000001', 'BR-LEGACY', 'BR old store',
  public.v1_wf_today() - 60, '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000002'
);
insert into public.v1_workforce_crew_profiles (
  team_id, crew_kind, needs_confirmation, shift_start_minute,
  shift_finish_minute, created_by_auth_user_id, updated_by_auth_user_id
) values (
  '6f040000-0000-4000-8000-000000000001', 'workshop', false, 390, 870,
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000002'
);
insert into public.v1_workforce_day_sheets (
  team_id, work_date, entered_by_auth_user_id, entered_at,
  last_saved_by_auth_user_id, last_saved_at
) values (
  '6f040000-0000-4000-8000-000000000001', current_setting('br.day2')::date,
  '10000000-0000-4000-8000-000000000002', clock_timestamp(),
  '10000000-0000-4000-8000-000000000002', clock_timestamp()
);
insert into public.v1_workforce_day_rows (
  sheet_id, team_id, work_date, worker_id, attendance_status,
  start_minute, finish_minute, updated_by_auth_user_id
)
select sheet.id, sheet.team_id, sheet.work_date,
  '6f020000-0000-4000-8000-000000000004', 'P', 390, 870,
  '10000000-0000-4000-8000-000000000002'
from public.v1_workforce_day_sheets sheet
where sheet.team_id = '6f040000-0000-4000-8000-000000000001';
select set_config('br.legacy', '6f040000-0000-4000-8000-000000000001', true);

-- Opening the places --------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('br.site', (
  public.v1_wf_open_place('6f010000-0000-4000-8000-000000000001', null) ->> 'id'
), true);
select isnt(current_setting('br.site', true), null,
  'A Site Engineer opens a project they are on');
select throws_ok(
  $$select public.v1_wf_open_place(null, 'Workshop')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot open an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_wf_open_place(null, 'Workshop')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Engineer cannot open an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_wf_open_place(null, 'Workshop')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Senior Mechanical Engineer cannot open an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'project_manager');
select throws_ok(
  $$select public.v1_wf_open_place(null, 'Workshop')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Manager cannot open an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_open_place(null, 'Workshop')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement cannot open a place'
);

reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select set_config('br.ws', (
  public.v1_wf_open_place(null, 'Workshop') ->> 'id'
), true);
select isnt(current_setting('br.ws', true), null,
  'The Workshop In-Charge opens the workshop');
select is(
  public.v1_wf_open_place('6f010000-0000-4000-8000-000000000002', null) -> 'access' ->> 'take',
  'true',
  'The Workshop In-Charge also opens and keeps a project he is not on'
);
reset role;
select is(
  (select needs_confirmation from public.v1_workforce_crew_profiles
   where team_id = current_setting('br.ws')::uuid),
  false,
  'The workshop needs no month confirmation'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  public.v1_wf_open_place(null, 'workshop') ->> 'id',
  current_setting('br.ws'),
  'The Accountant opens the same workshop'
);
select lives_ok(
  $$select public.v1_wf_open_place(null, 'Labour Camp')$$,
  'The Accountant may add an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select lives_ok(
  $$select public.v1_wf_open_place(null, 'Main Store')$$,
  'HR/PRO may add an internal place'
);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  public.v1_wf_open_place(null, 'Workshop') ->> 'id',
  current_setting('br.ws'),
  'Admin opens the workshop'
);

-- Who may add an internal place --------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, false,
  'Site Engineer: no new internal place');
select is(jsonb_array_length(public.v1_wf_list_places() -> 'locations'), 0,
  'Site Engineer: no internal place listed');
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, false,
  'Project Engineer: no new internal place');
select is(jsonb_array_length(public.v1_wf_list_places() -> 'locations'), 0,
  'Project Engineer: no internal place listed');
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, false,
  'Senior Mechanical Engineer: no new internal place');
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.v1_wf_list_places() -> 'locations') place
    where (place ->> 'can_take')::boolean
  ) and jsonb_array_length(public.v1_wf_list_places() -> 'locations') >= 1,
  'Senior Mechanical Engineer: internal places are listed to read only'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, true,
  'Accountant: may add an internal place');
select ok(
  (public.v1_wf_list_places() ->> 'can_take')::boolean
  and not exists (
    select 1 from jsonb_array_elements(public.v1_wf_list_places() -> 'projects') place
    where not (place ->> 'can_take')::boolean
  ),
  'Accountant: keeps attendance at every project'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, true,
  'HR/PRO: may add an internal place');
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, true,
  'Admin: may add an internal place');
reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, true,
  'Workshop In-Charge: may add an internal place');
reset role;
select pg_temp.as_role('document_controller');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'document_controller');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, false,
  'Document Controller: no new internal place');

-- The access matrix: a project place and the workshop -------------------------
-- {view, take, confirm, manage, officer}. The project needs confirmation;
-- the workshop does not.

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, false, true, false),
  'Site Engineer on the project: sees and takes (keeps the place they opened)');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(false, false, false, false, false),
  'Site Engineer: nothing at the workshop');

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, true, true, false),
  'Project Engineer on the project: sees, takes, confirms, manages');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(false, false, false, false, false),
  'Project Engineer: nothing at the workshop');

select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, true, true, false),
  'Senior Mechanical Engineer: keeps and confirms every project');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, false, false, false, false),
  'Senior Mechanical Engineer: reads the workshop only');

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, false, false, false),
  'Accountant: keeps every project, never confirms, reopens or changes its settings');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, true, false, false, false),
  'Accountant: keeps the workshop');

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, false, true, true),
  'HR/PRO: keeps every project and reopens');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, true, false, true, true),
  'HR/PRO: keeps the workshop');

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, true, true, true),
  'Admin: keeps, confirms as an override and reopens');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, true, false, true, true),
  'Admin: keeps the workshop');

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(false, false, false, false, false),
  'Procurement: no project attendance');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(false, false, false, false, false),
  'Procurement: no workshop attendance');

reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, false, true, false),
  'Workshop In-Charge: keeps projects too, without confirming');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, true, false, true, false),
  'Workshop In-Charge: keeps the workshop');
select is(
  pg_temp.access(current_setting('br.legacy')) ->> 'take',
  'true',
  'Workshop In-Charge: keeps an old internal sheet someone else created'
);

reset role;
select pg_temp.as_role('project_manager');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'project_manager');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, true, false, true, false),
  'Project Manager: keeps every project, does not confirm');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, false, false, false, false),
  'Project Manager: reads the workshop only');

reset role;
select pg_temp.as_role('document_controller');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'document_controller');
select is(pg_temp.access(current_setting('br.site')),
  pg_temp.expect(true, false, false, false, false),
  'Document Controller: reads projects');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, false, false, false, false),
  'Document Controller: reads the workshop');

-- An old internal sheet a Site Engineer created ------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(pg_temp.access(current_setting('br.legacy')),
  pg_temp.expect(false, false, false, false, false),
  'The Site Engineer no longer keeps the internal sheet they created');
select throws_ok(
  format($$select public.v1_wf_get_day(%L::uuid, %L::date)$$,
    current_setting('br.legacy'), current_setting('br.day2')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'nor reads its days'
);
reset role;
select results_eq(
  format($$select worker_id::text, attendance_status, start_minute,
      finish_minute, updated_by_auth_user_id::text
    from public.v1_workforce_day_rows
    where team_id = %L::uuid$$, current_setting('br.legacy')),
  $$values ('6f020000-0000-4000-8000-000000000004'::text, 'P'::text, 390, 870,
    '10000000-0000-4000-8000-000000000002'::text)$$,
  'Its saved line stays exactly as saved, with who saved it'
);
set local role authenticated;

-- Sheets: creating an internal one ------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"BR SE store","kind":"workshop","shift_start_minute":390,"shift_finish_minute":870}'::jsonb,
      0, '6f030000-0000-4000-8000-000000000001')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot create an internal sheet'
);
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"BR SE site","kind":"project","project_id":"6f010000-0000-4000-8000-000000000001","shift_start_minute":390,"shift_finish_minute":870}'::jsonb,
      0, '6f030000-0000-4000-8000-000000000002')$$,
  'A Site Engineer still creates a sheet on a project they are on'
);
reset role;
select set_config('br.sesite', (
  select team.id::text from public.v1_workforce_teams team
  where team.team_name = 'BR SE site'
), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  format($$select public.v1_wf_save_crew(jsonb_build_object(
      'crew_id', %L, 'name', 'BR SE site', 'kind', 'workshop',
      'shift_start_minute', 390, 'shift_finish_minute', 870), 1,
      '6f030000-0000-4000-8000-000000000003')$$,
    current_setting('br.sesite')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Engineer cannot turn a project sheet into an internal one'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"BR accountant store","kind":"workshop","needs_confirmation":false,"shift_start_minute":390,"shift_finish_minute":870}'::jsonb,
      0, '6f030000-0000-4000-8000-000000000004')$$,
  'The Accountant creates an internal sheet'
);
select is((public.v1_wf_list_crews() ->> 'can_create_crew')::boolean, true,
  'The Accountant is offered New crew');
select is(
  (select crew -> 'access' ->> 'manage'
   from jsonb_array_elements(public.v1_wf_list_crews() -> 'crews') crew
   where crew ->> 'name' = 'BR accountant store'),
  'true',
  'and keeps the settings of a sheet they opened'
);

-- Saving days ---------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, 0, null,
      '6f030000-0000-4000-8000-000000000010')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 870))),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot save a workshop day'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, 0, null,
      '6f030000-0000-4000-8000-000000000011')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 870))),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Senior Mechanical Engineer cannot save a workshop day'
);

reset role;
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, 0, null,
      '6f030000-0000-4000-8000-000000000012')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 870),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000002', 390, 870))),
  'The Workshop In-Charge saves the workshop day'
);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb,
      %s, null, '6f030000-0000-4000-8000-000000000012')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 870),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000002', 390, 870)),
    0),
  'A retry with the same key is accepted'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_day_rows
   where team_id = current_setting('br.ws')::uuid
     and work_date = current_setting('br.day')::date),
  2,
  'and saves the lines once'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, %s, null,
      '6f030000-0000-4000-8000-000000000013')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 930),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000002', 390, 870)),
    pg_temp.version(current_setting('br.ws'), current_setting('br.day'))),
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'The Accountant needs a reason to change a line the Workshop In-Charge saved'
);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, %s,
      'Out at 15:30 per the gate log', '6f030000-0000-4000-8000-000000000014')$$,
    current_setting('br.ws'), current_setting('br.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 930),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000002', 390, 870),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000003', 390, 870)),
    pg_temp.version(current_setting('br.ws'), current_setting('br.day'))),
  'With a reason the Accountant corrects a line and adds a labourer'
);
reset role;
select results_eq(
  format($$select actor_exact_role, reason
    from public.v1_workforce_day_changes change
    join public.v1_workforce_day_sheets sheet on sheet.id = change.sheet_id
    where sheet.team_id = %L::uuid$$, current_setting('br.ws')),
  $$values ('accountant'::text, 'Out at 15:30 per the gate log'::text)$$,
  'Only the changed line is logged, with the Accountant and the reason'
);
select is(
  (select count(*)::integer from public.v1_notifications notification
   join public.v1_workforce_day_sheets sheet on sheet.id = notification.entity_id
   where notification.recipient_auth_user_id = '10000000-0000-4000-8000-000000000010'
     and notification.event_code = 'workforce_attendance_day_changed'
     and sheet.team_id = current_setting('br.ws')::uuid),
  1,
  'The Workshop In-Charge is told once that his line was changed'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, %s, null,
      '6f030000-0000-4000-8000-000000000015')$$,
    current_setting('br.site'), current_setting('br.day'),
    jsonb_build_array(pg_temp.row_p('6f020000-0000-4000-8000-000000000004', 390, 870)),
    coalesce(pg_temp.version(current_setting('br.site'), current_setting('br.day')), 0)),
  'The Accountant saves a project day'
);

-- The month: confirming, reopening and holidays stay where they were ----------

select throws_ok(
  format($$select public.v1_wf_confirm_month(%L::uuid, %L::date,
      '6f030000-0000-4000-8000-000000000020')$$,
    current_setting('br.site'), current_setting('br.day')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'The Accountant does not confirm a month'
);
select throws_ok(
  format($$select public.v1_wf_reopen_month(%L::uuid, %L::date, 'Recount',
      '6f030000-0000-4000-8000-000000000021')$$,
    current_setting('br.site'), current_setting('br.day')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'The Accountant does not reopen a month'
);
select throws_ok(
  $$select public.v1_wf_save_public_holiday(
      current_setting('br.day')::date + 40, 'Example holiday', false)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'The Accountant does not keep the holiday calendar'
);

-- A confirmed month stays locked for the Accountant.
reset role;
insert into public.v1_workforce_month_confirmations (
  team_id, period_month, is_confirmed, confirmed_by_auth_user_id, confirmed_at
) values (
  current_setting('br.site')::uuid,
  date_trunc('month', current_setting('br.day')::date)::date,
  true, '10000000-0000-4000-8000-000000000001', clock_timestamp()
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select throws_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, %s, null,
      '6f030000-0000-4000-8000-000000000022')$$,
    current_setting('br.site'), current_setting('br.day'),
    jsonb_build_array(pg_temp.row_p('6f020000-0000-4000-8000-000000000004', 390, 900)),
    pg_temp.version(current_setting('br.site'), current_setting('br.day'))),
  '55000', 'V1_WORKFORCE_MONTH_LOCKED',
  'A confirmed month is locked for the Accountant'
);

-- A per-person deny still removes the right ------------------------------------

reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, origin, reason,
  changed_by_auth_user_id
) values (
  '10000000-0000-4000-8000-000000000013', 'workforce.attendance.maintain',
  'deny', 'organization', 'permission_management', 'By role deny test',
  '10000000-0000-4000-8000-000000000004'
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(pg_temp.access(current_setting('br.ws')),
  pg_temp.expect(true, false, false, false, false),
  'An explicit deny takes attendance away from the Accountant');
select is((public.v1_wf_list_places() ->> 'can_add_location')::boolean, false,
  'and the offer of a new internal place');

-- No role template changes ---------------------------------------------------------

reset role;
select ok(
  not exists (
    select 1 from public.v1_permission_role_defaults
    where role_name in ('accountant', 'workshop_in_charge')
      and capability_key like 'workforce.%' and is_granted
  ),
  'Attendance by role changes no role template'
);
select ok(
  not has_function_privilege('authenticated',
    'public.v1_wf_role_keeps_internal(text)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_crew_access(uuid)', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_wf_list_places()', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_open_place(uuid,text)', 'execute'),
  'Helpers stay private; the commands stay signed-in only'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Attendance at places, with no crews to set up (PRODUCT_DECISIONS section
-- 51): who opens a place, one shared sheet per place, reasons only for other
-- people's rows, buildings on rows, and taking over a project's old sheet.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- ...0010 played as Workshop In-Charge and Document Controller, Accountant
-- ...0013. Fictional fixtures only.

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

create function pg_temp.place(p_project text)
returns jsonb
language sql
as $$
  select place
  from jsonb_array_elements(public.v1_wf_list_places() -> 'projects') place
  where place ->> 'id' = p_project;
$$;

create function pg_temp.row_p(
  p_worker text, p_start integer, p_finish integer, p_scope text default null
)
returns jsonb
language sql
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'worker_id', p_worker, 'status', 'P',
    'start_minute', p_start, 'finish_minute', p_finish,
    'work_scope_id', p_scope
  ));
$$;

create function pg_temp.version(p_team uuid, p_date date)
returns bigint
language sql
as $$
  select (public.v1_wf_get_day(p_team, p_date) ->> 'record_version')::bigint;
$$;

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('6e010000-0000-4000-8000-000000000001', 'PL-001', 'Place one',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin'),
  ('6e010000-0000-4000-8000-000000000002', 'PL-002', 'Place two',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values
  ('6e050000-0000-4000-8000-000000000001',
   '6e010000-0000-4000-8000-000000000001', 'common', 'common',
   'Common / All Buildings', true),
  ('6e050000-0000-4000-8000-000000000002',
   '6e010000-0000-4000-8000-000000000001', 'building', 'tower-a',
   'Tower A', false),
  ('6e050000-0000-4000-8000-000000000003',
   '6e010000-0000-4000-8000-000000000002', 'building', 'block-1',
   'Block 1', false);

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('6e010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Places test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('6e010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'Places test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('6e020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'PL-' || n, 'Place Labourer ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 5) n;

-- The two most recent working days before today.
select set_config('pl.day', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc limit 1
), true);
select set_config('pl.day2', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc offset 1 limit 1
), true);

-- Who opens a place ------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  (pg_temp.place('6e010000-0000-4000-8000-000000000001') ->> 'can_take')::boolean,
  true,
  'A Site Engineer is offered a project they are on'
);
select is(
  pg_temp.place('6e010000-0000-4000-8000-000000000002'),
  null,
  'A Site Engineer is not offered a project they are not on'
);
select is(
  jsonb_array_length(
    pg_temp.place('6e010000-0000-4000-8000-000000000001') -> 'buildings'
  ),
  2,
  'A project comes with its buildings'
);
select is(
  pg_temp.place('6e010000-0000-4000-8000-000000000001') -> 'buildings' -> 0 ->> 'kind',
  'common',
  'Common comes first'
);
select throws_ok(
  $$select public.v1_wf_open_place('6e010000-0000-4000-8000-000000000002', null)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot open a project they are not on'
);
select throws_ok(
  $$select public.v1_wf_open_place(null, null)$$,
  '22023', 'V1_WORKFORCE_CREW_INVALID',
  'A place is a project or a location'
);
select throws_ok(
  $$select public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', 'Store')$$,
  '22023', 'V1_WORKFORCE_CREW_INVALID',
  'A place is not both a project and a location'
);
select set_config('pl.place', (
  public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', null) ->> 'id'
), true);
select isnt(current_setting('pl.place', true), null, 'A Site Engineer opens a project they are on');

reset role;
select results_eq(
  $$select place_key, shift_start_minute, shift_finish_minute,
      break_start_minute, needs_confirmation, crew_kind
    from public.v1_workforce_crew_profiles
    where team_id = current_setting('pl.place')::uuid$$,
  $$values ('project:6e010000-0000-4000-8000-000000000001'::text, 390, 870,
      null::integer, true, 'project'::text)$$,
  'A new project place starts at 06:30 for 8 hours, needs confirmation'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', null) ->> 'id',
  current_setting('pl.place'),
  'Opening the place again gives the same sheet'
);
select is(
  public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', null) ->> 'place_kind',
  'project',
  'The sheet says it is a project place'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_crew_profiles
   where place_key = 'project:6e010000-0000-4000-8000-000000000001'),
  1,
  'One sheet per place'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select is(
  (public.v1_wf_list_places() ->> 'can_take')::boolean, false,
  'Procurement does not keep attendance'
);
select is(
  jsonb_array_length(public.v1_wf_list_places() -> 'projects'), 0,
  'Procurement is offered no places'
);
select throws_ok(
  $$select public.v1_wf_open_place('6e010000-0000-4000-8000-000000000002', null)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement cannot open a place'
);
select throws_ok(
  $$select public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', null)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement cannot read an open place'
);

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  public.v1_wf_open_place('6e010000-0000-4000-8000-000000000001', null) ->> 'id',
  current_setting('pl.place'),
  'The Accountant reads an open place'
);
select is(
  (pg_temp.place('6e010000-0000-4000-8000-000000000001') ->> 'can_take')::boolean,
  false,
  'The Accountant reads but does not keep'
);
select throws_ok(
  $$select public.v1_wf_open_place('6e010000-0000-4000-8000-000000000002', null)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'The Accountant cannot open a new place'
);

-- Internal locations are kept by everyone who keeps attendance.
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('pl.store', (
  public.v1_wf_open_place(null, '  Main   Store ') ->> 'id'
), true);
reset role;
select is(
  (select place_key from public.v1_workforce_crew_profiles
   where team_id = current_setting('pl.store')::uuid),
  'location:main store',
  'A location is named once, whatever the spacing or case'
);
select pg_temp.as_role('workshop_in_charge');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select is(
  public.v1_wf_open_place(null, 'main store') ->> 'id',
  current_setting('pl.store'),
  'Another keeper opens the same location'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  (public.v1_wf_open_place(null, 'Main Store') -> 'access' ->> 'take')::boolean,
  true,
  'A Project Engineer keeps an internal location someone else opened'
);
reset role;
select pg_temp.as_role('document_controller');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'document_controller');
select is(
  (public.v1_wf_open_place(null, 'Main Store') -> 'access' ->> 'take')::boolean,
  false,
  'A Document Controller reads a location but does not keep it'
);

-- One shared sheet; reasons only for someone else's rows -------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, 0, null,
      '6e030000-0000-4000-8000-000000000001')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000001', 390, 870,
        '6e050000-0000-4000-8000-000000000002'),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870)
    )
  ),
  'A Site Engineer saves the day at the place'
);
select is(
  (select day_row ->> 'work_project_id'
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('pl.place')::uuid, current_setting('pl.day')::date
   ) -> 'rows') day_row
   where day_row ->> 'worker_id' = '6e020000-0000-4000-8000-000000000002'),
  '6e010000-0000-4000-8000-000000000001',
  'Every row on a project place is on that project'
);
select is(
  (select day_row ->> 'work_scope_name'
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('pl.place')::uuid, current_setting('pl.day')::date
   ) -> 'rows') day_row
   where day_row ->> 'worker_id' = '6e020000-0000-4000-8000-000000000001'),
  'Tower A',
  'A row records its building'
);
select is(
  (select (day_row ->> 'updated_by_me')::boolean
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('pl.place')::uuid, current_setting('pl.day')::date
   ) -> 'rows') day_row
   where day_row ->> 'worker_id' = '6e020000-0000-4000-8000-000000000001'),
  true,
  'A row says who saved it'
);
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, %s, null,
      '6e030000-0000-4000-8000-000000000002')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000001', 390, 870,
        '6e050000-0000-4000-8000-000000000003'),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870)
    ),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day')::date)
  ),
  '22023', 'V1_WORKFORCE_DAY_INVALID',
  'A building of another project is refused'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, %s, null,
      '6e030000-0000-4000-8000-000000000003')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000001', 390, 870,
        '6e050000-0000-4000-8000-000000000002'),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000003', 390, 870)
    ),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day')::date)
  ),
  'Another keeper adds a worker to the same day without a reason'
);
select is(
  (select (day_row ->> 'updated_by_me')::boolean
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('pl.place')::uuid, current_setting('pl.day')::date
   ) -> 'rows') day_row
   where day_row ->> 'worker_id' = '6e020000-0000-4000-8000-000000000001'),
  false,
  'A row saved again unchanged keeps who saved it'
);
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, %s, null,
      '6e030000-0000-4000-8000-000000000004')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000001', 390, 930,
        '6e050000-0000-4000-8000-000000000002'),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000003', 390, 870)
    ),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day')::date)
  ),
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'Changing a row someone else saved needs a reason'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, %s,
      'Stayed for the pump test', '6e030000-0000-4000-8000-000000000005')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000001', 390, 930,
        '6e050000-0000-4000-8000-000000000002'),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870),
      pg_temp.row_p('6e020000-0000-4000-8000-000000000003', 390, 870)
    ),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day')::date)
  ),
  'With a reason, the change is saved'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_day_changes change
   join public.v1_workforce_day_sheets sheet on sheet.id = change.sheet_id
   where sheet.team_id = current_setting('pl.place')::uuid),
  1,
  'Only the changed row of someone else is logged'
);
select is(
  (select count(*)::integer from public.v1_notifications
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000002'
     and event_code = 'workforce_attendance_day_changed'),
  1,
  'The person whose row changed is told once'
);
select is(
  (select changed_after_entry from public.v1_workforce_day_rows
   where team_id = current_setting('pl.place')::uuid
     and worker_id = '6e020000-0000-4000-8000-000000000002'),
  false,
  'An unchanged row is not marked changed'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, %s, null,
      '6e030000-0000-4000-8000-000000000006')$$,
    current_setting('pl.place'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000002', 390, 870)
    ),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day')::date)
  ),
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'Removing rows someone else saved needs a reason'
);

-- A day may be emptied.
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, 0, null,
      '6e030000-0000-4000-8000-000000000007')$$,
    current_setting('pl.place'), current_setting('pl.day2'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000004', 390, 870)
    )
  ),
  'A day with one worker'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, '[]'::jsonb, %s, null,
      '6e030000-0000-4000-8000-000000000008')$$,
    current_setting('pl.place'), current_setting('pl.day2'),
    pg_temp.version(current_setting('pl.place')::uuid, current_setting('pl.day2')::date)
  ),
  'Removing every row of one''s own saves an empty day'
);
select is(
  jsonb_array_length(public.v1_wf_get_day(
    current_setting('pl.place')::uuid, current_setting('pl.day2')::date
  ) -> 'rows'),
  0,
  'The emptied day has no rows'
);

-- Months: a place's days without a sheet are not missing ------------------

reset role;
select is(
  public.v1_wf_month_json(
    current_setting('pl.place')::uuid, current_setting('pl.day')::date
  ) -> 'missing_days',
  '[]'::jsonb,
  'A place has no missing days'
);

-- Taking over a project's old sheet --------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('pl.old', (
  public.v1_wf_save_crew(
    '{"name":"PL old sheet","kind":"project","project_id":"6e010000-0000-4000-8000-000000000002","shift_start_minute":390,"shift_finish_minute":1020,"break_start_minute":750,"break_finish_minute":780}'::jsonb,
    0, '6e030000-0000-4000-8000-000000000009'
  ) ->> 'id'
), true);
select lives_ok(
  format(
    $$select public.v1_wf_set_crew_members(%L, array['6e020000-0000-4000-8000-000000000005']::uuid[], null,
      '6e030000-0000-4000-8000-000000000010')$$,
    current_setting('pl.old')
  ),
  'The old sheet has a member'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, 0, null,
      '6e030000-0000-4000-8000-000000000011')$$,
    current_setting('pl.old'), current_setting('pl.day'),
    jsonb_build_array(
      pg_temp.row_p('6e020000-0000-4000-8000-000000000005', 390, 1020)
    )
  ),
  'The old sheet has a day'
);
reset role;
select set_config('pl.old_worked', (
  select worked_minutes::text from public.v1_workforce_day_rows
  where team_id = current_setting('pl.old')::uuid
), true);
set local role authenticated;
select is(
  public.v1_wf_open_place('6e010000-0000-4000-8000-000000000002', null) ->> 'id',
  current_setting('pl.old'),
  'Opening the project takes over its old sheet'
);
reset role;
select results_eq(
  $$select place_key, shift_start_minute, shift_finish_minute,
      break_start_minute, break_finish_minute
    from public.v1_workforce_crew_profiles
    where team_id = current_setting('pl.old')::uuid$$,
  $$values ('project:6e010000-0000-4000-8000-000000000002'::text, 390, 900,
      750, 780)$$,
  'Its new rows start at 06:30 for 8 hours plus its break'
);
select is(
  (select worked_minutes::text from public.v1_workforce_day_rows
   where team_id = current_setting('pl.old')::uuid),
  current_setting('pl.old_worked'),
  'Its saved rows are not touched'
);
select is(
  (select count(*)::integer from public.v1_audit_events
   where event_type = 'workforce_place_adopted'
     and entity_id = current_setting('pl.old')::uuid),
  1,
  'Taking over is audited'
);
set local role authenticated;
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_wf_get_day(
     current_setting('pl.old')::uuid, current_setting('pl.day2')::date
   ) -> 'rows')),
  0,
  'A place offers no crew members on a new day'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, '[]'::jsonb, 0, null,
      '6e030000-0000-4000-8000-000000000012')$$,
    current_setting('pl.old'), current_setting('pl.day2')
  ),
  'Its old members need not be marked'
);

select * from finish();
rollback;

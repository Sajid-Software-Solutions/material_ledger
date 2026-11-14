begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Today on the Workforce overview (PRODUCT_DECISIONS section 58): each place
-- says whether today is saved, by whom and its counts; the summary counts
-- labourers once across the places the reader may see, and never a place
-- the reader may not see.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- ...0010 played as Workshop In-Charge, Accountant ...0013. Fictional
-- fixtures only.

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

create function pg_temp.today_of(p_team text)
returns jsonb
language sql
as $$
  select crew -> 'today'
  from jsonb_array_elements(public.v1_wf_get_overview(null) -> 'crews') crew
  where crew ->> 'id' = p_team;
$$;

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '6f110000-0000-4000-8000-000000000001', 'OT-001', 'Overview site',
  'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
  'admin'
);

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('6f110000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Overview test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('6f110000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'Overview test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('6f120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'OT-' || n, 'Overview Labourer ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 4) n;

select set_config('ot.today', public.v1_wf_today()::text, true);

-- Today at the site (Site Engineer) and at the workshop (Workshop In-Charge):
-- labourer 1 is at both (morning site, afternoon workshop); labourer 2
-- present at the site; labourer 3 absent at the site; labourer 4 on sick
-- leave at the workshop.

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('ot.site', (
  public.v1_wf_open_place('6f110000-0000-4000-8000-000000000001', null) ->> 'id'
), true);
select is(
  pg_temp.today_of(current_setting('ot.site')) - 'date',
  '{"entered": false, "entered_by": null, "last_saved_by": null, "last_saved_at": null, "present": 0, "absent": 0, "leave": 0, "rest": 0}'::jsonb,
  'A place with nothing saved today says so'
);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, 0, null,
      '6f130000-0000-4000-8000-000000000001')$$,
    current_setting('ot.site'), current_setting('ot.today'),
    jsonb_build_array(
      pg_temp.row_p('6f120000-0000-4000-8000-000000000001', 390, 720),
      pg_temp.row_p('6f120000-0000-4000-8000-000000000002', 390, 870),
      pg_temp.row_s('6f120000-0000-4000-8000-000000000003', 'A'))),
  'The Site Engineer saves today at the site'
);

reset role;
update auth.users
set raw_app_meta_data = raw_app_meta_data
  || jsonb_build_object('role', 'workshop_in_charge')
where id = '10000000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000010', 'workshop_in_charge');
select set_config('ot.ws', (
  public.v1_wf_open_place(null, 'Overview workshop') ->> 'id'
), true);
select lives_ok(
  format($$select public.v1_wf_save_day(%L::uuid, %L::date, %L::jsonb, 0, null,
      '6f130000-0000-4000-8000-000000000002')$$,
    current_setting('ot.ws'), current_setting('ot.today'),
    jsonb_build_array(
      pg_temp.row_p('6f120000-0000-4000-8000-000000000001', 780, 1020),
      pg_temp.row_s('6f120000-0000-4000-8000-000000000004', 'SL'))),
  'The Workshop In-Charge saves today at the workshop'
);

-- Per place ---------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
reset role;
select set_config('ot.se_name',
  public.v1_wf_display_name('10000000-0000-4000-8000-000000000002'), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  pg_temp.today_of(current_setting('ot.site')) - 'date' - 'last_saved_at',
  jsonb_build_object(
    'entered', true,
    'entered_by', current_setting('ot.se_name'),
    'last_saved_by', current_setting('ot.se_name'),
    'present', 2, 'absent', 1, 'leave', 0, 'rest', 0
  ),
  'The Project Engineer sees who saved the site today and its counts'
);
select isnt(
  pg_temp.today_of(current_setting('ot.site')) ->> 'last_saved_at', null,
  'and when it was last saved'
);
select is(
  pg_temp.today_of(current_setting('ot.ws')), null,
  'The Project Engineer does not see the workshop'
);

-- The summary counts only what the reader may see -------------------------------

select is(
  (public.v1_wf_get_overview(null) -> 'today_summary') - 'date',
  '{"places": 1, "places_entered": 1, "present": 2, "absent": 1, "leave": 0}'::jsonb,
  'The Project Engineer''s summary covers the site only'
);

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  (public.v1_wf_get_overview(null) -> 'today_summary') - 'date' - 'places',
  '{"places_entered": 2, "present": 2, "absent": 1, "leave": 1}'::jsonb,
  'The Accountant''s summary counts a labourer at two places once'
);
select is(
  (pg_temp.today_of(current_setting('ot.ws')) ->> 'leave')::integer, 1,
  'and sees the workshop''s leave'
);

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  (public.v1_wf_get_overview(null) -> 'today_summary' ->> 'present')::integer,
  2,
  'Admin sees the same labourers working today'
);

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select is(
  (public.v1_wf_get_overview(null) -> 'today_summary') - 'date',
  '{"places": 0, "places_entered": 0, "present": 0, "absent": 0, "leave": 0}'::jsonb,
  'Procurement sees no place and no count'
);
select is(
  jsonb_array_length(public.v1_wf_get_overview(null) -> 'crews'), 0,
  'and no crew'
);

-- Every key the overview had is still there ----------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select ok(
  public.v1_wf_get_overview(null) ?& array[
    'schema_version', 'today', 'month', 'crews', 'feed', 'today_summary'
  ]
  and (public.v1_wf_get_overview(null) -> 'crews' -> 0) ?& array[
    'id', 'name', 'access', 'month', 'today'
  ],
  'The overview keeps its keys and adds today'
);

reset role;
select ok(
  not has_function_privilege('authenticated',
    'public.v1_wf_today_json(uuid,date)', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_wf_get_overview(date)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_get_overview(date)', 'execute'),
  'The helper stays private; the overview stays signed-in only'
);

select * from finish();
rollback;

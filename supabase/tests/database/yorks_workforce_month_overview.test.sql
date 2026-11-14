begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Everyone's month, one labourer's month and the workforce year
-- (PRODUCT_DECISIONS section 52): readers see exactly the places they may
-- view, a labourer's day counts once across places, and the year adds up.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- Accountant ...0013, PR ...0014. Fictional fixtures only.

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

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('6f010000-0000-4000-8000-000000000001', 'MO-001', 'Month one',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin'),
  ('6f010000-0000-4000-8000-000000000002', 'MO-002', 'Month two',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');

-- The Project Engineer is on project one only.
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('6f010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Month overview test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('6f020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'MO-' || n, 'Month Labourer ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 3) n;

select set_config('mo.day', (
  select series.day_ts::date::text
  from generate_series(
    public.v1_wf_today() - 14, public.v1_wf_today() - 1, interval '1 day'
  ) series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
  order by series.day_ts desc limit 1
), true);

-- Admin records: labourer 1 at both projects that day (morning at one,
-- afternoon at two), labourer 2 at project two only.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('mo.one', (
  public.v1_wf_open_place('6f010000-0000-4000-8000-000000000001', null) ->> 'id'
), true);
select set_config('mo.two', (
  public.v1_wf_open_place('6f010000-0000-4000-8000-000000000002', null) ->> 'id'
), true);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, 0, null,
      '6f030000-0000-4000-8000-000000000001')$$,
    current_setting('mo.one'), current_setting('mo.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 390, 690)
    )
  ),
  'Morning at project one'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L, %L, %L::jsonb, 0, null,
      '6f030000-0000-4000-8000-000000000002')$$,
    current_setting('mo.two'), current_setting('mo.day'),
    jsonb_build_array(
      pg_temp.row_p('6f020000-0000-4000-8000-000000000001', 720, 1020),
      pg_temp.row_p('6f020000-0000-4000-8000-000000000002', 390, 870)
    )
  ),
  'Afternoon at project two, and another labourer'
);

-- Everyone's month ---------------------------------------------------------

select is(
  jsonb_array_length(
    public.v1_wf_people_month(current_setting('mo.day')::date) -> 'entries'
  ),
  3,
  'Admin sees every row of the month'
);
select is(
  jsonb_array_length(
    public.v1_wf_people_month(current_setting('mo.day')::date) -> 'workers'
  ),
  2,
  'Each labourer once'
);
select is(
  (public.v1_wf_people_month(current_setting('mo.day')::date)
    -> 'days' -> 0 ->> 'date'),
  date_trunc('month', current_setting('mo.day')::date)::date::text,
  'The month starts on its first day'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  jsonb_array_length(
    public.v1_wf_people_month(current_setting('mo.day')::date) -> 'entries'
  ),
  1,
  'A Project Engineer sees only the rows at their project'
);
select is(
  (public.v1_wf_people_month(current_setting('mo.day')::date)
    -> 'places' -> 0 ->> 'id'),
  current_setting('mo.one'),
  'and only their place'
);

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  jsonb_array_length(
    public.v1_wf_people_month(current_setting('mo.day')::date) -> 'entries'
  ),
  3,
  'The Accountant sees every place'
);

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  jsonb_array_length(
    public.v1_wf_people_month(current_setting('mo.day')::date) -> 'entries'
  ),
  0,
  'A Site Engineer on no project sees nothing'
);

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format(
    $$select public.v1_wf_people_month(%L::date)$$, current_setting('mo.day')
  ),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement has no Workforce'
);
select throws_ok(
  format(
    $$select public.v1_wf_worker_month('6f020000-0000-4000-8000-000000000001', %L::date)$$,
    current_setting('mo.day')
  ),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement reads no timesheet'
);
select throws_ok(
  $$select public.v1_wf_workforce_year(2026)$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement reads no year'
);

-- One labourer's month ----------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  jsonb_array_length(public.v1_wf_worker_month(
    '6f020000-0000-4000-8000-000000000001', current_setting('mo.day')::date
  ) -> 'rows'),
  2,
  'HR/PRO sees the labourer at both places'
);
select is(
  (public.v1_wf_worker_month(
    '6f020000-0000-4000-8000-000000000001', current_setting('mo.day')::date
  ) -> 'rows' -> 1 ->> 'project_ref'),
  'MO-002',
  'In time order, each with its project'
);
select is(
  (select sum((entry ->> 'regular_minutes')::integer)
   from jsonb_array_elements(public.v1_wf_worker_month(
     '6f020000-0000-4000-8000-000000000001', current_setting('mo.day')::date
   ) -> 'rows') entry),
  480::bigint,
  'Eight normal hours over the whole day'
);
select is(
  (select sum((entry ->> 'normal_overtime_minutes')::integer)
   from jsonb_array_elements(public.v1_wf_worker_month(
     '6f020000-0000-4000-8000-000000000001', current_setting('mo.day')::date
   ) -> 'rows') entry),
  120::bigint,
  'and the rest overtime'
);
select throws_ok(
  format(
    $$select public.v1_wf_worker_month('6f020000-0000-4000-8000-0000000000ff', %L::date)$$,
    current_setting('mo.day')
  ),
  'P0002', 'V1_WORKFORCE_WORKER_NOT_FOUND',
  'An unknown labourer is refused'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  jsonb_array_length(public.v1_wf_worker_month(
    '6f020000-0000-4000-8000-000000000001', current_setting('mo.day')::date
  ) -> 'rows'),
  1,
  'A Project Engineer sees the labourer only at their project'
);

-- The year ------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('mo.year', extract(year from current_setting('mo.day')::date)::text, true);
select set_config('mo.month_index', (extract(month from current_setting('mo.day')::date) - 1)::text, true);
select is(
  jsonb_array_length(
    public.v1_wf_workforce_year(current_setting('mo.year')::integer) -> 'months'
  ),
  12,
  'Twelve months'
);
select results_eq(
  format(
    $$select (m ->> 'workers')::integer, (m ->> 'present_days')::integer,
        (m ->> 'regular_minutes')::integer,
        (m ->> 'normal_overtime_minutes')::integer
      from (select public.v1_wf_workforce_year(%s) -> 'months' -> %s as m) month$$,
    current_setting('mo.year'), current_setting('mo.month_index')
  ),
  $$values (2, 2, 960, 120)$$,
  'A labourer at two places is one present day; hours add up'
);
select is(
  jsonb_array_length(
    public.v1_wf_workforce_year(current_setting('mo.year')::integer) -> 'places'
  ),
  2,
  'Both places'
);
select isnt(
  public.v1_wf_workforce_year(current_setting('mo.year')::integer)
    -> 'labour_headcount',
  'null'::jsonb,
  'Admin sees the labour headcount'
);
select throws_ok(
  $$select public.v1_wf_workforce_year(1900)$$,
  '22023', 'V1_WORKFORCE_DATE_REQUIRED',
  'A year out of range is refused'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_workforce_year(current_setting('mo.year')::integer)
    -> 'labour_headcount',
  'null'::jsonb,
  'A Project Engineer sees no company headcount'
);
select is(
  jsonb_array_length(
    public.v1_wf_workforce_year(current_setting('mo.year')::integer) -> 'workers'
  ),
  1,
  'A Project Engineer sees the year of their project only'
);

select * from finish();
rollback;

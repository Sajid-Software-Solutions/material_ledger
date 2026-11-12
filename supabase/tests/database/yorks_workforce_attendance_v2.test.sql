begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- SME ...0009, Accountant ...0013, PR ...0014.

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

-- Fixtures ------------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('5a010000-0000-4000-8000-000000000001', 'WF-V2-001',
   'Sweihan attendance test', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('5a010000-0000-4000-8000-000000000002', 'WF-V2-002',
   'Other attendance test', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('5a010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Attendance test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('5a010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '400 days', 'Attendance test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('5a020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'WFV2-' || n, 'Test Worker ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 4) n;

select set_config('wf.tomorrow', (public.v1_wf_today() + 1)::text, true);
select set_config(
  'wf.next_month',
  (date_trunc('month', public.v1_wf_today()) + interval '1 month')::date::text,
  true
);

-- Calendar and hours ----------------------------------------------------------

select is(public.v1_wf_day_type('2026-11-01'), 'holiday', 'Sunday is a rest day');
select is(public.v1_wf_day_type('2026-08-03'), 'work', 'Monday is a working day');
select is(
  public.v1_wf_compute_minutes('P', 390, 750, 780, 900, 'holiday'),
  array[480, 0, 0, 480],
  'Sunday 6:30-3:00 with a 30-minute break is 8 holiday overtime hours'
);
select is(
  public.v1_wf_compute_minutes('P', 390, 750, 780, 1140, 'work'),
  array[720, 480, 240, 0],
  'A working day to 7 PM is 8 normal hours and 4 overtime hours'
);
select is(
  public.v1_wf_compute_minutes('P', 420, null, null, 780, 'work'),
  array[360, 360, 0, 0],
  'A short day with no break has no overtime'
);
select is(
  public.v1_wf_compute_minutes('SL', null, null, null, null, 'work'),
  array[0, 0, 0, 0],
  'Leave counts no hours'
);

-- Crew setup ------------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"SE crew","kind":"project","project_id":"5a010000-0000-4000-8000-000000000001","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '5a030000-0000-4000-8000-000000000001')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot create a crew'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select lives_ok(
  $$select public.v1_wf_save_crew(
      '{"crew_id":null,"name":"Sweihan site crew","kind":"project","project_id":"5a010000-0000-4000-8000-000000000001","needs_confirmation":true,"shift_start_minute":390,"shift_finish_minute":1020,"break_start_minute":750,"break_finish_minute":780}'::jsonb,
      0, '5a030000-0000-4000-8000-000000000002')$$,
  'The project''s Project Engineer creates a crew'
);
select throws_ok(
  $$select public.v1_wf_save_crew(
      '{"name":"Other crew","kind":"project","project_id":"5a010000-0000-4000-8000-000000000002","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
      0, '5a030000-0000-4000-8000-000000000003')$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Engineer cannot create a crew on a project they are not on'
);

reset role;
select set_config(
  'wf.crew',
  (select team_id::text from public.v1_workforce_crew_profiles profile
   join public.v1_workforce_teams team on team.id = profile.team_id
   where team.team_name = 'Sweihan site crew'),
  true
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  format(
    $$select public.v1_wf_set_crew_members(%L::uuid, array[
        '5a020000-0000-4000-8000-000000000001',
        '5a020000-0000-4000-8000-000000000002',
        '5a020000-0000-4000-8000-000000000003'
      ]::uuid[], null, '5a030000-0000-4000-8000-000000000010')$$,
    current_setting('wf.crew')
  ),
  'A Site Engineer on the project picks the crew workers'
);
select is(
  (public.v1_wf_get_crew(current_setting('wf.crew')::uuid)
    ->> 'member_count')::integer,
  3,
  'The crew has three members'
);

-- Access matrix -------------------------------------------------------------------

select ok(
  ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access') ->> 'take')::boolean
  and not ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access')
    ->> 'confirm')::boolean,
  'Site Engineer member: takes attendance, cannot confirm'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select ok(
  ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access') ->> 'take')::boolean
  and ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access')
    ->> 'confirm')::boolean,
  'Project Engineer member: takes attendance and confirms'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select ok(
  ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access') ->> 'confirm')::boolean,
  'An organization-wide engineer confirms any crew'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format($$select public.v1_wf_get_crew(%L::uuid)$$, current_setting('wf.crew')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement has no attendance access'
);
select throws_ok(
  format($$select public.v1_wf_get_day(%L::uuid, date '2026-08-03')$$,
    current_setting('wf.crew')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement cannot read a crew day'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select ok(
  ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access') ->> 'view')::boolean
  and not ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access')
    ->> 'take')::boolean,
  'Accountant reads every crew and cannot take attendance'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select ok(
  ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access') ->> 'manage')::boolean
  and ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access')
    ->> 'officer')::boolean,
  'PR manages every crew'
);

-- Saving a day -------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, %L::date,
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"A"}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000020')$$,
    current_setting('wf.crew'), current_setting('wf.tomorrow')
  ),
  '22023', 'V1_WORKFORCE_FUTURE_DATE',
  'A future day cannot be entered'
);
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"A"}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000021')$$,
    current_setting('wf.crew')
  ),
  '22023', 'V1_WORKFORCE_DAY_UNMARKED',
  'Every crew member must be marked before a day is saved'
);
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"A"}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000022')$$,
    current_setting('wf.crew')
  ),
  '22023', 'V1_WORKFORCE_TIME_MISSING',
  'Present without an Out time is refused'
);
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"OFF"},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"A"}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000023')$$,
    current_setting('wf.crew')
  ),
  '22023', 'V1_WORKFORCE_REST_DAY_NOT_ALLOWED',
  'Rest day is refused on a working day'
);

select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1140,"overtime_note":"Concrete pour"},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"SL"},
          {"worker_id":"5a020000-0000-4000-8000-000000000004","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1020}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000024')$$,
    current_setting('wf.crew')
  ),
  'A Site Engineer saves the whole day, with one worker added for the day'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1140,"overtime_note":"Concrete pour"},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"SL"},
          {"worker_id":"5a020000-0000-4000-8000-000000000004","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1020}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000024')$$,
    current_setting('wf.crew')
  ),
  'Retrying with the same key replays without a conflict'
);

reset role;
select is(
  (select count(*) from public.v1_workforce_day_sheets
   where team_id = current_setting('wf.crew')::uuid),
  1::bigint,
  'The retry did not create a second day'
);
select is(
  (select array[regular_minutes, normal_overtime_minutes, holiday_overtime_minutes]
   from public.v1_workforce_day_rows
   where worker_id = '5a020000-0000-4000-8000-000000000001'
     and work_date = '2026-08-03'),
  array[480, 240, 0],
  'The server computes 8 normal hours and 4 overtime hours'
);
select is(
  (select record_version from public.v1_workforce_day_sheets
   where team_id = current_setting('wf.crew')::uuid),
  1::bigint,
  'The day is at version 1'
);
set local role authenticated;

select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"A"}]'::jsonb,
        0, null, '5a030000-0000-4000-8000-000000000025')$$,
    current_setting('wf.crew')
  ),
  '40001', null,
  'A stale version is a conflict, never a silent overwrite'
);

-- The Project Engineer changes a day the Site Engineer entered.
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1140},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1020},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"SL"}]'::jsonb,
        1, null, '5a030000-0000-4000-8000-000000000026')$$,
    current_setting('wf.crew')
  ),
  '22023', 'V1_WORKFORCE_CHANGE_REASON_REQUIRED',
  'Changing a day someone else entered needs a reason'
);
select lives_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, date '2026-08-03',
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1140},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1020},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"SL"}]'::jsonb,
        1, 'Gate log shows he came', '5a030000-0000-4000-8000-000000000027')$$,
    current_setting('wf.crew')
  ),
  'With a reason the change is saved'
);

reset role;
select is(
  (select count(*) from public.v1_workforce_day_changes change
   join public.v1_workforce_day_sheets sheet on sheet.id = change.sheet_id
   where sheet.team_id = current_setting('wf.crew')::uuid),
  2::bigint,
  'The changed worker and the removed day-only worker are both logged'
);
select is(
  (select count(*) from public.v1_notifications
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000002'
     and event_code = 'workforce_attendance_day_changed'),
  1::bigint,
  'The Site Engineer who entered the day is notified'
);
select throws_ok(
  $$delete from public.v1_workforce_day_changes$$,
  '42501', 'V1_WORKFORCE_HISTORY_APPEND_ONLY',
  'The change history is append-only'
);
set local role authenticated;

-- Questions -------------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_ask_day(%L::uuid, date '2026-08-03',
      'Why?', '5a030000-0000-4000-8000-000000000030')$$,
    current_setting('wf.crew')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Site Engineer cannot raise a confirmer question'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select lives_ok(
  format($$select public.v1_wf_ask_day(%L::uuid, date '2026-08-03',
      'Worker 1 until 7 PM - did the client ask for this?',
      '5a030000-0000-4000-8000-000000000031')$$,
    current_setting('wf.crew')),
  'The Project Engineer asks about a day'
);
reset role;
select is(
  public.v1_wf_day_state(current_setting('wf.crew')::uuid, '2026-08-03'),
  'question',
  'The day shows an open question'
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  format($$select public.v1_wf_answer_day(%L::uuid, date '2026-08-03',
      'Yes, the concrete pour ran late.',
      '5a030000-0000-4000-8000-000000000032')$$,
    current_setting('wf.crew')),
  'The Site Engineer answers'
);
reset role;
select is(
  public.v1_wf_day_state(current_setting('wf.crew')::uuid, '2026-08-03'),
  'entered',
  'The day is entered again once answered'
);
set local role authenticated;

-- Month confirmation ---------------------------------------------------------------

reset role;
select set_config(
  'wf.prev_month',
  (date_trunc('month', public.v1_wf_today()) - interval '1 month')::date::text,
  true
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  format($$select public.v1_wf_confirm_month(%L::uuid, %L::date,
      '5a030000-0000-4000-8000-000000000040')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')),
  '55000', 'V1_WORKFORCE_MONTH_INCOMPLETE',
  'A month with days not entered cannot be confirmed'
);
select throws_ok(
  format($$select public.v1_wf_confirm_month(%L::uuid, %L::date,
      '5a030000-0000-4000-8000-000000000041')$$,
    current_setting('wf.crew'), current_setting('wf.next_month')),
  '55000', 'V1_WORKFORCE_MONTH_NOT_ENDED',
  'A month cannot be confirmed before its last day'
);

-- Enter every working day of last month as the Site Engineer.
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
create function pg_temp.fill_month(p_team uuid, p_month date)
returns integer
language plpgsql
as $$
declare
  v_day date;
  v_count integer := 0;
begin
  for v_day in
    select series.day_ts::date
    from generate_series(
      p_month,
      (p_month + interval '1 month - 1 day')::date,
      interval '1 day'
    ) series(day_ts)
    where public.v1_wf_day_type(series.day_ts::date) = 'work'
  loop
    perform public.v1_wf_save_day(
      p_team, v_day,
      '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"P","start_minute":390,"break_start_minute":750,"break_finish_minute":780,"finish_minute":1020},
        {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
        {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"AL"}]'::jsonb,
      0, null, gen_random_uuid()
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
-- The helper reads the internal calendar, so it runs as the owner while the
-- Site Engineer's identity stays the actor of every save.
reset role;
select ok(
  pg_temp.fill_month(
    current_setting('wf.crew')::uuid, current_setting('wf.prev_month')::date
  ) > 15,
  'Every working day of last month is entered'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select lives_ok(
  format($$select public.v1_wf_confirm_month(%L::uuid, %L::date,
      '5a030000-0000-4000-8000-000000000042')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')),
  'The Project Engineer confirms the complete month'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format(
    $$select public.v1_wf_save_day(%L::uuid, %L::date + 1,
        '[{"worker_id":"5a020000-0000-4000-8000-000000000001","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000002","status":"A"},
          {"worker_id":"5a020000-0000-4000-8000-000000000003","status":"A"}]'::jsonb,
        1, 'Late change', '5a030000-0000-4000-8000-000000000043')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')
  ),
  '55000', 'V1_WORKFORCE_MONTH_LOCKED',
  'A confirmed month refuses every change'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  format($$select public.v1_wf_reopen_month(%L::uuid, %L::date,
      'Correction', '5a030000-0000-4000-8000-000000000044')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')),
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'A Project Engineer cannot reopen a confirmed month'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  format($$select public.v1_wf_reopen_month(%L::uuid, %L::date,
      '  ', '5a030000-0000-4000-8000-000000000045')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')),
  '22023', 'V1_WORKFORCE_REASON_REQUIRED',
  'Reopening needs a reason'
);
select lives_ok(
  format($$select public.v1_wf_reopen_month(%L::uuid, %L::date,
      'Payroll query on one worker', '5a030000-0000-4000-8000-000000000046')$$,
    current_setting('wf.crew'), current_setting('wf.prev_month')),
  'PR reopens the month with a reason'
);
reset role;
select ok(
  not public.v1_wf_month_locked(
    current_setting('wf.crew')::uuid, current_setting('wf.prev_month')::date
  ),
  'The reopened month is editable again'
);
set local role authenticated;

-- Reads ----------------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  jsonb_array_length(
    public.v1_wf_get_month_sheet(
      current_setting('wf.crew')::uuid, current_setting('wf.prev_month')::date
    ) -> 'workers'
  ),
  3,
  'Accountant reads the monthly sheet for every crew worker'
);
select ok(
  not (public.v1_wf_get_month_sheet(
    current_setting('wf.crew')::uuid, current_setting('wf.prev_month')::date
  ) ? 'basic_salary'),
  'The monthly sheet carries no pay field'
);
select ok(
  jsonb_array_length(public.v1_wf_get_overview(null) -> 'feed') > 0,
  'The overview feed lists recent entries'
);

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_list_workers()$$,
  '42501', 'V1_WORKFORCE_CREW_ACCESS_DENIED',
  'Procurement cannot read the worker list'
);

-- A per-person deny still removes a right the role would give.
reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, origin, reason,
  changed_by_auth_user_id
) values (
  '10000000-0000-4000-8000-000000000002', 'workforce.attendance.maintain',
  'deny', 'organization', 'permission_management', 'Attendance deny test',
  '10000000-0000-4000-8000-000000000004'
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select ok(
  not ((public.v1_wf_get_crew(current_setting('wf.crew')::uuid) -> 'access')
    ->> 'take')::boolean,
  'An explicit deny removes the Site Engineer''s attendance right'
);
reset role;
select ok(
  not exists (
    select 1 from public.v1_permission_role_defaults
    where role_name in ('project_engineer', 'site_engineer', 'accountant')
      and capability_key like 'workforce.%' and is_granted
  ),
  'Attendance V2 changes no engineering or Accountant role template'
);

reset role;
select ok(
  not has_table_privilege('authenticated', 'public.v1_workforce_day_rows', 'select')
  and not has_table_privilege('anon', 'public.v1_workforce_day_sheets', 'select')
  and not has_function_privilege('anon', 'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.v1_wf_crew_access(uuid)', 'execute'),
  'Attendance tables and helpers are reachable only through the commands'
);

select * from finish();
rollback;

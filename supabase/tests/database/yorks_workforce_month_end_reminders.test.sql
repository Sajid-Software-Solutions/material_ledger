begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: PE ...0001, SE ...0002, Admin ...0004, SME ...0009,
-- PM ...0010.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
$$;

select set_config(
  'mr.prev',
  (date_trunc('month', public.v1_wf_today()) - interval '1 month')::date::text,
  true
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('6b010000-0000-4000-8000-000000000001', 'MR-REM-001',
   'Reminder project with PE', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('6b010000-0000-4000-8000-000000000002', 'MR-REM-002',
   'Reminder project without PE', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin');
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values (
  '6b010000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'project_engineer',
  clock_timestamp() - interval '400 days', 'Reminder test',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

-- Two crews created last month; neither month is confirmed.
insert into public.v1_workforce_teams (
  id, team_code, team_name, default_project_id, valid_from,
  created_by_auth_user_id, updated_by_auth_user_id
) values
  ('6b020000-0000-4000-8000-000000000001', 'CREW-REM1', 'Reminder crew A',
   '6b010000-0000-4000-8000-000000000001', current_setting('mr.prev')::date,
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('6b020000-0000-4000-8000-000000000002', 'CREW-REM2', 'Reminder crew B',
   '6b010000-0000-4000-8000-000000000002', current_setting('mr.prev')::date,
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_crew_profiles (
  team_id, crew_kind, project_id, needs_confirmation, shift_start_minute,
  shift_finish_minute, created_by_auth_user_id, updated_by_auth_user_id,
  created_at
)
select team.id, 'project', team.default_project_id, true, 390, 1020,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004',
  current_setting('mr.prev')::timestamptz
from public.v1_workforce_teams team
where team.id in (
  '6b020000-0000-4000-8000-000000000001',
  '6b020000-0000-4000-8000-000000000002'
);

-- A workshop crew needs no confirmation and is never reminded.
insert into public.v1_workforce_teams (
  id, team_code, team_name, valid_from, created_by_auth_user_id,
  updated_by_auth_user_id
) values (
  '6b020000-0000-4000-8000-000000000003', 'CREW-REM3', 'Reminder workshop',
  current_setting('mr.prev')::date, '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_workforce_crew_profiles (
  team_id, crew_kind, needs_confirmation, shift_start_minute,
  shift_finish_minute, created_by_auth_user_id, updated_by_auth_user_id,
  created_at
) values (
  '6b020000-0000-4000-8000-000000000003', 'workshop', false, 420, 960,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004',
  current_setting('mr.prev')::timestamptz
);

-- The job ----------------------------------------------------------------

select ok(
  public.v1_wf_send_month_end_reminders() >= 3,
  'The daily job reminds the crews'' confirmers'
);
select is(
  (select count(*) from public.v1_notifications
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000001'
     and event_code = 'workforce_attendance_month_overdue'),
  1::bigint,
  'The Project Engineer receives one overdue (urgent) reminder for last month'
);
select ok(
  exists (
    select 1 from public.v1_notifications
    where recipient_auth_user_id = '10000000-0000-4000-8000-000000000009'
      and event_code = 'workforce_attendance_month_overdue'
  ) and exists (
    select 1 from public.v1_notifications
    where recipient_auth_user_id = '10000000-0000-4000-8000-000000000010'
      and event_code = 'workforce_attendance_month_overdue'
  ),
  'A crew whose project has no Project Engineer reminds SME and PM'
);
select is(
  (select count(*) from public.v1_notifications
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000002'
     and event_code = 'workforce_attendance_month_overdue'),
  0::bigint,
  'A Site Engineer is not reminded'
);
select is(
  public.v1_wf_send_month_end_reminders(),
  0,
  'Running the job again the same day sends nothing twice'
);

-- The notification opens Month confirmation on the due month.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
reset role;
select is(
  (select public.v1_notification_module_route(n)
   from public.v1_notifications n
   where n.recipient_auth_user_id = '10000000-0000-4000-8000-000000000001'
     and n.event_code = 'workforce_attendance_month_overdue'),
  '/yorks/workforce/confirm?month=' || current_setting('mr.prev'),
  'The reminder opens Month confirmation on the due month'
);

-- In the app ---------------------------------------------------------------

set local role authenticated;
select is(
  (select jsonb_array_length(public.v1_wf_get_confirmations_due() -> 'due')),
  1,
  'The Project Engineer sees their one crew waiting'
);
select ok(
  ((public.v1_wf_get_confirmations_due() -> 'due' -> 0) ->> 'overdue')::boolean,
  'Last month is shown as overdue'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  (select jsonb_array_length(public.v1_wf_get_confirmations_due() -> 'due')),
  0,
  'A Site Engineer has nothing to confirm'
);

-- Confirming removes it from the list and from tomorrow's reminders.
reset role;
insert into public.v1_workforce_month_confirmations (
  team_id, period_month, is_confirmed, confirmed_by_auth_user_id,
  confirmed_at
) values (
  '6b020000-0000-4000-8000-000000000001', current_setting('mr.prev')::date,
  true, '10000000-0000-4000-8000-000000000001', clock_timestamp()
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  (select jsonb_array_length(public.v1_wf_get_confirmations_due() -> 'due')),
  0,
  'A confirmed month is no longer waiting'
);
reset role;
select ok(
  not exists (
    select 1 from public.v1_wf_due_crew_months(public.v1_wf_today() + 1)
    where team_id = '6b020000-0000-4000-8000-000000000001'
      and period_month = current_setting('mr.prev')::date
  ),
  'A confirmed month is not reminded again'
);

-- The schedule --------------------------------------------------------------

select ok(
  exists (
    select 1 from cron.job
    where jobname = 'yorks-workforce-month-end-reminders'
      and schedule = '5 4 * * *'
      and active
  ),
  'The reminder runs every day at 08:05 Dubai time'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.v1_wf_send_month_end_reminders()', 'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_wf_get_confirmations_due()', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.v1_wf_get_confirmations_due()', 'execute'
  ),
  'Only the job sends reminders; signed-in people read their own list'
);

select * from finish();
rollback;

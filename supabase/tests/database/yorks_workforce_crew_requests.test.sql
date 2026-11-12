begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- SME ...0009, Accountant ...0013, PR ...0014. Fictional fixtures only.

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

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('7c010000-0000-4000-8000-000000000001', 'CRQ-T-001',
   'Crew request test project', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('7c010000-0000-4000-8000-000000000002', 'CRQ-T-002',
   'Crew request other project', 'active', 'project_engineer',
   '10000000-0000-4000-8000-000000000004', 'admin');
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('7c010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '30 days', 'Crew request test',
   '10000000-0000-4000-8000-000000000004', 'admin'),
  ('7c010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'site_engineer',
   clock_timestamp() - interval '30 days', 'Crew request test',
   '10000000-0000-4000-8000-000000000004', 'admin');
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('7c020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'CRQT-' || n, 'Request Worker ' || n,
  case when n <= 3 then 'Duct fitter' else 'Helper' end,
  'Example Manpower LLC', 'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 5) n;

select set_config('crq.from', (public.v1_wf_today() + 2)::text, true);
select set_config('crq.yesterday', (public.v1_wf_today() - 1)::text, true);
select set_config('crq.year', extract(year from public.v1_wf_today())::text, true);
select set_config(
  'crq.payload',
  jsonb_build_object(
    'crew_kind', 'project',
    'project_id', '7c010000-0000-4000-8000-000000000001',
    'work_label', 'Level 3 ductwork',
    'needed_from', current_setting('crq.from'),
    'notes', 'Ceiling closes next week',
    'lines', jsonb_build_array(
      jsonb_build_object('trade', 'Duct fitter', 'quantity', 3),
      jsonb_build_object('trade', 'Helper', 'quantity', 2,
        'note', 'Any helper')
    )
  )::text,
  true
);

-- Who may raise a request --------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_wf_submit_request(current_setting('crq.payload')::jsonb,
      null, '7c030000-0000-4000-8000-000000000001')$$,
  '42501', null, 'Procurement cannot raise a crew request'
);
select throws_ok(
  $$select public.v1_wf_list_requests()$$,
  '42501', null, 'Procurement cannot see crew requests'
);

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select throws_ok(
  $$select public.v1_wf_submit_request(current_setting('crq.payload')::jsonb,
      null, '7c030000-0000-4000-8000-000000000002')$$,
  '42501', null, 'Accountant cannot raise a crew request'
);

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_wf_submit_request(
      jsonb_set(current_setting('crq.payload')::jsonb, '{project_id}',
        '"7c010000-0000-4000-8000-000000000002"'),
      null, '7c030000-0000-4000-8000-000000000003')$$,
  '42501', null, 'A Site Engineer cannot request for a project they are not on'
);
select throws_ok(
  $$select public.v1_wf_submit_request(
      jsonb_set(current_setting('crq.payload')::jsonb, '{needed_from}',
        to_jsonb(current_setting('crq.yesterday'))),
      null, '7c030000-0000-4000-8000-000000000004')$$,
  '22023', null, 'A request cannot be needed in the past'
);
select throws_ok(
  $$select public.v1_wf_submit_request(
      jsonb_set(current_setting('crq.payload')::jsonb, '{lines}', '[]'),
      null, '7c030000-0000-4000-8000-000000000005')$$,
  '22023', null, 'A request needs at least one line'
);
select is(
  (public.v1_wf_submit_request(current_setting('crq.payload')::jsonb,
     null, '7c030000-0000-4000-8000-000000000010') ->> 'state'),
  'submitted',
  'A Site Engineer on the project raises a request; it waits for approval'
);
select is(
  (public.v1_wf_submit_request(current_setting('crq.payload')::jsonb,
     null, '7c030000-0000-4000-8000-000000000010') ->> 'number'),
  'CRQ-' || current_setting('crq.year') || '-0001',
  'A retry returns the same request and number'
);
reset role;
select set_config('crq.id', (
  select id::text from public.v1_workforce_crew_requests
  where requested_by_auth_user_id = '10000000-0000-4000-8000-000000000002'
), true);
select is(
  (select count(*)::int from public.v1_workforce_crew_requests), 1,
  'The retry created nothing twice'
);
select is(
  (select count(*)::int from public.v1_notifications
   where entity_id = current_setting('crq.id')::uuid
     and event_code = 'workforce_crew_request_submitted'
     and recipient_auth_user_id = '10000000-0000-4000-8000-000000000001'),
  1,
  'The project''s Project Engineer is notified'
);

-- Approval -------------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select ok(
  not ((public.v1_wf_get_request(current_setting('crq.id')::uuid)
    -> 'access' ->> 'decide')::boolean),
  'The requester cannot approve their own request'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  $$select public.v1_wf_decide_request(current_setting('crq.id')::uuid,
      'approve', null, 1, '7c030000-0000-4000-8000-000000000020')$$,
  '42501', null, 'PR does not approve crew requests'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select ok(
  (public.v1_wf_get_request(current_setting('crq.id')::uuid)
    -> 'access' ->> 'view')::boolean
  and not (public.v1_wf_get_request(current_setting('crq.id')::uuid)
    -> 'access' ->> 'fulfil')::boolean,
  'Accountant reads requests without acting on them'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_wf_decide_request(current_setting('crq.id')::uuid,
      'return', '', 1, '7c030000-0000-4000-8000-000000000021')$$,
  '22023', null, 'Returning a request needs a reason'
);
select is(
  public.v1_wf_decide_request(current_setting('crq.id')::uuid, 'return',
    'Split fitters and helpers by level', 1,
    '7c030000-0000-4000-8000-000000000022') ->> 'state',
  'returned', 'The Project Engineer returns it with a reason'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  public.v1_wf_submit_request(
    current_setting('crq.payload')::jsonb
      || jsonb_build_object('request_id', current_setting('crq.id')),
    2, '7c030000-0000-4000-8000-000000000023') ->> 'state',
  'submitted', 'The requester fixes and resubmits'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_wf_decide_request(current_setting('crq.id')::uuid,
      'approve', null, 2, '7c030000-0000-4000-8000-000000000024')$$,
  '40001', null, 'A stale version is refused'
);
select is(
  public.v1_wf_decide_request(current_setting('crq.id')::uuid, 'approve',
    null, 3, '7c030000-0000-4000-8000-000000000025') ->> 'owner',
  'pr', 'Approved requests wait for PR'
);
reset role;
select is(
  (select count(*)::int from public.v1_notifications
   where entity_id = current_setting('crq.id')::uuid
     and event_code = 'workforce_crew_request_approved'
     and recipient_auth_user_id = '10000000-0000-4000-8000-000000000014'),
  1,
  'PR is told the request is approved'
);

-- A Project Engineer's own request is approved on submit.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_submit_request(current_setting('crq.payload')::jsonb,
    null, '7c030000-0000-4000-8000-000000000030') ->> 'state',
  'approved', 'A Project Engineer''s request on their project is approved on submit'
);

-- Assigning workers ------------------------------------------------------------

reset role;
select set_config('crq.lines', (
  select jsonb_agg(line.id order by line.line_number)::text
  from public.v1_workforce_crew_request_lines line
  where line.request_id = current_setting('crq.id')::uuid and line.is_current
), true);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_wf_fulfil_request(current_setting('crq.id')::uuid,
      '{"lines":[]}'::jsonb, 4, '7c030000-0000-4000-8000-000000000040')$$,
  '42501', null, 'A Site Engineer does not assign workers'
);

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  format($$select public.v1_wf_fulfil_request(%L::uuid,
      jsonb_build_object(
        'new_crew', jsonb_build_object('name', 'Level 3 crew',
          'shift_start_minute', 390, 'shift_finish_minute', 1020),
        'lines', jsonb_build_array(jsonb_build_object(
          'line_id', %L, 'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000001',
            '7c020000-0000-4000-8000-000000000002')))),
      4, '7c030000-0000-4000-8000-000000000041')$$,
    current_setting('crq.id'),
    current_setting('crq.lines')::jsonb ->> 0),
  '22023', 'V1_WORKFORCE_REQUEST_REASON_REQUIRED',
  'A line left short needs a reason'
);
select is(
  public.v1_wf_fulfil_request(current_setting('crq.id')::uuid,
    jsonb_build_object(
      'new_crew', jsonb_build_object('name', 'Level 3 crew',
        'shift_start_minute', 390, 'shift_finish_minute', 1020,
        'break_start_minute', 750, 'break_finish_minute', 780),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 0,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000001',
            '7c020000-0000-4000-8000-000000000002'),
          'decision', 'partial',
          'reason', 'Third fitter free from Monday'),
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 1,
          'worker_ids', jsonb_build_array(),
          'decision', 'cannot_provide',
          'reason', 'No helpers free this week'))),
    4, '7c030000-0000-4000-8000-000000000042') ->> 'state',
  'partially_fulfilled',
  'PR assigns two fitters into a new crew; short lines keep their reasons'
);
reset role;
select set_config('crq.crew', (
  select target_team_id::text from public.v1_workforce_crew_requests
  where id = current_setting('crq.id')::uuid
), true);
select is(
  (select count(*)::int from public.v1_workforce_crew_members member
   where member.team_id = current_setting('crq.crew')::uuid
     and member.removed_at is null),
  2, 'The assigned workers are now crew members'
);
select ok(
  exists (
    select 1 from public.v1_workforce_crew_profiles profile
    where profile.team_id = current_setting('crq.crew')::uuid
      and profile.project_id = '7c010000-0000-4000-8000-000000000001'
  ),
  'The new crew belongs to the request''s project'
);
select ok(
  exists (
    select 1 from public.v1_notifications
    where entity_id = current_setting('crq.id')::uuid
      and event_code = 'workforce_crew_request_fulfilled'
      and recipient_auth_user_id = '10000000-0000-4000-8000-000000000002'
  ),
  'The requester is told workers were assigned'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  format($$select public.v1_wf_fulfil_request(%L::uuid,
      jsonb_build_object('crew_id', %L,
        'lines', jsonb_build_array(jsonb_build_object(
          'line_id', %L, 'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000001')))),
      5, '7c030000-0000-4000-8000-000000000043')$$,
    current_setting('crq.id'), current_setting('crq.crew'),
    current_setting('crq.lines')::jsonb ->> 0),
  '23505', 'V1_WORKFORCE_WORKER_ON_CREW',
  'A worker already on a crew cannot be assigned again'
);
select throws_ok(
  format($$select public.v1_wf_fulfil_request(%L::uuid,
      jsonb_build_object('crew_id', %L,
        'lines', jsonb_build_array(jsonb_build_object(
          'line_id', %L, 'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000003',
            '7c020000-0000-4000-8000-000000000004')))),
      5, '7c030000-0000-4000-8000-000000000044')$$,
    current_setting('crq.id'), current_setting('crq.crew'),
    current_setting('crq.lines')::jsonb ->> 0),
  '22023', 'V1_WORKFORCE_REQUEST_OVER_ASSIGNED',
  'A line cannot receive more workers than requested'
);
select is(
  public.v1_wf_fulfil_request(current_setting('crq.id')::uuid,
    jsonb_build_object('crew_id', current_setting('crq.crew'),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 0,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000003')),
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 1,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000004',
            '7c020000-0000-4000-8000-000000000005')))),
    5, '7c030000-0000-4000-8000-000000000045') ->> 'state',
  'fulfilled', 'Assigning the rest fulfils the request'
);
select is(
  public.v1_wf_fulfil_request(current_setting('crq.id')::uuid,
    jsonb_build_object('crew_id', current_setting('crq.crew'),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 0,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000003')),
        jsonb_build_object(
          'line_id', current_setting('crq.lines')::jsonb ->> 1,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000004',
            '7c020000-0000-4000-8000-000000000005')))),
    5, '7c030000-0000-4000-8000-000000000045') ->> 'assigned_count',
  '5', 'A retried assignment adds nobody twice'
);

-- Visibility ------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  jsonb_array_length(public.v1_wf_list_requests() -> 'requests'), 2,
  'A Site Engineer sees the requests on their project'
);
reset role;
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values (
  '7c010000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001', 'project_engineer',
  clock_timestamp() - interval '1 day', 'Crew request test',
  '10000000-0000-4000-8000-000000000004', 'admin'
);
update public.v1_project_members
set effective_to = clock_timestamp() - interval '1 second',
  revoked_by_auth_user_id = '10000000-0000-4000-8000-000000000004',
  revoked_by_role = 'admin', revoked_reason = 'Moved to another site'
where project_id = '7c010000-0000-4000-8000-000000000001'
  and member_auth_user_id = '10000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  jsonb_array_length(public.v1_wf_list_requests() -> 'requests'), 1,
  'After leaving the project a Site Engineer sees only their own request'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select is(
  jsonb_array_length(public.v1_wf_list_requests() -> 'requests'), 2,
  'Senior Mechanical Engineer sees every request'
);

-- Cancel and close --------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select set_config('crq.sme', (
  public.v1_wf_submit_request(
    jsonb_build_object('crew_kind', 'workshop',
      'needed_from', current_setting('crq.from'),
      'lines', jsonb_build_array(
        jsonb_build_object('trade', 'Fabricator', 'quantity', 1))),
    null, '7c030000-0000-4000-8000-000000000050') ->> 'id'
), true);
select is(
  public.v1_wf_get_request(current_setting('crq.sme')::uuid) ->> 'state',
  'approved', 'An org-wide engineer''s workshop request is approved on submit'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  $$select public.v1_wf_close_request(current_setting('crq.sme')::uuid,
      '', 1, '7c030000-0000-4000-8000-000000000051')$$,
  '22023', null, 'Closing needs a reason'
);
select is(
  public.v1_wf_close_request(current_setting('crq.sme')::uuid,
    'Covered by the existing workshop crew', 1,
    '7c030000-0000-4000-8000-000000000052') ->> 'state',
  'closed', 'PR closes what cannot be provided, with a reason'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select set_config('crq.pe', (
  public.v1_wf_submit_request(
    jsonb_set(current_setting('crq.payload')::jsonb, '{project_id}',
      '"7c010000-0000-4000-8000-000000000002"'),
    null, '7c030000-0000-4000-8000-000000000053') ->> 'id'
), true);
select is(
  public.v1_wf_cancel_request(current_setting('crq.pe')::uuid,
    'Plan changed', 1, '7c030000-0000-4000-8000-000000000054') ->> 'state',
  'cancelled', 'The requester cancels before anyone is assigned'
);

-- Daily overdue summary ----------------------------------------------------------

reset role;
select set_config('crq.late', (
  select id::text from public.v1_workforce_crew_requests
  where request_number like 'CRQ-%' and state = 'approved'
    and requested_by_auth_user_id = '10000000-0000-4000-8000-000000000001'
  limit 1
), true);
insert into public.v1_workforce_crew_requests (
  request_number, crew_kind, project_id, needed_from, state,
  requested_by_auth_user_id, requested_by_role, last_actor_auth_user_id,
  last_actor_role, submitted_at
)
select 'CRQ-T-LATE-' || n, 'project', '7c010000-0000-4000-8000-000000000001',
  public.v1_wf_today(), 'approved',
  '10000000-0000-4000-8000-000000000001', 'project_engineer',
  '10000000-0000-4000-8000-000000000001', 'project_engineer',
  clock_timestamp()
from generate_series(1, 3) n;
select is(
  public.v1_wf_send_crew_request_reminders(),
  (select count(*)::int from public.v1_wf_request_fulfillers()),
  'Each PR gets one overdue summary, however many requests wait'
);
select is(
  public.v1_wf_send_crew_request_reminders(), 0,
  'The summary is sent once a day'
);
select ok(
  exists (
    select 1 from cron.job
    where jobname = 'yorks-workforce-crew-request-reminders'
      and schedule = '10 4 * * *'
  ),
  'The summary runs every morning'
);

-- By name, approve and assign in one step, finish ----------------------------

reset role;
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
) values
  ('7c020000-0000-4000-8000-000000000006', 'CRQT-6', 'Named Fitter',
   'Duct fitter', 'Example Manpower LLC', 'agency_worker', date '2025-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('7c020000-0000-4000-8000-000000000007', 'CRQT-7', 'Spare Helper',
   'Helper', 'Example Manpower LLC', 'agency_worker', date '2025-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004');
-- The named fitter is on the workshop crew today.
insert into public.v1_workforce_teams (
  id, team_code, team_name, valid_from, created_by_auth_user_id,
  updated_by_auth_user_id
) values (
  '7c040000-0000-4000-8000-000000000001', 'CRQT-WS', 'Request workshop crew',
  public.v1_wf_today() - 30, '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_workforce_crew_profiles (
  team_id, crew_kind, needs_confirmation, shift_start_minute,
  shift_finish_minute, created_by_auth_user_id, updated_by_auth_user_id
) values (
  '7c040000-0000-4000-8000-000000000001', 'workshop', false, 420, 960,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_workforce_crew_members (
  team_id, worker_id, added_by_auth_user_id
) values (
  '7c040000-0000-4000-8000-000000000001',
  '7c020000-0000-4000-8000-000000000006',
  '10000000-0000-4000-8000-000000000004'
);
-- The Site Engineer is back on the project.
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values (
  '7c010000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002', 'site_engineer',
  clock_timestamp(), 'Crew request test',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_submit_request(jsonb_build_object(
      'crew_kind', 'project',
      'project_id', '7c010000-0000-4000-8000-000000000001',
      'needed_from', %L,
      'lines', jsonb_build_array(
        jsonb_build_object('worker_id', '7c020000-0000-4000-8000-000000000006'),
        jsonb_build_object('worker_id', '7c020000-0000-4000-8000-000000000006'))),
    null, '7c030000-0000-4000-8000-000000000060')$$,
    current_setting('crq.from')),
  '22023', null, 'The same person cannot be asked for twice'
);
select set_config('crq.named', (
  public.v1_wf_submit_request(jsonb_build_object(
      'crew_kind', 'project',
      'project_id', '7c010000-0000-4000-8000-000000000001',
      'needed_from', current_setting('crq.from'),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'worker_id', '7c020000-0000-4000-8000-000000000006',
          'quantity', 5),
        jsonb_build_object('trade', 'Helper', 'quantity', 1))),
    null, '7c030000-0000-4000-8000-000000000061') ->> 'id'
), true);
select ok(
  (select (line ->> 'quantity')::int = 1
      and line ->> 'trade' = 'Duct fitter'
      and line -> 'worker' ->> 'crew_name' = 'Request workshop crew'
   from jsonb_array_elements(
     public.v1_wf_get_request(current_setting('crq.named')::uuid) -> 'lines'
   ) line
   where (line ->> 'line_number')::int = 1),
  'A named worker is one person, takes their designation and shows their current crew'
);
select throws_ok(
  format($$select public.v1_wf_fulfil_request(%L::uuid,
      jsonb_build_object('approve', true, 'lines', jsonb_build_array()),
      1, '7c030000-0000-4000-8000-000000000062')$$,
    current_setting('crq.named')),
  '42501', null, 'The requester cannot approve their own request'
);
reset role;
select set_config('crq.named_lines', (
  select jsonb_agg(line.id order by line.line_number)::text
  from public.v1_workforce_crew_request_lines line
  where line.request_id = current_setting('crq.named')::uuid and line.is_current
), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_fulfil_request(current_setting('crq.named')::uuid,
    jsonb_build_object(
      'approve', true,
      'new_crew', jsonb_build_object('name', 'Named request crew',
        'shift_start_minute', 390, 'shift_finish_minute', 1020),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'line_id', current_setting('crq.named_lines')::jsonb ->> 0,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000006')),
        jsonb_build_object(
          'line_id', current_setting('crq.named_lines')::jsonb ->> 1,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000007')))),
    1, '7c030000-0000-4000-8000-000000000063') ->> 'state',
  'fulfilled',
  'The Project Engineer approves and assigns in one step'
);
reset role;
select set_config('crq.named_crew', (
  select target_team_id::text from public.v1_workforce_crew_requests
  where id = current_setting('crq.named')::uuid
), true);
select ok(
  exists (
    select 1 from public.v1_workforce_crew_members member
    where member.worker_id = '7c020000-0000-4000-8000-000000000006'
      and member.team_id = current_setting('crq.named_crew')::uuid
      and member.removed_at is null
  ) and exists (
    select 1 from public.v1_workforce_crew_members member
    where member.worker_id = '7c020000-0000-4000-8000-000000000006'
      and member.team_id = '7c040000-0000-4000-8000-000000000001'
      and member.removed_at is not null
  ),
  'The named worker moved from the workshop crew to the request crew'
);
select ok(
  exists (
    select 1 from public.v1_workforce_crew_request_events event
    where event.request_id = current_setting('crq.named')::uuid
      and event.event_type = 'approved'
      and (event.detail ->> 'with_assignment')::boolean
  ),
  'The approval is recorded as made together with the assignment'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format($$select public.v1_wf_finish_request(%L::uuid, null, 2,
      '7c030000-0000-4000-8000-000000000064')$$, current_setting('crq.named')),
  '42501', null, 'Procurement cannot finish a crew request'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  public.v1_wf_finish_request(current_setting('crq.named')::uuid,
    'Ductwork on level 3 done', 2,
    '7c030000-0000-4000-8000-000000000065') ->> 'state',
  'completed', 'The requester finishes the request when the work is done'
);
reset role;
select is(
  (select count(*)::int from public.v1_workforce_crew_members member
   where member.team_id = current_setting('crq.named_crew')::uuid
     and member.removed_at is null),
  0, 'Its workers leave the crew'
);

-- Release workers one by one --------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('crq.rel', (
  public.v1_wf_submit_request(jsonb_build_object(
      'crew_kind', 'project',
      'project_id', '7c010000-0000-4000-8000-000000000001',
      'needed_from', current_setting('crq.from'),
      'lines', jsonb_build_array(
        jsonb_build_object('worker_id', '7c020000-0000-4000-8000-000000000006'),
        jsonb_build_object('worker_id', '7c020000-0000-4000-8000-000000000007'))),
    null, '7c030000-0000-4000-8000-000000000070') ->> 'id'
), true);
reset role;
select set_config('crq.rel_lines', (
  select jsonb_agg(line.id order by line.line_number)::text
  from public.v1_workforce_crew_request_lines line
  where line.request_id = current_setting('crq.rel')::uuid and line.is_current
), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_fulfil_request(current_setting('crq.rel')::uuid,
    jsonb_build_object(
      'approve', true,
      'new_crew', jsonb_build_object('name', 'Release test crew',
        'shift_start_minute', 390, 'shift_finish_minute', 1020),
      'lines', jsonb_build_array(
        jsonb_build_object(
          'line_id', current_setting('crq.rel_lines')::jsonb ->> 0,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000006')),
        jsonb_build_object(
          'line_id', current_setting('crq.rel_lines')::jsonb ->> 1,
          'worker_ids', jsonb_build_array(
            '7c020000-0000-4000-8000-000000000007')))),
    1, '7c030000-0000-4000-8000-000000000071') ->> 'state',
  'fulfilled', 'Two named workers are on site'
);

select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format($$select public.v1_wf_release_request_worker(%L::uuid,
      '7c020000-0000-4000-8000-000000000006', null, 2,
      '7c030000-0000-4000-8000-000000000072')$$, current_setting('crq.rel')),
  '42501', null, 'Procurement cannot release a worker'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_release_request_worker(%L::uuid,
      '7c020000-0000-4000-8000-000000000006', null, 1,
      '7c030000-0000-4000-8000-000000000073')$$, current_setting('crq.rel')),
  '40001', null, 'A stale version cannot release a worker'
);
select is(
  public.v1_wf_release_request_worker(current_setting('crq.rel')::uuid,
    '7c020000-0000-4000-8000-000000000006', 'Fitting done', 2,
    '7c030000-0000-4000-8000-000000000074') ->> 'state',
  'fulfilled', 'The requester releases one worker; the request stays open'
);
select is(
  public.v1_wf_release_request_worker(current_setting('crq.rel')::uuid,
    '7c020000-0000-4000-8000-000000000006', 'Fitting done', 2,
    '7c030000-0000-4000-8000-000000000074') ->> 'record_version',
  '3', 'A retry does not release twice'
);
select ok(
  (select bool_and(
      case when person ->> 'worker_id' = '7c020000-0000-4000-8000-000000000006'
        then person ->> 'released_at' is not null
        else person ->> 'released_at' is null end)
   from jsonb_array_elements(
     public.v1_wf_get_request(current_setting('crq.rel')::uuid) -> 'lines'
   ) line, jsonb_array_elements(line -> 'assigned') person),
  'The request shows who has left the crew'
);
select throws_ok(
  format($$select public.v1_wf_release_request_worker(%L::uuid,
      '7c020000-0000-4000-8000-000000000006', null, 3,
      '7c030000-0000-4000-8000-000000000075')$$, current_setting('crq.rel')),
  '22023', 'V1_WORKFORCE_REQUEST_WORKER_NOT_ON_SITE',
  'A worker already released cannot be released again'
);
select throws_ok(
  format($$select public.v1_wf_release_request_worker(%L::uuid,
      '7c020000-0000-4000-8000-000000000001', null, 3,
      '7c030000-0000-4000-8000-000000000076')$$, current_setting('crq.rel')),
  '22023', 'V1_WORKFORCE_REQUEST_WORKER_NOT_ON_SITE',
  'A worker who is not on this request cannot be released through it'
);
reset role;
select ok(
  not exists (
    select 1 from public.v1_workforce_crew_members member
    where member.worker_id = '7c020000-0000-4000-8000-000000000006'
      and member.removed_at is null
  ) and exists (
    select 1 from public.v1_workforce_crew_members member
    where member.worker_id = '7c020000-0000-4000-8000-000000000007'
      and member.removed_at is null
  ),
  'Only the released worker left the crew'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_release_request_worker(current_setting('crq.rel')::uuid,
    '7c020000-0000-4000-8000-000000000007', null, 3,
    '7c030000-0000-4000-8000-000000000077') ->> 'state',
  'completed', 'Releasing the last worker on site finishes the request'
);
reset role;
select ok(
  (select count(*) = 2 from public.v1_workforce_crew_request_events event
   where event.request_id = current_setting('crq.rel')::uuid
     and event.event_type = 'worker_released')
  and exists (
    select 1 from public.v1_workforce_crew_request_events event
    where event.request_id = current_setting('crq.rel')::uuid
      and event.event_type = 'completed'
      and (event.detail ->> 'last_worker')::boolean
  ),
  'Each release and the finish are in the history'
);

-- Boundary ------------------------------------------------------------------

select ok(
  not has_table_privilege('authenticated',
    'public.v1_workforce_crew_requests', 'select')
  and not has_table_privilege('authenticated',
    'public.v1_workforce_crew_request_assignments', 'insert')
  and not has_function_privilege('authenticated',
    'public.v1_wf_send_crew_request_reminders()', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_list_requests()', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_finish_request(uuid,text,bigint,uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_wf_release_request_worker(uuid,uuid,text,bigint,uuid)',
    'execute'),
  'Requests are reachable only through their functions'
);

select * from finish();
rollback;

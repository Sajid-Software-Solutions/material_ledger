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

-- Fixtures: a project with its PE and SE, another project, five workers.
insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  ('5c010000-0000-4000-8000-000000000001', 'CDS-001', 'Status test',
   'active', 'project_engineer', '10000000-0000-4000-8000-000000000004',
   'admin');
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  ('5c010000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000001', 'project_engineer',
   clock_timestamp() - interval '400 days', 'Status test',
   '10000000-0000-4000-8000-000000000004', 'admin');

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
)
select
  ('5c020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'CDS-' || n, 'Status Worker ' || n, 'Helper', 'Example Manpower LLC',
  'agency_worker', date '2025-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 5) n;

select set_config('cds.today', public.v1_wf_today()::text, true);

-- Worker 1 expired, 2 expiring, 3 fine, 4 no dated document, 5 not on the
-- crew (expired, must never appear).
insert into public.v1_people_documents (
  worker_id, kind, document_number, expiry_date,
  created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
) values
  ('5c020000-0000-4000-8000-000000000001', 'visa', 'V-STATUS-1',
   current_setting('cds.today')::date - 5,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('5c020000-0000-4000-8000-000000000001', 'passport', 'P-STATUS-1',
   current_setting('cds.today')::date + 900,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('5c020000-0000-4000-8000-000000000002', 'labour_card', 'L-STATUS-2',
   current_setting('cds.today')::date + 20,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('5c020000-0000-4000-8000-000000000003', 'visa', 'V-STATUS-3',
   current_setting('cds.today')::date + 400,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('5c020000-0000-4000-8000-000000000004', 'emirates_id', 'E-STATUS-4',
   null,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('5c020000-0000-4000-8000-000000000005', 'visa', 'V-STATUS-5',
   current_setting('cds.today')::date - 1,
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');

-- The Project Engineer makes a crew of workers 1 to 4.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select public.v1_wf_save_crew(
  '{"name":"Status crew","kind":"project","project_id":"5c010000-0000-4000-8000-000000000001","shift_start_minute":390,"shift_finish_minute":1020}'::jsonb,
  0, '5c030000-0000-4000-8000-000000000001');
reset role;
select set_config('cds.crew', (
  select team.id::text from public.v1_workforce_teams team
  where team.team_name = 'Status crew'), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select public.v1_wf_set_crew_members(current_setting('cds.crew')::uuid, array[
  '5c020000-0000-4000-8000-000000000001',
  '5c020000-0000-4000-8000-000000000002',
  '5c020000-0000-4000-8000-000000000003',
  '5c020000-0000-4000-8000-000000000004'
]::uuid[], null, '5c030000-0000-4000-8000-000000000002');

-- What the crew's engineer sees ---------------------------------------------------

select is(
  public.v1_wf_crew_document_status(current_setting('cds.crew')::uuid)
    -> 'statuses',
  jsonb_build_object(
    '5c020000-0000-4000-8000-000000000001', 'expired',
    '5c020000-0000-4000-8000-000000000002', 'expiring',
    '5c020000-0000-4000-8000-000000000003', 'ok'
  ),
  'The crew''s engineer sees expired, expiring and OK, and nothing for a worker with no dated document'
);
select ok(
  public.v1_wf_crew_document_status(current_setting('cds.crew')::uuid)::text
    !~ '(STATUS-|visa|passport|labour_card|emirates|expiry_date|date_of_birth)',
  'No document kind, number or date is returned'
);
select ok(
  not (public.v1_wf_crew_document_status(current_setting('cds.crew')::uuid)
    -> 'statuses') ? '5c020000-0000-4000-8000-000000000005',
  'A worker who is not on the crew is not included'
);
select throws_ok(
  $$select public.v1_people_get('5c020000-0000-4000-8000-000000000001')$$,
  '42501', null,
  'The engineer still cannot open the person''s documents'
);

-- Who may see it ----------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  format($$select public.v1_wf_crew_document_status(%L::uuid)$$,
    current_setting('cds.crew')),
  '42501', null, 'A Site Engineer not on the project cannot see it'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format($$select public.v1_wf_crew_document_status(%L::uuid)$$,
    current_setting('cds.crew')),
  '42501', null, 'Procurement cannot see it'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select is(
  jsonb_typeof(public.v1_wf_crew_document_status(
    current_setting('cds.crew')::uuid) -> 'statuses'),
  'object', 'An organization-wide engineer sees every crew'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  public.v1_wf_crew_document_status(current_setting('cds.crew')::uuid)
    -> 'statuses' ->> '5c020000-0000-4000-8000-000000000002',
  'expiring', 'PR sees it too'
);

-- A renewal changes the status the engineer sees.
reset role;
update public.v1_people_documents
set is_current = false, ended_at = clock_timestamp(), ended_reason = 'renewed'
where worker_id = '5c020000-0000-4000-8000-000000000001' and kind = 'visa';
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_wf_crew_document_status(current_setting('cds.crew')::uuid)
    -> 'statuses' ->> '5c020000-0000-4000-8000-000000000001',
  'ok', 'Once the expired visa is replaced, the worker is OK'
);

reset role;
select ok(
  not has_function_privilege('anon',
    'public.v1_wf_crew_document_status(uuid)', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_wf_crew_document_status(uuid)', 'execute'),
  'Signed-in people may call it; the crew check decides what they see'
);

select * from finish();
rollback;

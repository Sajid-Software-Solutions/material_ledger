begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(34);

-- Surface and grants -------------------------------------------------------

select ok(
  has_function_privilege('authenticated', 'public.v1_list_user_project_access()', 'execute')
  and not has_function_privilege('anon', 'public.v1_list_user_project_access()', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_set_user_project_membership(jsonb,uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_set_user_project_membership(jsonb,uuid)', 'execute'),
  'Only authenticated actors can call the user project access functions'
);
select ok(
  not has_function_privilege('authenticated',
    'public.v1_user_project_access_target(text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_user_project_access_basis(text)', 'execute'),
  'The app-user resolver and access-basis helper are not directly callable'
);
select ok(
  (select prosecdef and 'jit=off' = any(proconfig) from pg_proc
    where oid = 'public.v1_list_user_project_access()'::regprocedure),
  'The directory is a security-definer projection with JIT disabled'
);

-- Project with a Project Engineer and a Site Engineer ---------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true);
select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"UM-PA-001",
      "name":"User access project",
      "job_contract_reference":"N-UM-001",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Site coverage"
      }],
      "buildings":[{"code":"ua","name":"Access Building"}],
      "attachments":[]
    }'::jsonb,
    'c1000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates a project with a Site Engineer'
);
select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'UM-PA-001'),
      'state', 'active', 'expected_version', 1, 'reason', 'Ready'
    ), 'c1000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The project is active'
);

select throws_ok(
  $$select public.v1_list_user_project_access()$$,
  '42501', 'V1_USER_PROJECT_ACCESS_DENIED',
  'A Project Engineer without users.view cannot read the directory'
);

set local role postgres;
create temporary table v1_upa_case as
select id as project_id from public.v1_projects where project_ref = 'UM-PA-001';
grant select on table v1_upa_case to authenticated;

-- Admin directory ----------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true);

create temporary table v1_upa_dir on commit drop as
select public.v1_list_user_project_access() as body;

create or replace function pg_temp.upa_user(p_app_user_id text)
returns jsonb language sql stable as $$
  select item from v1_upa_dir, jsonb_array_elements(body -> 'users') item
  where item ->> 'app_user_id' = p_app_user_id
$$;

select is(
  (select jsonb_array_length(body -> 'users') from v1_upa_dir), 8,
  'Every mapped account is listed once'
);
select is(
  pg_temp.upa_user('usr-local-site-engineer') ->> 'access_basis', 'assigned',
  'Site Engineers reach projects through assignments'
);
select is(
  (pg_temp.upa_user('usr-local-site-engineer') ->> 'project_count')::integer, 1,
  'The Site Engineer is counted on the project they are assigned to'
);
select is(
  pg_temp.upa_user('usr-local-site-engineer') #>> '{memberships,0,project_role}',
  'site_engineer',
  'The Site Engineer membership carries its project role'
);
select is(
  pg_temp.upa_user('usr-local-site-engineer') #>> '{memberships,0,project_ref}',
  'UM-PA-001',
  'The membership names the project reference'
);
select is(
  (pg_temp.upa_user('usr-local-project-engineer') ->> 'project_count')::integer, 1,
  'The creating Project Engineer is counted on the project'
);
select is(
  pg_temp.upa_user('usr-local-procurement') ->> 'access_basis', 'active_projects',
  'Procurement covers active and on-hold projects'
);
select is(
  (pg_temp.upa_user('usr-local-procurement') ->> 'project_count')::integer, 1,
  'Procurement is counted on the active project'
);
select ok(
  pg_temp.upa_user('usr-local-senior-mechanical-engineer') ->> 'access_basis' = 'all_projects'
  and pg_temp.upa_user('usr-local-admin') ->> 'access_basis' = 'all_projects',
  'Admin and organisation-wide engineering roles cover every project'
);
select ok(
  pg_temp.upa_user('usr-local-accountant') ->> 'access_basis' = 'none'
  and (pg_temp.upa_user('usr-local-accountant') ->> 'project_count')::integer = 0,
  'An Accountant has no structural project access'
);
select ok(
  (pg_temp.upa_user('usr-local-site-engineer') ->> 'team_eligible')::boolean
  and not (pg_temp.upa_user('usr-local-accountant') ->> 'team_eligible')::boolean,
  'Only Project and Site Engineers are offered for project teams'
);
select ok(
  (select (body ->> 'commercial_visible')::boolean from v1_upa_dir)
  and pg_temp.upa_user('usr-local-site-engineer') -> 'commercial' ? 'view',
  'Admin receives the commercial projection'
);
select is(
  (select jsonb_array_length(item -> 'members')
    from v1_upa_dir, jsonb_array_elements(body -> 'projects') item
    where item ->> 'project_ref' = 'UM-PA-001'),
  2,
  'The project team lists both engineers'
);
select ok(
  (select (item ->> 'can_manage_team')::boolean
    from v1_upa_dir, jsonb_array_elements(body -> 'projects') item
    where item ->> 'project_ref' = 'UM-PA-001'),
  'Admin can manage the project team'
);
select ok(
  (select position('10000000-0000-4000-8000-00000000000' in body::text) = 0 from v1_upa_dir),
  'No Auth UUID leaves the database'
);

-- Commands -----------------------------------------------------------------

select is(
  (public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', 'project_engineer',
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case)),
      'reason', 'Promoted for the fit-out'
    ), 'c1000000-0000-4000-8000-000000000003'::uuid
  ) ->> 'changed')::boolean,
  true,
  'Admin changes a Site Engineer to Project Engineer on the project'
);
select is(
  (select member.project_role from public.v1_project_members member
    where member.project_id = (select project_id from v1_upa_case)
      and member.member_auth_user_id = '10000000-0000-4000-8000-000000000002'
      and member.effective_to is null),
  'project_engineer',
  'The active membership now carries the new role'
);
select is(
  (public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', 'project_engineer',
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case)),
      'reason', 'Repeat'
    ), 'c1000000-0000-4000-8000-000000000004'::uuid
  ) ->> 'changed')::boolean,
  false,
  'Setting the same role again is a no-op'
);
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', null,
      'expected_version', 1,
      'reason', 'Stale'
    ), 'c1000000-0000-4000-8000-000000000005'::uuid
  )$$,
  '40001', 'V1_PROJECT_VERSION_CONFLICT',
  'A stale project version is rejected'
);
select lives_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', null,
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case)),
      'reason', 'Moved to another site'
    ), 'c1000000-0000-4000-8000-000000000006'::uuid
  )$$,
  'Admin removes the engineer from the project'
);
select is(
  (select count(*)::integer from public.v1_project_members member
    where member.project_id = (select project_id from v1_upa_case)
      and member.member_auth_user_id = '10000000-0000-4000-8000-000000000002'
      and member.effective_to is null),
  0,
  'The removal ends the dated membership'
);
set local role postgres;
select ok(
  exists (select 1 from public.v1_audit_events event
    where event.project_id = (select project_id from v1_upa_case)
      and event.event_type = 'project_member_revoked'
      and event.reason = 'Moved to another site'),
  'The removal is audited with its reason'
);
set local role authenticated;
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-project-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', null,
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case)),
      'reason', 'Leaving'
    ), 'c1000000-0000-4000-8000-000000000007'::uuid
  )$$,
  '55000', 'V1_ACTIVE_PROJECT_REQUIRES_PROJECT_ENGINEER',
  'An active project keeps at least one Project Engineer'
);
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-accountant',
      'project_id', (select project_id from v1_upa_case),
      'project_role', 'site_engineer',
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case)),
      'reason', 'Not eligible'
    ), 'c1000000-0000-4000-8000-000000000008'::uuid
  )$$,
  '42501', 'V1_PROJECT_MEMBER_MUST_HAVE_PROJECT_OR_SITE_ENGINEER_CLAIM',
  'Only engineers can join a project team'
);
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-missing',
      'project_id', (select project_id from v1_upa_case),
      'project_role', 'site_engineer',
      'expected_version', 1
    ), 'c1000000-0000-4000-8000-000000000009'::uuid
  )$$,
  'P0002', 'V1_USER_PROJECT_ACCESS_TARGET_NOT_FOUND',
  'An unknown app user is rejected'
);
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'member_auth_user_id', '10000000-0000-4000-8000-000000000002',
      'expected_version', 1
    ), 'c1000000-0000-4000-8000-000000000010'::uuid
  )$$,
  '22023', null,
  'Auth UUIDs are not accepted as command input'
);

-- Other actors -------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true);
select ok(
  not (public.v1_list_user_project_access() ->> 'commercial_visible')::boolean
  and (select bool_and(item -> 'commercial' = 'null'::jsonb)
    from jsonb_array_elements(public.v1_list_user_project_access() -> 'users') item),
  'A non-Admin user viewer receives no commercial projection'
);

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true);
select throws_ok(
  $$select public.v1_set_user_project_membership(
    jsonb_build_object(
      'app_user_id', 'usr-local-site-engineer',
      'project_id', (select project_id from v1_upa_case),
      'project_role', 'site_engineer',
      'expected_version', (select record_version from public.v1_projects
        where id = (select project_id from v1_upa_case))
    ), 'c1000000-0000-4000-8000-000000000011'::uuid
  )$$,
  '42501', 'V1_PROJECT_TEAM_MANAGEMENT_DENIED',
  'Procurement cannot change a project team'
);

select * from finish();
rollback;

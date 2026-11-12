begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select is(
  (select count(*)
   from public.v1_capability_catalog catalog
   where public.v1_workforce_is_capability_key(catalog.capability_key)),
  12::bigint,
  'The Workforce catalogue contains exactly the twelve approved T01 keys'
);

select ok(
  (select count(*)
   from public.v1_capability_catalog catalog
   where public.v1_workforce_is_capability_key(catalog.capability_key)
     and catalog.module_key = 'workforce'
     and catalog.status = 'operational'
     and catalog.authorization_mode = 'enforced'
     and catalog.is_assignable) = 12,
  'The accepted Workforce chain plus Administration enables all twelve reviewed consumers'
);

select is(
  (select count(*) from public.v1_permission_role_defaults),
  (select count(*) * 10 from public.v1_capability_catalog),
  'The exact-role matrix covers every capability after Workforce is seeded'
);

select ok(
  (select count(*)
   from public.v1_permission_role_defaults role_default
   where public.v1_workforce_is_capability_key(role_default.capability_key)
     and role_default.role_name = 'admin'
     and role_default.is_granted
     and role_default.can_delegate) = 12
  -- PR (section 37) holds every Workforce key; it delegates only view and
  -- attendance maintenance.
  and (select count(*)
   from public.v1_permission_role_defaults role_default
   where public.v1_workforce_is_capability_key(role_default.capability_key)
     and role_default.role_name = 'pr'
     and role_default.is_granted) = 12
  and not exists (
    select 1
    from public.v1_permission_role_defaults role_default
    where public.v1_workforce_is_capability_key(role_default.capability_key)
      and role_default.role_name not in ('admin', 'pr')
      and (role_default.is_granted or role_default.can_delegate)
  ),
  'Only Admin and PR receive the built-in Workforce ceiling; delegation remains explicit and audited'
);

select ok(
  (select bool_and(class.relrowsecurity)
   from pg_catalog.pg_class class
   where class.oid = any(array[
     'public.v1_workforce_trades'::regclass,
     'public.v1_workforce_internal_locations'::regclass,
     'public.v1_workforce_teams'::regclass,
     'public.v1_workforce_workers'::regclass,
     'public.v1_workforce_worker_assignments'::regclass,
     'public.v1_workforce_responsibility_assignments'::regclass
   ]))
  and not exists (
    select 1
    from (values
      ('public.v1_workforce_trades'),
      ('public.v1_workforce_internal_locations'),
      ('public.v1_workforce_teams'),
      ('public.v1_workforce_workers'),
      ('public.v1_workforce_worker_assignments'),
      ('public.v1_workforce_responsibility_assignments')
    ) as relation(relation_name)
    cross join (values
      ('select'), ('insert'), ('update'), ('delete')
    ) as privilege(privilege_name)
    where has_table_privilege(
      'authenticated', relation.relation_name, privilege.privilege_name
    )
  ),
  'All six Workforce relations use RLS and expose no authenticated CRUD privilege'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_get_workforce_foundation(text,text,integer,integer,date)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_save_workforce_worker(jsonb,bigint,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_get_workforce_foundation(text,text,integer,integer,date)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_workforce_responsibility_allows(uuid,uuid,date)',
    'execute'
  ),
  'Only protected public RPCs are exposed to authenticated callers'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '57010000-0000-4000-8000-000000000001',
  'WF-T01-001', 'Workforce T01 test project', 'active', 'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '57010000-0000-4000-8000-000000000002',
  'WF-T01-002', 'Workforce inactive project guard', 'on_hold',
  'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values (
  '57020000-0000-4000-8000-000000000001',
  '57010000-0000-4000-8000-000000000001',
  'common', 'common', 'Common / All Buildings', true
);

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values (
  '57020000-0000-4000-8000-000000000002',
  '57010000-0000-4000-8000-000000000002',
  'common', 'common', 'Common / All Buildings', true
);

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, leaving_date, current_status,
  created_by_auth_user_id, updated_by_auth_user_id
) values
  (
    '57030000-0000-4000-8000-000000000002', 'WF-T01-BOUNDED',
    'Bounded Employment Worker', 'Technician', 'Yorks AC & Ref.',
    'yorks_employee', '2026-01-01', '2026-12-31', 'inactive',
    '10000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    '57030000-0000-4000-8000-000000000003', 'WF-T01-TEAM-WINDOW',
    'Finite Team Worker', 'Technician', 'Yorks AC & Ref.',
    'yorks_employee', '2026-01-01', null, 'active',
    '10000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000004'
  );

insert into public.v1_workforce_teams (
  id, team_code, team_name, default_project_id, default_project_scope_id,
  valid_from, valid_to, is_active,
  created_by_auth_user_id, updated_by_auth_user_id
) values (
  '57050000-0000-4000-8000-000000000002', 'WF-T01-FINITE',
  'Finite Workforce test team',
  '57010000-0000-4000-8000-000000000001',
  '57020000-0000-4000-8000-000000000001',
  '2026-01-01', '2026-12-31', true,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select lives_ok(
  $sql$select public.v1_save_workforce_worker(
    '{
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "worker_number":"WF-T01-001",
      "full_name":"Ahmed Workforce",
      "designation":"Ductman",
      "employer_company":"Yorks AC & Ref.",
      "worker_type":"yorks_employee",
      "joining_date":"2026-01-01",
      "current_status":"active"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000001'::uuid
  )$sql$,
  'Admin can create a normalized worker without creating an Auth identity'
);

select is(
  (public.v1_save_workforce_worker(
    '{
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "worker_number":"WF-T01-001",
      "full_name":"Ahmed Workforce",
      "designation":"Ductman",
      "employer_company":"Yorks AC & Ref.",
      "worker_type":"yorks_employee",
      "joining_date":"2026-01-01",
      "current_status":"active"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000001'::uuid
  ) ->> 'record_version')::integer,
  1,
  'An identical retry returns the completed worker command without duplication'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker(
    '{
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "worker_number":"WF-T01-DIFFERENT",
      "full_name":"Ahmed Workforce",
      "designation":"Ductman",
      "employer_company":"Yorks AC & Ref.",
      "worker_type":"yorks_employee",
      "joining_date":"2026-01-01",
      "current_status":"active"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000001'::uuid
  )$sql$,
  '22023',
  'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'An idempotency key cannot be reused with a different worker payload'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker(
    '{
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "worker_number":"WF-T01-001",
      "full_name":"Ahmed Workforce",
      "designation":"Ductman",
      "employer_company":"Yorks AC & Ref.",
      "worker_type":"yorks_employee",
      "joining_date":"2026-01-01",
      "current_status":"active"
    }'::jsonb,
    99,
    '57040000-0000-4000-8000-000000000002'::uuid
  )$sql$,
  '40001',
  'V1_WORKFORCE_WORKER_VERSION_CONFLICT',
  'A stale worker edit cannot overwrite the current record'
);

select lives_ok(
  $sql$select public.v1_save_workforce_team(
    '{
      "team_id":"57050000-0000-4000-8000-000000000001",
      "team_code":"WF-T01-TEAM",
      "team_name":"Workforce test team",
      "default_supervisor_auth_user_id":"10000000-0000-4000-8000-000000000002",
      "default_project_id":"57010000-0000-4000-8000-000000000001",
      "default_project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-01-01",
      "is_active":true
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000003'::uuid
  )$sql$,
  'Admin can create a dated project team with a server-validated scope'
);

select lives_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000001",
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "assignment_kind":"primary",
      "team_id":"57050000-0000-4000-8000-000000000001",
      "supervisor_auth_user_id":"10000000-0000-4000-8000-000000000002",
      "project_id":"57010000-0000-4000-8000-000000000001",
      "project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-01-01",
      "reason":"Initial primary deployment"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000004'::uuid
  )$sql$,
  'Admin can record an open-ended primary assignment'
);

select lives_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000002",
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "assignment_kind":"temporary",
      "team_id":"57050000-0000-4000-8000-000000000001",
      "supervisor_auth_user_id":"10000000-0000-4000-8000-000000000002",
      "project_id":"57010000-0000-4000-8000-000000000001",
      "project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-08-01",
      "valid_to":"2026-08-31",
      "reason":"Temporary August deployment"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000005'::uuid
  )$sql$,
  'A dated temporary assignment can coexist with the primary history'
);

select is(
  public.v1_get_workforce_foundation(
    'Ahmed', 'active', 25, 0, '2026-08-15'
  ) #>> '{workers,0,effective_assignment,assignment_kind}',
  'temporary',
  'Temporary assignment takes precedence only inside its effective window'
);

select is(
  public.v1_get_workforce_foundation(
    'Ahmed', 'active', 25, 0, '2026-09-15'
  ) #>> '{workers,0,effective_assignment,assignment_kind}',
  'primary',
  'Primary assignment resumes after the temporary window without rewriting history'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000003",
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "assignment_kind":"temporary",
      "project_id":"57010000-0000-4000-8000-000000000001",
      "valid_from":"2026-08-15",
      "valid_to":"2026-09-10",
      "reason":"Competing temporary assignment"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000006'::uuid
  )$sql$,
  '23P01',
  null,
  'Overlapping temporary assignments are rejected transactionally'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000004",
      "worker_id":"57030000-0000-4000-8000-000000000002",
      "assignment_kind":"primary",
      "project_id":"57010000-0000-4000-8000-000000000001",
      "project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-02-01",
      "reason":"Must not outlive finite employment"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000008'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_ASSIGNMENT_OUTSIDE_EMPLOYMENT',
  'An open-ended assignment cannot outlive a finite worker employment window'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000005",
      "worker_id":"57030000-0000-4000-8000-000000000003",
      "assignment_kind":"primary",
      "team_id":"57050000-0000-4000-8000-000000000002",
      "project_id":"57010000-0000-4000-8000-000000000001",
      "project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-02-01",
      "reason":"Must not outlive finite team"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000009'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_ASSIGNMENT_OUTSIDE_TEAM_WINDOW',
  'An open-ended assignment cannot outlive a finite team window'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker(
    '{
      "worker_id":"57030000-0000-4000-8000-000000000001",
      "worker_number":"WF-T01-001",
      "full_name":"Ahmed Workforce",
      "designation":"Ductman",
      "employer_company":"Yorks AC & Ref.",
      "worker_type":"yorks_employee",
      "joining_date":"2026-01-01",
      "leaving_date":"2026-12-31",
      "current_status":"inactive"
    }'::jsonb,
    1,
    '57040000-0000-4000-8000-000000000010'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_WORKER_DATES_CONFLICT_WITH_ASSIGNMENTS',
  'A worker edit cannot move the leaving date before open-ended assignment history'
);

select throws_ok(
  $sql$select public.v1_save_workforce_team(
    '{
      "team_id":"57050000-0000-4000-8000-000000000001",
      "team_code":"WF-T01-TEAM",
      "team_name":"Workforce test team",
      "default_supervisor_auth_user_id":"10000000-0000-4000-8000-000000000002",
      "default_project_id":"57010000-0000-4000-8000-000000000001",
      "default_project_scope_id":"57020000-0000-4000-8000-000000000001",
      "valid_from":"2026-01-01",
      "valid_to":"2026-12-31",
      "is_active":true
    }'::jsonb,
    1,
    '57040000-0000-4000-8000-000000000013'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_TEAM_DATES_CONFLICT_WITH_ASSIGNMENTS',
  'A team edit cannot move its end before open-ended assignment history'
);

select throws_ok(
  $sql$select public.v1_save_workforce_team(
    '{
      "team_id":"57050000-0000-4000-8000-000000000003",
      "team_code":"WF-T01-INACTIVE-PROJECT",
      "team_name":"Inactive project team",
      "default_project_id":"57010000-0000-4000-8000-000000000002",
      "default_project_scope_id":"57020000-0000-4000-8000-000000000002",
      "valid_from":"2026-01-01",
      "is_active":true
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000011'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_ACTIVE_PROJECT_REQUIRED',
  'A new team cannot point to a non-active project with an active scope'
);

select throws_ok(
  $sql$select public.v1_save_workforce_worker_assignment(
    '{
      "assignment_id":"57060000-0000-4000-8000-000000000006",
      "worker_id":"57030000-0000-4000-8000-000000000003",
      "assignment_kind":"primary",
      "project_id":"57010000-0000-4000-8000-000000000002",
      "project_scope_id":"57020000-0000-4000-8000-000000000002",
      "valid_from":"2026-02-01",
      "reason":"Must require an active project"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000012'::uuid
  )$sql$,
  '23514',
  'V1_WORKFORCE_ACTIVE_PROJECT_REQUIRED',
  'A new worker assignment cannot point to a non-active project with an active scope'
);

select lives_ok(
  $sql$select public.v1_save_workforce_responsibility_assignment(
    '{
      "responsibility_assignment_id":"57070000-0000-4000-8000-000000000001",
      "auth_user_id":"10000000-0000-4000-8000-000000000002",
      "scope_kind":"team",
      "team_id":"57050000-0000-4000-8000-000000000001",
      "valid_from":"2026-01-01",
      "reason":"Site supervisor team responsibility"
    }'::jsonb,
    null,
    '57040000-0000-4000-8000-000000000007'::uuid
  )$sql$,
  'Admin can assign a dated responsibility scope without changing the user role'
);

reset role;
select ok(
  public.v1_workforce_responsibility_allows(
    '10000000-0000-4000-8000-000000000002',
    '57030000-0000-4000-8000-000000000001',
    '2026-08-15'
  ),
  'Effective responsibility resolves through the worker team assignment'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select is(
  (public.v1_get_workforce_foundation(
    'Ahmed', 'active', 25, 0, '2026-08-15'
  ) ->> 'worker_count')::integer,
  1,
  'Admin receives a filtered, server-owned Workforce projection'
);

select is(
  public.v1_get_workforce_foundation(
    'Ahmed', 'active', 25, 0, '2026-08-15'
  ) #>> '{workers,0,linked_auth_user_id}',
  null,
  'Worker master remains valid without a linked application user'
);

reset role;
select is(
  (select count(*)
   from public.v1_audit_events audit
   where audit.entity_id = '57030000-0000-4000-8000-000000000001'
     and audit.event_type = 'workforce_worker_created'),
  1::bigint,
  'The retried worker command creates exactly one immutable audit event'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_get_workforce_foundation(null,null,50,0,current_date)$$,
  '42501',
  'V1_WORKFORCE_MANAGEMENT_REQUIRED',
  'A responsibility assignment does not become delegated Worker-master authority'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_get_workforce_foundation(null,null,50,0,current_date)$$,
  '42501',
  'V1_WORKFORCE_MANAGEMENT_REQUIRED',
  'Project Engineer receives no Worker-master authority without an explicit capability'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select throws_ok(
  $$select public.v1_get_workforce_foundation(null,null,50,0,current_date)$$,
  '42501',
  'V1_WORKFORCE_MANAGEMENT_REQUIRED',
  'Procurement receives no Worker-master authority without an explicit capability'
);

reset role;

select throws_ok(
  $$delete from public.v1_workforce_workers
    where id = '57030000-0000-4000-8000-000000000001'$$,
  '42501',
  'V1_WORKFORCE_HISTORY_DELETE_FORBIDDEN',
  'Worker history cannot be hard-deleted even by a direct database owner path'
);

select * from finish();
rollback;

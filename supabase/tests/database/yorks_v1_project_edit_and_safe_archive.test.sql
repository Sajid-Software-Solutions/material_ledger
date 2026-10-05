begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(16);

select ok(
  has_function_privilege(
    'authenticated', 'public.v1_update_project(jsonb,uuid)', 'execute'
  ) and has_function_privilege(
    'authenticated', 'public.v1_archive_project(jsonb,uuid)', 'execute'
  ),
  'Authenticated callers can reach only the server-checked project commands'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.v1_can_edit_project(uuid)', 'execute'
  ),
  'The project edit authorization helper is not client-callable'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"EDIT-001",
      "name":"Original project",
      "parties":{"client":{"name":"Original Client"}},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Initial team"
      }],
      "buildings":[
        {"code":"tower_a","name":"Tower A"},
        {"code":"tower_b","name":"Tower B"}
      ],
      "attachments":[]
    }'::jsonb,
    '30000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'A project engineer can create a project to maintain'
);

select lives_ok(
  $$select public.v1_update_project(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'EDIT-001'),
      'expected_version', 1,
      'project_ref', 'EDIT-001A',
      'name', 'Updated project',
      'job_contract_reference', 'JOB-EDIT',
      'project_site', 'Dubai',
      'start_date', '2026-08-05',
      'target_completion_date', '2026-10-05',
      'notes', 'Updated through the five-stage form',
      'parties', jsonb_build_object('client', jsonb_build_object('name', 'Updated Client')),
      'buildings', jsonb_build_array(
        jsonb_build_object(
          'id', (select id from public.v1_project_scopes
            where project_id = (select id from public.v1_projects where project_ref = 'EDIT-001')
              and scope_code = 'tower_a'),
          'code', 'tower_a', 'name', 'Tower A Updated',
          'floors_levels', jsonb_build_array('GF'),
          'flags', jsonb_build_object('has_frp_room', true),
          'delivery_address', 'Tower A loading bay'
        ),
        jsonb_build_object(
          'id', (select id from public.v1_project_scopes
            where project_id = (select id from public.v1_projects where project_ref = 'EDIT-001')
              and scope_code = 'tower_b'),
          'code', 'tower_b', 'name', 'Tower B'
        )
      )
    ),
    '30000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The active Project Engineer can update the project setup with a current version'
);

select is(
  (select name from public.v1_projects where project_ref = 'EDIT-001A'),
  'Updated project',
  'The project update changes the project record'
);

select is(
  (select record_version from public.v1_projects where project_ref = 'EDIT-001A'),
  2,
  'The project update advances the optimistic version exactly once'
);

select is(
  (select name from public.v1_project_scopes
    where project_id = (select id from public.v1_projects where project_ref = 'EDIT-001A')
      and scope_code = 'tower_a'),
  'Tower A Updated',
  'The retained building scope is updated in place'
);

select ok(
  (select is_active from public.v1_project_scopes
    where project_id = (select id from public.v1_projects where project_ref = 'EDIT-001A')
      and scope_code = 'tower_b'),
  'An unchanged physical building retains its active identity'
);

set local role postgres;
select is(
  (select count(*) from public.v1_audit_events
    where entity_id = (select id from public.v1_projects where project_ref = 'EDIT-001A')
      and event_type = 'project_updated'),
  1::bigint,
  'The setup update leaves one immutable audit event'
);

select throws_ok(
  $$update public.v1_projects
      set start_date = (current_date + interval '51 years')::date
    where project_ref = 'EDIT-001A'$$,
  '22023',
  'V1_PROJECT_START_DATE_OUT_OF_SUPPORTED_RANGE',
  'A century-scale project date is rejected at the database boundary'
);

create temporary table v1_project_edit_target as
select id from public.v1_projects where project_ref = 'EDIT-001A';
grant select on table v1_project_edit_target to authenticated;
set local role authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select throws_ok(
  $$select public.v1_update_project(
    jsonb_build_object(
      'project_id', (select id from v1_project_edit_target),
      'expected_version', 2, 'project_ref', 'DENIED', 'name', 'Denied',
      'parties', jsonb_build_object(),
      'buildings', jsonb_build_array(jsonb_build_object('name', 'Denied'))
    ),
    '30000000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501',
  'V1_PROJECT_EDIT_DENIED',
  'Procurement cannot edit a project through the trusted command'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select lives_ok(
  $$select public.v1_archive_project(
    jsonb_build_object(
      'project_id', (select id from v1_project_edit_target),
      'expected_version', 2,
      'reason', 'Entered in error; retained safely for audit.'
    ),
    '30000000-0000-4000-8000-000000000004'::uuid
  )$$,
  'Admin can safely archive an inactive project record'
);

set local role postgres;
select ok(
  exists (select 1 from public.v1_projects where project_ref = 'EDIT-001A' and state = 'archived')
    and exists (select 1 from public.v1_audit_events
      where entity_id = (select id from public.v1_projects where project_ref = 'EDIT-001A')
        and event_type = 'project_archived'),
  'Safe archive preserves the project and writes its audit trail'
);

set local role authenticated;
select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"EDIT-001A",
      "name":"Replacement project",
      "buildings":[{"code":"replacement","name":"Replacement Building"}],
      "attachments":[]
    }'::jsonb,
    '30000000-0000-4000-8000-000000000005'::uuid
  )$$,
  'An archived project reference can be reused by one replacement project'
);

set local role postgres;
select is(
  (select count(*) from public.v1_projects where project_ref = 'EDIT-001A'),
  2::bigint,
  'The original archived project is retained beside its replacement'
);

select is(
  (select count(*) from public.v1_projects
    where project_ref = 'EDIT-001A' and state <> 'archived'),
  1::bigint,
  'Only one non-archived project may use a reference'
);

select * from finish();
rollback;

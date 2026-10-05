begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(13);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);

select lives_ok($$select public.v1_create_project(
  '{"project_ref":"SETUP-RECOVERY","name":"Setup recovery","initial_members":[{"auth_user_id":"10000000-0000-4000-8000-000000000002","project_role":"site_engineer"}],"buildings":[{"code":"a","name":"A"},{"code":"b","name":"B"}],"attachments":[]}'::jsonb,
  '38000000-0000-4000-8000-000000000001'::uuid)$$,
  'Core creation supports optional dates and parties');

set local role postgres;
create temporary table setup_recovery_payload as
select jsonb_build_object(
  'project_id', project.id, 'expected_version', 1,
  'project_ref', project.project_ref, 'name', 'Renamed',
  'parties', '{}'::jsonb,
  'buildings', (select jsonb_agg(jsonb_build_object(
    'id', scope.id, 'code', scope.scope_code, 'name', scope.name,
    'flags', jsonb_build_object('has_frp_room', false)) order by scope.scope_code)
    from public.v1_project_scopes scope where scope.project_id = project.id
      and scope.scope_kind = 'building')
) as payload from public.v1_projects project where project_ref = 'SETUP-RECOVERY';
grant select on setup_recovery_payload to authenticated;
set local role authenticated;

select lives_ok($$select public.v1_update_project(
  (select payload from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000002'::uuid)$$,
  'Project Engineer can update while preserving all physical scope IDs');
select lives_ok($$select public.v1_update_project(
  (select payload from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000002'::uuid)$$,
  'Dropped update responses replay the original result before version checking');
select throws_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('name','Different') from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000002'::uuid)$$,
  '22023','V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'A replay key cannot be reused with changed reviewed input');
select throws_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',2,
    'buildings', jsonb_build_array(payload->'buildings'->0)) from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000003'::uuid)$$,
  '55000','V1_PROJECT_BUILDING_RETIREMENT_REQUIRES_RECONCILIATION',
  'Project Engineer cannot retire a persisted scope through setup');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}', true);
select lives_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',2,'name','Site update') from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000004'::uuid)$$,
  'Assigned Site Engineer can update retained scopes');
select throws_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',3,
    'buildings',jsonb_build_array(payload->'buildings'->0)) from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000005'::uuid)$$,
  '55000','V1_PROJECT_BUILDING_RETIREMENT_REQUIRES_RECONCILIATION',
  'Site Engineer cannot retire a persisted scope through setup');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select throws_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',3) from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000006'::uuid)$$,
  '42501','V1_PROJECT_EDIT_DENIED',
  'Procurement remains denied even when all scope IDs are preserved');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}', true);
select lives_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',3,'name','Admin update') from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000007'::uuid)$$,
  'Admin can update retained scopes');
select throws_ok($$select public.v1_update_project(
  (select payload || jsonb_build_object('expected_version',4,
    'buildings',jsonb_build_array(payload->'buildings'->0)) from setup_recovery_payload),
  '38000000-0000-4000-8000-000000000008'::uuid)$$,
  '55000','V1_PROJECT_BUILDING_RETIREMENT_REQUIRES_RECONCILIATION',
  'Admin also requires controlled dependency reconciliation to retire a scope');

set local role postgres;
select is((select record_version from public.v1_projects where project_ref='SETUP-RECOVERY'),4,
  'Rejected removals and same-key replay do not advance the project version');
select is((select count(*) from public.v1_project_scopes where project_id=(select id from public.v1_projects where project_ref='SETUP-RECOVERY') and is_active),3::bigint,
  'Common and both physical scope identities remain active and preserved');
select is((select count(*) from public.v1_audit_events where project_id=(select id from public.v1_projects where project_ref='SETUP-RECOVERY') and event_type='project_updated'),3::bigint,
  'Only the three successful unique update intents produce audit events');
select * from finish();
rollback;

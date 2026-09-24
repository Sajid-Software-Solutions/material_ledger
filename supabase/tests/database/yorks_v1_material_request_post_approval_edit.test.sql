begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(33);

select ok(
  has_function_privilege('authenticated',
    'public.v1_set_material_request_post_approval_edit(jsonb,uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_set_material_request_post_approval_edit(jsonb,uuid)', 'execute')
  and not has_table_privilege('authenticated',
    'public.v1_material_requests', 'update'),
  'Grant mutation is an authenticated trusted command, not a table write'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_create_project(
  '{"project_ref":"MR-POST-EDIT-001","name":"Post Approval Editing",
    "parties":{},"initial_members":[{"auth_user_id":
    "10000000-0000-4000-8000-000000000002","project_role":"site_engineer",
    "reason":"Request creator"}],"buildings":[{"code":"main",
    "name":"Main Building"}],"attachments":[]}'::jsonb,
  'ae000000-0000-4000-8000-000000000001'::uuid)$$,
  'Project Engineer creates the isolated editing fixture');
select lives_ok($$select public.v1_set_project_state(jsonb_build_object(
  'project_id', (select id from public.v1_projects
    where project_ref = 'MR-POST-EDIT-001'),
  'state', 'active', 'expected_version', 1,
  'reason', 'Ready for post-approval edit testing'),
  'ae000000-0000-4000-8000-000000000002'::uuid)$$,
  'Project is activated');

set local role postgres;
create temporary table post_edit_fixture as select
  project.id as project_id,
  (select id from public.v1_project_scopes scope
    where scope.project_id = project.id and scope.scope_kind = 'building'
    limit 1) as scope_id
from public.v1_projects project
where project.project_ref = 'MR-POST-EDIT-001';
create temporary table post_edit_payload as select jsonb_build_object(
  'request_id', 'ae100000-0000-4000-8000-000000000001',
  'expected_version', 0,
  'project_id', project_id, 'scope_id', scope_id,
  'title', 'Initial engineering request', 'timing', 'normal',
  'scheduled_date', null, 'delivery_note', null,
  'lines', jsonb_build_array(jsonb_build_object(
    'id', 'ae110000-0000-4000-8000-000000000001',
    'display_order', 1, 'source_kind', 'custom',
    'source_boq_group_id', null, 'source_boq_row_id', null,
    'item_description', 'Duct fitting', 'brand_origin', null,
    'technical_attributes', '{}'::jsonb,
    'requested_qty', '2', 'unit', 'Nos'
  ))) as payload from post_edit_fixture;
grant select on table post_edit_fixture, post_edit_payload to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}', true);
select lives_ok($$select public.v1_save_material_request_draft(
  (select payload from post_edit_payload))$$,
  'Site Engineer creates request');
select lives_ok($$select public.v1_submit_material_request(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 1),
  'ae200000-0000-4000-8000-000000000001'::uuid)$$,
  'Site Engineer submits request');
select throws_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 2,
    'enabled', true, 'procurement_editor_auth_user_id', null),
  'ae200000-0000-4000-8000-000000000002'::uuid)$$,
  '42501', 'V1_POST_APPROVAL_EDIT_GRANT_DENIED',
  'Site Engineer cannot grant editing');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_decide_material_request(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 2,
    'decision', 'approved', 'reason', null),
  'ae200000-0000-4000-8000-000000000003'::uuid)$$,
  'Project Engineer approves request');
select ok((select
    (projection ->> 'post_approval_edit_enabled')::boolean = false
    and projection ->> 'procurement_editor_auth_user_id' is null
  from (select public.v1_material_request_projection(
    'ae100000-0000-4000-8000-000000000001'::uuid) as projection) projected),
  'Editing is off by default after approval');
select ok((public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Assigned Project Engineer can manage the grant');

set local role postgres;
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, reason,
  assigned_by_auth_user_id, assigned_by_role
) select project_id,
  '10000000-0000-4000-8000-000000000002'::uuid,
  'project_engineer', 'Explicit dual assignment for approval',
  '10000000-0000-4000-8000-000000000001'::uuid, 'project_engineer'
from post_edit_fixture;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}', true);
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Dual-assigned Site Engineer still needs explicit approval capability');
set local role postgres;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, reason,
  changed_by_auth_user_id
) values (
  '10000000-0000-4000-8000-000000000002'::uuid,
  'material_requests.approve', 'grant', 'organization',
  'Explicit dual-assigned approval test',
  '10000000-0000-4000-8000-000000000004'::uuid
);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}', true);
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Exact Site Engineer cannot grant editing under the current approval policy');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}', true);
select ok((public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Global Engineering approver needs no per-project membership row');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}', true);
select ok((public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Admin can manage the audited edit grant');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_edit_post_approval')::boolean,
  'Procurement has no default editing permission');
select throws_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 3,
    'enabled', true, 'procurement_editor_auth_user_id', null),
  'ae200000-0000-4000-8000-000000000004'::uuid)$$,
  '42501', 'V1_POST_APPROVAL_EDIT_GRANT_DENIED',
  'Procurement cannot self-grant');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}', true);
select throws_ok($$select public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid)$$,
  '42501', 'V1_MATERIAL_REQUEST_NOT_READABLE',
  'Accountant cannot read or manage Engineering MR editing');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 3,
    'enabled', true, 'procurement_editor_auth_user_id',
    '10000000-0000-4000-8000-000000000003'),
  'ae200000-0000-4000-8000-000000000005'::uuid)$$,
  'Approver grants a named active Procurement editor');
select is((public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 3,
    'enabled', true, 'procurement_editor_auth_user_id',
    '10000000-0000-4000-8000-000000000003'),
  'ae200000-0000-4000-8000-000000000005'::uuid) ->> 'record_version')::integer,
  4, 'Idempotent grant retry returns the original committed version');
select throws_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 3,
    'enabled', false, 'procurement_editor_auth_user_id', null),
  'ae200000-0000-4000-8000-000000000006'::uuid)$$,
  '40001', 'V1_MATERIAL_REQUEST_VERSION_CONFLICT',
  'A competing stale grant update cannot overwrite the current choice');

set local role postgres;
insert into public.v1_material_request_line_commercials (
  request_line_id, unit_cost, currency_code
) values ('ae110000-0000-4000-8000-000000000001'::uuid, 10, 'AED');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select ok((public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_edit_post_approval')::boolean,
  'Named Procurement editor can edit before arrangement');
select lives_ok($$select public.v1_update_material_request_for_approval(
  (select payload from post_edit_payload) || jsonb_build_object(
    'expected_version', 4, 'title', 'Procurement amendment proposal',
    'lines', jsonb_build_array(jsonb_build_object(
      'id', 'ae110000-0000-4000-8000-000000000001',
      'display_order', 1, 'source_kind', 'custom',
      'source_boq_group_id', null, 'source_boq_row_id', null,
      'item_description', 'Revised duct fitting', 'brand_origin', null,
      'technical_attributes', '{}'::jsonb,
      'requested_qty', '3', 'unit', 'Nos'))),
  'ae200000-0000-4000-8000-000000000007'::uuid)$$,
  'Named Procurement edit creates a versioned Engineering proposal');
select ok((select projection ->> 'state' = 'awaiting_request_approval'
    and (projection ->> 'post_approval_amendment_pending')::boolean
    and (projection ->> 'record_version')::integer = 5
    from (select public.v1_material_request_projection(
      'ae100000-0000-4000-8000-000000000001'::uuid) as projection) projected),
  'Proposal blocks arrangement and remains visible to its named editor');
set local role postgres;
select ok((select unit_cost = 10 from public.v1_material_request_line_commercials
  where request_line_id =
    'ae110000-0000-4000-8000-000000000001'::uuid),
  'The original line cost link survives the amendment');
select ok((select snapshot_reason = 'post_approval_amendment'
  from public.v1_material_request_revision_snapshots
  where request_id = 'ae100000-0000-4000-8000-000000000001'::uuid
    and request_record_version = 5),
  'The revised Engineering proposal has a dedicated immutable snapshot');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select throws_ok($$select public.v1_begin_arrangement(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 5),
  'ae200000-0000-4000-8000-000000000008'::uuid)$$,
  '22023', 'V1_BEGIN_ARRANGEMENT_STATE_INVALID',
  'Procurement cannot arrange a pending amendment');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_decide_material_request(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 5,
    'decision', 'approved', 'reason', null),
  'ae200000-0000-4000-8000-000000000009'::uuid)$$,
  'Project Engineer reapproves the proposed version');
set local role postgres;
select ok((select state = 'approved_for_arrangement'
    and not post_approval_amendment_pending and record_version = 6
    from public.v1_material_requests where id =
      'ae100000-0000-4000-8000-000000000001'::uuid)
  and (select count(*) = 2 from public.v1_material_request_decisions
    where request_id =
      'ae100000-0000-4000-8000-000000000001'::uuid and decision = 'approved'),
  'Reapproval preserves both decisions and clears pending state');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 6,
    'enabled', false, 'procurement_editor_auth_user_id', null),
  'ae200000-0000-4000-8000-000000000010'::uuid)$$,
  'Approver revokes post-approval editing');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_edit_post_approval')::boolean,
  'Revocation immediately removes Procurement edit authority');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok($$select public.v1_set_material_request_post_approval_edit(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 7,
    'enabled', true, 'procurement_editor_auth_user_id',
    '10000000-0000-4000-8000-000000000003'),
  'ae200000-0000-4000-8000-000000000011'::uuid)$$,
  'Approver can re-enable the window before arrangement');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select lives_ok($$select public.v1_begin_arrangement(
  jsonb_build_object('request_id',
    'ae100000-0000-4000-8000-000000000001', 'expected_version', 8),
  'ae200000-0000-4000-8000-000000000012'::uuid)$$,
  'Procurement begins arrangement after reapproval');
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_edit_post_approval')::boolean,
  'Starting arrangement ends the edit window');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select ok(not (public.v1_material_request_projection(
  'ae100000-0000-4000-8000-000000000001'::uuid) ->> 'can_manage_post_approval_edit')::boolean,
  'Approver cannot reopen editing after arrangement starts');

select * from finish();
rollback;

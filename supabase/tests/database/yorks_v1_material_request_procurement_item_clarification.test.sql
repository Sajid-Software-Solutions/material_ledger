begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(40);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_update_material_request_procurement_item(jsonb,uuid)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.v1_update_material_request_procurement_item(jsonb,uuid)',
    'execute'
  ),
  'clarification is exposed only as an authenticated trusted command'
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
      "project_ref":"MR-CLARIFY-001",
      "name":"Procurement Clarification Project",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Request creator"
      }],
      "buildings":[{"code":"main","name":"Main Building"}],
      "attachments":[]
    }'::jsonb,
    '90700000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the clarification test project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects
        where project_ref = 'MR-CLARIFY-001'),
      'state', 'active', 'expected_version', 1,
      'reason', 'Ready for Material Requests'
    ),
    '90700000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Project is activated through the trusted command'
);

set local role postgres;
create temporary table v1_clarification_target as
select project.id as project_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'building' limit 1) as scope_id
from public.v1_projects project
where project.project_ref = 'MR-CLARIFY-001';
grant select on table v1_clarification_target to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_save_material_request_draft(jsonb_build_object(
    'request_id', '90710000-0000-4000-8000-000000000001',
    'expected_version', 0,
    'project_id', (select project_id from v1_clarification_target),
    'scope_id', (select scope_id from v1_clarification_target),
    'title', 'Ambiguous fan request', 'timing', 'normal',
    'scheduled_date', null, 'delivery_note', null,
    'lines', jsonb_build_array(jsonb_build_object(
      'id', '90720000-0000-4000-8000-000000000001',
      'display_order', 1, 'source_kind', 'custom',
      'source_boq_group_id', null, 'source_boq_row_id', null,
      'item_description', 'Exhaust fan', 'brand_origin', null,
      'technical_attributes', jsonb_build_object('size', '12 inch'),
      'requested_qty', '3', 'unit', 'Nos'
    ))
  ))$$,
  'Site Engineer saves the original ambiguous request'
);

select lives_ok(
  $$select public.v1_submit_material_request(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 1
    ), '90730000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Site Engineer submits the request'
);

set local role postgres;
select is(
  (select requested_item_description
   from public.v1_material_request_lines
   where id = '90720000-0000-4000-8000-000000000001'::uuid),
  'Exhaust fan',
  'the submitted request has an immutable original-description snapshot'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 2, 'decision', 'approved', 'reason', null
    ), '90730000-0000-4000-8000-000000000008'::uuid
  )$$,
  'Project Engineer approves the original request for Procurement'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select lives_ok(
  $$select public.v1_begin_arrangement(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 3
    ), '90730000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Procurement begins the arrangement before clarifying the item'
);

set local role postgres;
create temporary table v1_clarification_arrangement as
select arrangement.id as arrangement_id, arrangement_line.id as arrangement_line_id
from public.v1_procurement_arrangements arrangement
join public.v1_procurement_arrangement_lines arrangement_line
  on arrangement_line.arrangement_id = arrangement.id
where arrangement.request_id =
    '90710000-0000-4000-8000-000000000001'::uuid
  and arrangement.status = 'working';
grant select on table v1_clarification_arrangement to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 4,
      'item_description', 'Unauthorized edit',
      'model_reference', 'BAD-1'
    ), '90730000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501', 'V1_PROCUREMENT_ITEM_CLARIFICATION_DENIED',
  'Site Engineering cannot use the Procurement clarification command'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 2,
      'item_description', 'Exhaust fan EF-300',
      'model_reference', 'EF-300'
    ), '90730000-0000-4000-8000-000000000004'::uuid
  )$$,
  '40001', 'V1_MATERIAL_REQUEST_VERSION_CONFLICT',
  'a stale Procurement screen cannot overwrite current item identity'
);

select lives_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 4,
      'item_description', 'Exhaust fan EF-300',
      'model_reference', 'EF-300'
    ), '90730000-0000-4000-8000-000000000005'::uuid
  )$$,
  'Procurement clarifies the effective description and model'
);

set local role postgres;
select ok(
  (select item_description = 'Exhaust fan EF-300'
      and technical_attributes ->> 'model' = 'EF-300'
      and requested_item_description = 'Exhaust fan'
      and requested_technical_attributes ->> 'size' = '12 inch'
      and not (requested_technical_attributes ? 'model')
      and procurement_clarification_version = 1
   from public.v1_material_request_lines
   where id = '90720000-0000-4000-8000-000000000001'::uuid),
  'effective identity changes while all original Engineering evidence remains'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 4,
      'item_description', 'Exhaust fan EF-300',
      'model_reference', 'EF-300'
    ), '90730000-0000-4000-8000-000000000005'::uuid
  )$$,
  'an identical retry returns the first confirmed response'
);

set local role postgres;
select is(
  (select count(*)::integer from public.v1_audit_events
   where event_type = 'procurement_item_clarified'
     and entity_id = '90720000-0000-4000-8000-000000000001'::uuid),
  1,
  'an identical retry creates no duplicate audit event'
);

select ok(
  (select state = 'awaiting_request_approval'
      and current_action_owner_role = 'project_engineer'
      and procurement_clarification_revision = 1
      and approved_procurement_clarification_revision = 0
   from public.v1_material_requests
   where id = '90710000-0000-4000-8000-000000000001'::uuid),
  'clarification atomically transfers the request to Engineering review'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 4,
      'item_description', 'Different payload',
      'model_reference', null
    ), '90730000-0000-4000-8000-000000000005'::uuid
  )$$,
  '22023', 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'one command key cannot be reused for a different correction'
);

select throws_ok(
  $$select public.v1_save_arrangement(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'arrangement_id', (select arrangement_id
        from v1_clarification_arrangement),
      'expected_request_version', (
        public.v1_arrangement_projection(
          '90710000-0000-4000-8000-000000000001'::uuid
        ) ->> 'request_record_version'
      )::integer,
      'expected_arrangement_version', 1,
      'procurement_note', null,
      'lines', jsonb_build_array(jsonb_build_object(
        'arrangement_line_id', (select arrangement_line_id
          from v1_clarification_arrangement),
        'source_kind', 'external_supplier', 'external_supplier', null,
        'inventory_item_id', null, 'decision', 'full', 'arranged_qty', '3',
        'reason', null, 'unit_cost', null,
        'external_source_ready', false,
        'external_expected_date', null, 'external_reference', null
      ))
    ), '90730000-0000-4000-8000-000000000006'::uuid
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_APPROVAL_REQUIRED',
  'Procurement cannot save arrangement before Engineering reapproval'
);

select ok(
  (select (projection ->> 'clarification_review_required')::boolean
      and (projection ->> 'can_clarify')::boolean
      and not (projection ->> 'can_save')::boolean
   from (select public.v1_arrangement_projection(
     '90710000-0000-4000-8000-000000000001'::uuid
   ) as projection) result),
  'pending workspace permits identity correction but locks arrangement save'
);

select throws_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 5, 'decision', 'approved', 'reason', null
    ), '90730000-0000-4000-8000-000000000009'::uuid
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_DECISION_DENIED',
  'Procurement cannot approve its own clarification'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 5, 'decision', 'approved', 'reason', null
    ), '90730000-0000-4000-8000-000000000010'::uuid
  )$$,
  'Project Engineer approves the exact Procurement clarification revision'
);
select ok(
  (public.v1_get_material_workflow_command_outcome('v1_decide_material_request',
    '90730000-0000-4000-8000-000000000010') ->> 'status') = 'confirmed'
  and (public.v1_get_material_workflow_command_view('v1_decide_material_request',
    '90730000-0000-4000-8000-000000000010') -> 'response') ?& array['id','state','lines'],
  'actor can reconcile a receipt before separately reading the current projection'
);
select ok(
  not (public.v1_get_material_workflow_command_outcome('v1_decide_material_request',
    '90730000-0000-4000-8000-000000000010')::text like '%unit_cost%'),
  'Engineering outcome readback contains no protected commercial fields'
);
select is(
  public.v1_get_material_workflow_command_outcome('v1_decide_material_request',
    '90730000-0000-4000-8000-000000000099')->>'status', 'unknown',
  'absent command is unknown, never a fabricated rejection'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select is(
  public.v1_get_material_workflow_command_outcome('v1_decide_material_request',
    '90730000-0000-4000-8000-000000000010')->>'status','unknown',
  'another actor cannot discover or retrieve the confirmed receipt'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',true);
select ok(not has_function_privilege('anon',
  'public.v1_get_material_workflow_command_outcome(text,uuid)','execute'),
  'anonymous callers cannot read command outcomes');

reset role;

select ok(
  (select response_json ?& array['id','state','timing','lines','project_id','scope_id']
    and response_json ->> 'state' = 'arranging'
    and not (response_json::text like '%unit_cost%')
   from public.v1_idempotency_keys
   where idempotency_key = '90730000-0000-4000-8000-000000000010'),
  'clarification approval stores the role-safe Material Request response'
);

select ok(
  not has_function_privilege('authenticated',
    'public.v1_decide_material_request_before_response_contract(jsonb,uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_decide_material_request(jsonb,uuid)', 'execute'),
  'response adapter retains the private implementation and public RPC boundary'
);
-- Simulate the stored response of an approval completed before this migration.
update public.v1_idempotency_keys
set response_json = jsonb_build_object(
  'request_id','90710000-0000-4000-8000-000000000001', 'request_state','arranging')
where idempotency_key = '90730000-0000-4000-8000-000000000010';
set local role authenticated;
select ok(
  public.v1_decide_material_request(
    jsonb_build_object('request_id','90710000-0000-4000-8000-000000000001',
      'expected_version',5,'decision','approved','reason',null),
    '90730000-0000-4000-8000-000000000010'::uuid
  ) ?& array['id','state','timing','lines'],
  'retry of a pre-fix committed approval returns a readable request'
);
select ok(
  public.v1_decide_material_request(
    jsonb_build_object('request_id','90710000-0000-4000-8000-000000000001',
      'expected_version',5,'decision','approved','reason',null),
    '90730000-0000-4000-8000-000000000010'::uuid
  ) ?& array['id','state','timing','lines'],
  'subsequent retry retains the repaired response'
);
reset role;
select is(
  (select count(*)::integer from public.v1_audit_events
   where idempotency_key = '90730000-0000-4000-8000-000000000010'),
  1, 'response repair does not duplicate the approval audit event'
);


set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select ok(
  (select not (projection ->> 'clarification_review_required')::boolean
      and (projection ->> 'can_save')::boolean
      and (projection ->> 'procurement_clarification_revision')::integer = 1
      and (projection ->>
        'approved_procurement_clarification_revision')::integer = 1
   from (select public.v1_arrangement_projection(
     '90710000-0000-4000-8000-000000000001'::uuid
   ) as projection) result),
  'approval unlocks the preserved working arrangement for Procurement'
);

select lives_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', 6,
      'item_description', 'Exhaust fan EF-300 final',
      'model_reference', 'EF-300R'
    ), '90730000-0000-4000-8000-000000000012'::uuid
  )$$,
  'a later Procurement correction creates a new Engineering checkpoint'
);

select ok(
  (select (projection ->> 'clarification_review_required')::boolean
      and not (projection ->> 'can_save')::boolean
      and (projection ->> 'procurement_clarification_revision')::integer = 2
      and (projection ->>
        'approved_procurement_clarification_revision')::integer = 1
   from (select public.v1_arrangement_projection(
     '90710000-0000-4000-8000-000000000001'::uuid
   ) as projection) result),
  'the earlier approval cannot authorize a later correction'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select ok(
  public.v1_decide_material_request(
    jsonb_build_object('request_id','90710000-0000-4000-8000-000000000001',
      'expected_version',7,'decision','returned','reason','Check model again'),
    '90730000-0000-4000-8000-000000000014'::uuid
  ) ?& array['id','state','timing','lines'],
  'returning a clarification also returns the Material Request contract'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}', true);
select lives_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object('request_id','90710000-0000-4000-8000-000000000001',
      'request_line_id','90720000-0000-4000-8000-000000000001',
      'expected_request_version',8,'item_description','Exhaust fan final checked',
      'model_reference','EF-300R'),
    '90730000-0000-4000-8000-000000000015'::uuid
  )$$, 'Procurement can correct a returned clarification'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select lives_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'expected_version', 9, 'decision', 'approved', 'reason', null
    ), '90730000-0000-4000-8000-000000000013'::uuid
  )$$,
  'Project Engineer approves the newer clarification revision independently'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select lives_ok(
  $$select public.v1_save_arrangement(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'arrangement_id', (select arrangement_id
        from v1_clarification_arrangement),
      'expected_request_version', 10,
      'expected_arrangement_version', 1,
      'procurement_note', null,
      'lines', jsonb_build_array(jsonb_build_object(
        'arrangement_line_id', (select arrangement_line_id
          from v1_clarification_arrangement),
        'source_kind', 'external_supplier', 'external_supplier', null,
        'inventory_item_id', null, 'decision', 'full', 'arranged_qty', '3',
        'reason', null, 'unit_cost', null,
        'external_source_ready', false,
        'external_expected_date', null, 'external_reference', null
      ))
    ), '90730000-0000-4000-8000-000000000011'::uuid
  )$$,
  'Procurement saves arrangement only after Engineering reapproval'
);

select throws_ok(
  $$select public.v1_update_material_request_procurement_item(
    jsonb_build_object(
      'request_id', '90710000-0000-4000-8000-000000000001',
      'request_line_id', '90720000-0000-4000-8000-000000000001',
      'expected_request_version', (
        public.v1_arrangement_projection(
          '90710000-0000-4000-8000-000000000001'::uuid
        ) ->> 'request_record_version'
      )::integer,
      'item_description', 'Too late',
      'model_reference', 'LATE-1'
    ), '90730000-0000-4000-8000-000000000007'::uuid
  )$$,
  '22023', 'V1_PROCUREMENT_ITEM_CLARIFICATION_LOCKED',
  'item identity is locked after the arrangement is saved'
);

select throws_ok(
  $$update public.v1_material_request_lines
    set item_description = 'Direct bypass'
    where id = '90720000-0000-4000-8000-000000000001'::uuid$$,
  '42501', null,
  'Procurement cannot bypass the command with a direct line update'
);

set local role postgres;
select throws_ok(
  $$update public.v1_material_request_lines
    set requested_item_description = 'Rewrite history'
    where id = '90720000-0000-4000-8000-000000000001'::uuid$$,
  '42501', 'V1_MATERIAL_REQUEST_REQUESTED_SNAPSHOT_IMMUTABLE',
  'even privileged writes cannot rewrite original requested evidence'
);

select * from finish();
rollback;

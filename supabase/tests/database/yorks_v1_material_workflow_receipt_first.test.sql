begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();
-- The four global Engineer roles are exact Auth roles, not editable metadata.
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('10000000-0000-4000-8000-000000000011','authenticated','authenticated',
  'p2-workshop@yorks.local.test','{"role":"workshop_in_charge","app_user_id":"p2-workshop"}',
  '{"full_name":"P2 Workshop"}',now(),now()),
 ('10000000-0000-4000-8000-000000000012','authenticated','authenticated',
  'p2-document@yorks.local.test','{"role":"document_controller","app_user_id":"p2-document"}',
  '{"full_name":"P2 Document"}',now(),now());


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
      "project_ref":"P2-RECEIPT-FIRST",
      "name":"Receipt first projection isolation",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Request creator"
      }],
      "buildings":[{"code":"main","name":"Main Building"}],
      "attachments":[]
    }'::jsonb,
    'a1600000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the clarification test project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects
        where project_ref = 'P2-RECEIPT-FIRST'),
      'state', 'active', 'expected_version', 1,
      'reason', 'Ready for Material Requests'
    ),
    'a1600000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Project is activated through the trusted command'
);

set local role postgres;
create temporary table v1_clarification_target as
select project.id as project_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'building' limit 1) as scope_id
from public.v1_projects project
where project.project_ref = 'P2-RECEIPT-FIRST';
grant select on table v1_clarification_target to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_save_material_request_draft(jsonb_build_object(
    'request_id', 'a1610000-0000-4000-8000-000000000001',
    'expected_version', 0,
    'project_id', (select project_id from v1_clarification_target),
    'scope_id', (select scope_id from v1_clarification_target),
    'title', 'Ambiguous fan request', 'timing', 'normal',
    'scheduled_date', null, 'delivery_note', null,
    'lines', jsonb_build_array(jsonb_build_object(
      'id', 'a1620000-0000-4000-8000-000000000001',
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
      'request_id', 'a1610000-0000-4000-8000-000000000001',
      'expected_version', 1
    ), 'a1630000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Site Engineer submits the request'
);

set local role postgres;
select is(
  (select requested_item_description
   from public.v1_material_request_lines
   where id = 'a1620000-0000-4000-8000-000000000001'::uuid),
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
      'request_id', 'a1610000-0000-4000-8000-000000000001',
      'expected_version', 2, 'decision', 'approved', 'reason', null
    ), 'a1630000-0000-4000-8000-000000000008'::uuid
  )$$,
  'Project Engineer approves the original request for Procurement'
);

-- The receipt is metadata-only. A stored payload must never be replayed after
-- authority changes, even when its historical response contained more fields.
reset role;
update public.v1_idempotency_keys set response_json=response_json||
  '{"unit_cost":"historical-commercial-value"}'::jsonb
where idempotency_key='a1630000-0000-4000-8000-000000000008';
create temporary table p2_effect_counts as select
 (select count(*) from public.v1_idempotency_keys) commands,
 (select count(*) from public.v1_audit_events) audits;
create temporary table p2_projection_calls(called_at timestamptz);
alter function public.v1_material_request_projection(uuid)
  rename to v1_material_request_projection_before_p2_test;
create function public.v1_material_request_projection(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  insert into pg_temp.p2_projection_calls values(clock_timestamp());
  perform pg_sleep(0.15);
  return public.v1_material_request_projection_before_p2_test(p_request_id);
end $$;
revoke all on function public.v1_material_request_projection(uuid) from public,anon;
grant execute on function public.v1_material_request_projection(uuid) to authenticated;
set local role authenticated;
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'confirmed','exact actor gets committed truth independently of slow projection');
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->'response',
 'null'::jsonb,'old clients receive confirmed with null optional view');
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'entity_id',
 'a1610000-0000-4000-8000-000000000001','receipt retains the exact request root');
select ok(not public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')::text
 like '%historical-commercial-value%','receipt never replays historical commercial response');
reset role;
select is((select count(*) from p2_projection_calls),0::bigint,
 'repeated receipt reads never invoke the slow projection');
set local role authenticated;
select ok((public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->'response')
 ?& array['id','state','lines'],'separate authorized view returns the current role-safe projection');
select ok(not public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')::text
 like '%unit_cost%','Engineering current hydration has no protected commercial fields');
reset role;
select is((select count(*) from p2_projection_calls),2::bigint,
 'only explicit separate view calls invoke screen projection');
set local role authenticated;
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000099')->>'status',
 'unknown','a missing command cannot hydrate or prove rejection');
select is(public.v1_get_material_workflow_command_outcome(
 'v1_cancel_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','the same key under another allowlisted command proves nothing');
select throws_ok($$select public.v1_get_material_workflow_command_view(
 'v1_delete_everything','a1630000-0000-4000-8000-000000000008')$$,
 '22023','V1_COMMAND_OUTCOME_INVALID','view uses the exact receipt command allowlist');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','site_engineer cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','site_engineer cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','procurement cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','procurement cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','admin cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','admin cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','accountant cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','accountant cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','senior_mechanical_engineer cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','senior_mechanical_engineer cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000010","role":"authenticated","app_metadata":{"role":"project_manager"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','project_manager cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','project_manager cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000011","role":"authenticated","app_metadata":{"role":"workshop_in_charge"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','workshop_in_charge cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','workshop_in_charge cannot hydrate another actor receipt');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000012","role":"authenticated","app_metadata":{"role":"document_controller"}}',true);
select is(public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','document_controller cannot discover another actor receipt');
select is(public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')->>'status',
 'unknown','document_controller cannot hydrate another actor receipt');
reset role;
select is((select count(*) from p2_projection_calls),2::bigint,
 'unknown/foreign receipts never call the heavy projection');
select is((select count(*) from public.v1_idempotency_keys),
 (select commands from p2_effect_counts),'read-only recovery creates no command');
select is((select count(*) from public.v1_audit_events),
 (select audits from p2_effect_counts),'read-only recovery appends no business audit');
select ok(not has_function_privilege('anon',
 'public.v1_get_material_workflow_command_view(text,uuid)','execute'),
 'anonymous callers cannot use the separate view endpoint');
select ok(has_function_privilege('authenticated',
 'public.v1_get_material_workflow_command_view(text,uuid)','execute'),
 'signed-in callers use the protected endpoint');
update public.v1_profiles set is_active=false
where auth_user_id='10000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select throws_ok($$select public.v1_get_material_workflow_command_outcome(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')$$,
 '42501','V1_MATERIAL_REQUEST_NOT_READABLE','deactivated actors cannot witness protected receipts');
select throws_ok($$select public.v1_get_material_workflow_command_view(
 'v1_decide_material_request','a1630000-0000-4000-8000-000000000008')$$,
 '42501','V1_MATERIAL_REQUEST_NOT_READABLE','separate hydration rechecks current active authority');
reset role;
select * from finish();
rollback;

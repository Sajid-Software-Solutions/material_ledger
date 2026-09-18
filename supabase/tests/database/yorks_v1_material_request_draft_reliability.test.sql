begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(14);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_save_material_request_draft_idempotent(jsonb,uuid)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.v1_get_material_request_draft_save_result(jsonb,uuid)',
    'execute'
  ),
  'authenticated actors can call only the new trusted save and receipt functions'
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
      "project_ref":"MR-REL-001",
      "name":"MR Reliability Project",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Draft reliability requester"
      }],
      "buildings":[{"code":"rel","name":"Reliability Building"}],
      "attachments":[]
    }'::jsonb,
    '91000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the isolated reliability fixture project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'MR-REL-001'),
      'state', 'active',
      'expected_version', 1,
      'reason', 'Ready for reliability tests'
    ),
    '91000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The reliability fixture is activated through the trusted command'
);

set local role postgres;
create temporary table v1_mr_reliability_payloads as
select jsonb_build_object(
  'request_id', '92000000-0000-4000-8000-000000000001',
  'expected_version', 0,
  'project_id', project.id,
  'scope_id', scope.id,
  'title', 'Draft receipt reliability',
  'timing', 'normal',
  'scheduled_date', null,
  'delivery_note', 'Common store',
  'lines', jsonb_build_array(jsonb_build_object(
    'id', '93000000-0000-4000-8000-000000000001',
    'display_order', 1,
    'source_kind', 'custom',
    'source_boq_group_id', null,
    'source_boq_row_id', null,
    'item_description', 'Flexible duct',
    'brand_origin', null,
    'technical_attributes', '{}'::jsonb,
    'requested_qty', '2',
    'unit', 'Meter'
  ))
) as payload
from public.v1_projects project
join public.v1_project_scopes scope
  on scope.project_id = project.id and scope.scope_kind = 'common'
where project.project_ref = 'MR-REL-001';
grant select on table v1_mr_reliability_payloads to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_save_material_request_draft_idempotent(
    (select payload from v1_mr_reliability_payloads),
    '94000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Site Engineer saves one creator-owned draft through the idempotent command'
);

select is(
  (public.v1_save_material_request_draft_idempotent(
    (select payload from v1_mr_reliability_payloads),
    '94000000-0000-4000-8000-000000000001'::uuid
  ) ->> 'record_version')::integer,
  1,
  'A same-key replay returns the original committed record version'
);

set local role postgres;
select is(
  (select record_version from public.v1_material_requests
    where id = '92000000-0000-4000-8000-000000000001'::uuid),
  1,
  'A same-key replay does not apply the draft mutation twice'
);
set local role authenticated;

select is(
  public.v1_get_material_request_draft_save_result(
    (select payload from v1_mr_reliability_payloads),
    '94000000-0000-4000-8000-000000000001'::uuid
  ),
  public.v1_save_material_request_draft_idempotent(
    (select payload from v1_mr_reliability_payloads),
    '94000000-0000-4000-8000-000000000001'::uuid
  ),
  'The authorized receipt read returns the same authoritative acknowledgement'
);

select ok(
  (public.v1_get_material_request_draft_save_result(
    (select payload from v1_mr_reliability_payloads),
    '94000000-0000-4000-8000-000000000001'::uuid
  ) ?& array[
    'request_id', 'record_version', 'operation_id', 'payload_hash', 'committed_at'
  ]),
  'The receipt is a bounded acknowledgement rather than a full request projection'
);

select throws_ok(
  $$select public.v1_save_material_request_draft_idempotent(
    jsonb_set(
      (select payload from v1_mr_reliability_payloads),
      '{title}',
      '"Different payload"'::jsonb
    ),
    '94000000-0000-4000-8000-000000000001'::uuid
  )$$,
  '22023',
  'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'The same logical operation cannot be reused with a different payload'
);

select is(
  public.v1_get_material_request_draft_save_result(
    jsonb_set(
      (select payload from v1_mr_reliability_payloads),
      '{request_id}',
      '"92000000-0000-4000-8000-000000000099"'::jsonb
    ),
    '94000000-0000-4000-8000-000000000099'::uuid
  ),
  null::jsonb,
  'A missing receipt remains unknown and is not reported as a rollback'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_save_material_request_draft_idempotent(
    jsonb_set(
      (select payload from v1_mr_reliability_payloads),
      '{request_id}',
      '"92000000-0000-4000-8000-000000000003"'::jsonb
    ),
    '94000000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501',
  'V1_MATERIAL_REQUEST_DRAFT_SAVE_DENIED',
  'Procurement cannot create a draft through the new wrapper'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_save_material_request_draft_idempotent(
    jsonb_set(
      jsonb_set(
        (select payload from v1_mr_reliability_payloads),
        '{request_id}',
        '"92000000-0000-4000-8000-000000000004"'::jsonb
      ),
      '{lines,0,id}',
      '"93000000-0000-4000-8000-000000000004"'::jsonb
    ),
    '94000000-0000-4000-8000-000000000004'::uuid
  )$$,
  'Project Engineer retains existing draft-create authority through the wrapper'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_save_material_request_draft_idempotent(
    jsonb_set(
      jsonb_set(
        (select payload from v1_mr_reliability_payloads),
        '{request_id}',
        '"92000000-0000-4000-8000-000000000005"'::jsonb
      ),
      '{lines,0,id}',
      '"93000000-0000-4000-8000-000000000005"'::jsonb
    ),
    '94000000-0000-4000-8000-000000000005'::uuid
  )$$,
  'Admin retains audited support authority through the wrapper'
);

set local role postgres;
select is(
  (select count(*) from public.v1_idempotency_keys
   where command_name = 'v1_save_material_request_draft_idempotent'
     and completed_at is not null),
  3::bigint,
  'Each successful logical save has one completed receipt'
);

select * from finish();
rollback;

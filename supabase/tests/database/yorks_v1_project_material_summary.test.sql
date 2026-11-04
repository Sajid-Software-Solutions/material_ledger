begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(22);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_project_material_summary(uuid,date,date,uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_project_material_summary(uuid,date,date,uuid,text)',
    'execute'
  ),
  'Only authenticated actors can execute the project Material Summary'
);

select ok(
  (select prosecdef and 'jit=off' = any(proconfig)
    from pg_proc
    where oid = 'public.v1_project_material_summary(uuid,date,date,uuid,text)'::regprocedure),
  'The summary is a security-definer projection with JIT disabled'
);

-- Project Engineer creates and activates the project so Procurement's
-- running-project read boundary is exercised as well.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"MS-SUM-001",
      "name":"Material summary project",
      "job_contract_reference":"N-MS-001",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Summary reader"
      }],
      "buildings":[{"code":"ms","name":"Summary Building"}],
      "attachments":[]
    }'::jsonb,
    'a5000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the Material Summary test project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'MS-SUM-001'),
      'state', 'active', 'expected_version', 1, 'reason', 'Ready for summary'
    ), 'a5000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The Material Summary test project is active'
);

set local role postgres;
create temporary table v1_ms_targets as
select project.id as project_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'building' limit 1) as building_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'common' limit 1) as common_id
from public.v1_projects project where project.project_ref = 'MS-SUM-001';
grant select on table v1_ms_targets to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  source.instance_id,
  'a5000000-0000-4000-8000-0000000000e6'::uuid,
  source.aud,
  source.role,
  'unassigned.summary.engineer@yorks.local.test',
  source.encrypted_password,
  source.email_confirmed_at,
  jsonb_build_object(
    'provider', 'email',
    'providers', jsonb_build_array('email'),
    'role', 'site_engineer',
    'app_user_id', 'usr-unassigned-summary-engineer',
    'caps', '[]'::jsonb
  ),
  jsonb_build_object(
    'full_name', 'Unassigned Summary Engineer',
    'must_change_password', false
  ),
  source.created_at,
  source.updated_at,
  '', '', '', ''
from auth.users source
where source.id = '10000000-0000-4000-8000-000000000001'::uuid;

-- MR-001 is submitted at 21:30 UTC on Saturday 31 October 2026, which is
-- 01:30 on Sunday 1 November in Asia/Dubai: November, week of Monday 26 Oct.
-- MR-002 is submitted on Monday 2 November: a new week.
-- The draft must never appear.
insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state, record_version,
  created_by_auth_user_id, requester_display_name, requester_project_role,
  current_action_owner_role, current_action_code, submitted_at,
  project_engineer_snapshot
) values (
  'a5100000-0000-4000-8000-000000000001',
  (select project_id from v1_ms_targets), (select building_id from v1_ms_targets),
  'MS-SUM-001-MR001', 'Summary request one', 'normal', 'received', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  'project_engineer', 'material_request_close_review',
  '2026-10-31 21:30:00+00',
  '[{"display_name":"Local Project Engineer"}]'::jsonb
), (
  'a5100000-0000-4000-8000-000000000002',
  (select project_id from v1_ms_targets), (select common_id from v1_ms_targets),
  'MS-SUM-001-MR002', 'Summary request two', 'normal', 'received', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  'project_engineer', 'material_request_close_review',
  '2026-11-02 08:00:00+00',
  '[{"display_name":"Local Project Engineer"}]'::jsonb
);
insert into public.v1_material_requests (
  id, project_id, scope_id, created_by_auth_user_id, requester_display_name,
  requester_project_role, project_engineer_snapshot
) values (
  'a5100000-0000-4000-8000-000000000003',
  (select project_id from v1_ms_targets), (select building_id from v1_ms_targets),
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  '[{"display_name":"Local Project Engineer"}]'::jsonb
);

insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description, brand_origin,
  requested_qty, unit
) values
  ('a5200000-0000-4000-8000-000000000001',
    'a5100000-0000-4000-8000-000000000001', 1, 'custom', 'Aluminium Tape', '3M', 10, 'Roll'),
  ('a5200000-0000-4000-8000-000000000002',
    'a5100000-0000-4000-8000-000000000001', 2, 'custom', 'Safety Gloves', null, 20, 'Pairs'),
  ('a5200000-0000-4000-8000-000000000003',
    'a5100000-0000-4000-8000-000000000002', 1, 'custom', 'aluminium  tape', 'Local', 5, 'roll'),
  ('a5200000-0000-4000-8000-000000000004',
    'a5100000-0000-4000-8000-000000000002', 2, 'custom', 'Aluminium Tap', null, 4, 'Roll'),
  ('a5200000-0000-4000-8000-000000000005',
    'a5100000-0000-4000-8000-000000000003', 1, 'custom', 'Draft only material', null, 9, 'Nos');

insert into public.v1_inventory_items (
  id, item_description, brand_origin, unit, created_by_auth_user_id, item_code
) values (
  'a5300000-0000-4000-8000-000000000001', 'Material summary tape stock', '3M',
  'Mtr', '10000000-0000-4000-8000-000000000003', 'MS-AT-001'
);
insert into public.v1_inventory_balances (inventory_item_id, on_hand_qty)
values ('a5300000-0000-4000-8000-000000000001', 0);
insert into public.v1_procurement_arrangements (
  id, request_id, arrangement_version, status, is_current,
  started_by_auth_user_id, saved_by_auth_user_id, saved_at
) values (
  'a5400000-0000-4000-8000-000000000001',
  'a5100000-0000-4000-8000-000000000001', 1, 'approved', true,
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000003', clock_timestamp()
);
insert into public.v1_procurement_arrangement_lines (
  id, arrangement_id, request_line_id, source_kind, inventory_item_id,
  decision, arranged_qty, warehouse_available_at_save
) values (
  'a5500000-0000-4000-8000-000000000001',
  'a5400000-0000-4000-8000-000000000001',
  'a5200000-0000-4000-8000-000000000001', 'warehouse',
  'a5300000-0000-4000-8000-000000000001', 'full', 10, 10
);
insert into public.v1_material_request_line_approvals (
  request_line_id, arrangement_line_id, arrangement_id, approved_qty,
  approved_by_auth_user_id
) values (
  'a5200000-0000-4000-8000-000000000001',
  'a5500000-0000-4000-8000-000000000001',
  'a5400000-0000-4000-8000-000000000001', 10,
  '10000000-0000-4000-8000-000000000001'
);
insert into public.v1_material_dispatches (
  id, request_id, project_id, dispatch_number, dispatch_date, delivery_reference,
  state, dispatched_by_auth_user_id, dispatched_by_role
) values (
  'a5600000-0000-4000-8000-000000000001',
  'a5100000-0000-4000-8000-000000000001',
  (select project_id from v1_ms_targets), 'MS-SUM-001-DSP001', current_date,
  'DN-MS-001', 'receipt_pending', '10000000-0000-4000-8000-000000000003',
  'procurement'
);
insert into public.v1_material_dispatch_lines (
  id, dispatch_id, request_line_id, arrangement_line_id, source_kind,
  inventory_item_id, external_supplier, item_description, brand_origin, unit,
  approved_qty_snapshot, dispatched_qty
) values (
  'a5700000-0000-4000-8000-000000000001',
  'a5600000-0000-4000-8000-000000000001',
  'a5200000-0000-4000-8000-000000000001',
  'a5500000-0000-4000-8000-000000000001', 'warehouse',
  'a5300000-0000-4000-8000-000000000001', null,
  'Material summary tape stock', '3M', 'Mtr', 10, 6
);

-- Assigned Site Engineer: positive read and aggregation proofs.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
create temporary table v1_ms_summary as
select public.v1_project_material_summary(
  (select project_id from v1_ms_targets)
) as payload;

select is(
  (select jsonb_array_length(payload -> 'items') from v1_ms_summary),
  3,
  'Spelling variants stay separate while case and spacing variants group'
);
select is(
  (select item ->> 'requested_qty' from v1_ms_summary,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'aluminium tape' || chr(31) || 'roll'),
  '15',
  'Requested quantity sums every submitted request line of the item'
);
select is(
  (select item ->> 'sent_qty' from v1_ms_summary,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'aluminium tape' || chr(31) || 'roll'),
  '6',
  'Sent quantity comes from committed dispatch lines'
);
select is(
  (select item -> 'item_codes' from v1_ms_summary,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'aluminium tape' || chr(31) || 'roll'),
  '["MS-AT-001"]'::jsonb,
  'Warehouse item codes are carried for dispatched items'
);
select is(
  (select jsonb_array_length(item -> 'request_refs') from v1_ms_summary,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'aluminium tape' || chr(31) || 'roll'),
  2,
  'Each item lists the Material Requests that carried it'
);
select ok(
  not exists (
    select 1 from v1_ms_summary, jsonb_array_elements(payload -> 'items') item
    where item ->> 'item_description' ilike 'draft only%'
  ),
  'Draft requests never enter the Material Summary'
);
select ok(
  exists (
    select 1 from v1_ms_summary, jsonb_array_elements(payload -> 'weeks') week
    where week ->> 0 = '2026-10-26'
  ) and exists (
    select 1 from v1_ms_summary, jsonb_array_elements(payload -> 'weeks') week
    where week ->> 0 = '2026-11-02'
  ) and not exists (
    select 1 from v1_ms_summary, jsonb_array_elements(payload -> 'months') month
    where month ->> 0 = '2026-10-01'
  ),
  'Dates use Asia/Dubai and weeks run Monday to Sunday'
);
select ok(
  (select payload::text from v1_ms_summary)
    !~* '"([a-z]+_)*(cost|rate|price|supplier|valuation)(_[a-z]+)*"\s*:',
  'The response contains no commercial or supplier field'
);
select is(
  jsonb_array_length(public.v1_project_material_summary(
    (select project_id from v1_ms_targets), p_search => 'aluminum tape'
  ) -> 'items'),
  2,
  'Search returns close spellings of the same material next to each other'
);
select is(
  jsonb_array_length(public.v1_project_material_summary(
    (select project_id from v1_ms_targets),
    p_scope_id => (select common_id from v1_ms_targets)
  ) -> 'items'),
  2,
  'The building filter limits the summary to that scope'
);
select is(
  jsonb_array_length(public.v1_project_material_summary(
    (select project_id from v1_ms_targets),
    p_from => '2026-11-02'::date, p_to => '2026-11-08'::date
  ) -> 'items'),
  2,
  'The date filter uses the request date'
);
select throws_ok(
  $$select public.v1_project_material_summary(
    (select project_id from v1_ms_targets),
    p_from => '2026-12-01'::date, p_to => '2026-11-01'::date
  )$$,
  '22023', 'V1_PROJECT_MATERIAL_SUMMARY_INVALID',
  'An inverted date range is rejected'
);

-- Assigned Project Engineer, Procurement (active project) and Admin can read.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_project_material_summary((select project_id from v1_ms_targets))$$,
  'The assigned Project Engineer reads the Material Summary'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_project_material_summary((select project_id from v1_ms_targets))$$,
  'Procurement reads the Material Summary of a running project'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_project_material_summary((select project_id from v1_ms_targets))$$,
  'Admin reads the Material Summary'
);

-- Negative: unassigned engineer, a scope from another project and no actor.
select set_config(
  'request.jwt.claims',
  '{"sub":"a5000000-0000-4000-8000-0000000000e6","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-unassigned-summary-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_project_material_summary((select project_id from v1_ms_targets))$$,
  '42501', 'V1_PROJECT_MATERIAL_SUMMARY_DENIED',
  'An unassigned engineer cannot read another project Material Summary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select throws_ok(
  $$select public.v1_project_material_summary(
    (select project_id from v1_ms_targets),
    p_scope_id => 'a5900000-0000-4000-8000-000000000001'::uuid
  )$$,
  '22023', 'V1_PROJECT_MATERIAL_SUMMARY_INVALID',
  'A building that is not part of the project is rejected'
);

select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$select public.v1_project_material_summary((select project_id from v1_ms_targets))$$,
  '42501', 'V1_PROJECT_MATERIAL_SUMMARY_DENIED',
  'A request without an authenticated actor is denied'
);

select * from finish();
rollback;

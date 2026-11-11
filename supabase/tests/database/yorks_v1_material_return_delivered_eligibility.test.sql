begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(45);

-- Surface and grants -------------------------------------------------------

select ok(
  has_function_privilege('authenticated',
    'public.v1_material_return_item_candidates(uuid,uuid,text,uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_material_return_item_candidates(uuid,uuid,text,uuid)', 'execute'),
  'Only authenticated actors can execute the grouped return candidates'
);
select ok(
  not has_function_privilege('authenticated',
    'public.v1_material_return_active_quantity(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_material_return_dispatch_basis(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_receipt_review_line_return_guard()', 'execute'),
  'Eligibility helpers and the receipt guard are not directly callable'
);
select ok(
  (select prosecdef and 'jit=off' = any(proconfig) from pg_proc
    where oid = 'public.v1_material_return_item_candidates(uuid,uuid,text,uuid)'::regprocedure),
  'Candidates are a security-definer projection with JIT disabled'
);

-- Project ------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true);
select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"RT-ELG-001",
      "name":"Return eligibility project",
      "job_contract_reference":"N-RT-001",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Return drafter"
      }],
      "buildings":[{"code":"rt","name":"Return Building"}],
      "attachments":[]
    }'::jsonb,
    'b1000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the return eligibility project'
);
select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'RT-ELG-001'),
      'state', 'active', 'expected_version', 1, 'reason', 'Ready for returns'
    ), 'b1000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The return eligibility project is active'
);

set local role postgres;
create temporary table v1_rt as
select project.id as project_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'building' limit 1) as building_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'common' limit 1) as common_id
from public.v1_projects project where project.project_ref = 'RT-ELG-001';
grant select on table v1_rt to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select source.instance_id, 'b1000000-0000-4000-8000-0000000000e6'::uuid,
  source.aud, source.role, 'unassigned.return.engineer@yorks.local.test',
  source.encrypted_password, source.email_confirmed_at,
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'),
    'role', 'site_engineer', 'app_user_id', 'usr-unassigned-return-engineer',
    'caps', '[]'::jsonb),
  jsonb_build_object('full_name', 'Unassigned Return Engineer',
    'must_change_password', false),
  source.created_at, source.updated_at, '', '', '', ''
from auth.users source
where source.id = '10000000-0000-4000-8000-000000000001'::uuid;

-- Deliveries ---------------------------------------------------------------
-- MR-001 (building): Copper Pipe 15mm (warehouse, coded) and Safety Gloves
-- (external supplier). Delivered first and receipt-confirmed: pipe 8 good of 10.
-- MR-002 (common): Copper Pipe 15mm and Copper Pipe 22mm, delivered later and
-- not yet confirmed by the site.
insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state, record_version,
  created_by_auth_user_id, requester_display_name, requester_project_role,
  current_action_owner_role, current_action_code, submitted_at,
  project_engineer_snapshot
) values (
  'b1100000-0000-4000-8000-000000000001',
  (select project_id from v1_rt), (select building_id from v1_rt),
  'RT-ELG-001-MR001', 'Return request one', 'normal', 'received', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  'project_engineer', 'material_request_close_review', '2026-10-20 08:00:00+00',
  '[{"display_name":"Local Project Engineer"}]'::jsonb
), (
  'b1100000-0000-4000-8000-000000000002',
  (select project_id from v1_rt), (select common_id from v1_rt),
  'RT-ELG-001-MR002', 'Return request two', 'normal', 'received', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  'project_engineer', 'material_request_close_review', '2026-10-28 08:00:00+00',
  '[{"display_name":"Local Project Engineer"}]'::jsonb
);
insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description, brand_origin,
  requested_qty, unit, technical_attributes
) values
  ('b1200000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001',
    1, 'custom', 'Copper Pipe', 'Mueller', 10, 'Mtr',
    '{"size":"15mm","model":"Type L"}'::jsonb),
  ('b1200000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000001',
    2, 'custom', 'Safety Gloves', null, 20, 'Pairs', '{}'::jsonb),
  ('b1200000-0000-4000-8000-000000000003', 'b1100000-0000-4000-8000-000000000002',
    1, 'custom', 'copper  pipe', 'Local', 5, 'mtr',
    '{"size":"15mm","equipment_tag":"CH-01"}'::jsonb),
  ('b1200000-0000-4000-8000-000000000004', 'b1100000-0000-4000-8000-000000000002',
    2, 'custom', 'Copper Pipe', null, 3, 'Mtr', '{"size":"22mm"}'::jsonb);

insert into public.v1_inventory_items (
  id, item_description, brand_origin, unit, created_by_auth_user_id, item_code
) values (
  'b1300000-0000-4000-8000-000000000001', 'Copper Pipe 15mm stock', 'Mueller',
  'Mtr', '10000000-0000-4000-8000-000000000003', 'CP-015'
);
insert into public.v1_inventory_balances (inventory_item_id, on_hand_qty)
values ('b1300000-0000-4000-8000-000000000001', 0);
insert into public.v1_procurement_arrangements (
  id, request_id, arrangement_version, status, is_current,
  started_by_auth_user_id, saved_by_auth_user_id, saved_at
) values
  ('b1400000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001',
    1, 'approved', true, '10000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000003', clock_timestamp()),
  ('b1400000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000002',
    1, 'approved', true, '10000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000003', clock_timestamp());
insert into public.v1_procurement_arrangement_lines (
  id, arrangement_id, request_line_id, source_kind, inventory_item_id,
  external_supplier, decision, arranged_qty, warehouse_available_at_save
) values
  ('b1500000-0000-4000-8000-000000000001', 'b1400000-0000-4000-8000-000000000001',
    'b1200000-0000-4000-8000-000000000001', 'warehouse',
    'b1300000-0000-4000-8000-000000000001', null, 'full', 10, 10),
  ('b1500000-0000-4000-8000-000000000002', 'b1400000-0000-4000-8000-000000000001',
    'b1200000-0000-4000-8000-000000000002', 'external_supplier', null,
    'Gloves Trading LLC', 'full', 20, null),
  ('b1500000-0000-4000-8000-000000000003', 'b1400000-0000-4000-8000-000000000002',
    'b1200000-0000-4000-8000-000000000003', 'external_supplier', null,
    'Pipe Trading LLC', 'full', 5, null),
  ('b1500000-0000-4000-8000-000000000004', 'b1400000-0000-4000-8000-000000000002',
    'b1200000-0000-4000-8000-000000000004', 'external_supplier', null,
    'Pipe Trading LLC', 'full', 3, null);
insert into public.v1_material_dispatches (
  id, request_id, project_id, dispatch_number, dispatch_date, delivery_reference,
  state, dispatched_by_auth_user_id, dispatched_by_role, dispatched_at
) values
  ('b1600000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001',
    (select project_id from v1_rt), 'RT-ELG-001-DSP001', '2026-10-21', 'DN-RT-001',
    'receipt_pending', '10000000-0000-4000-8000-000000000003', 'procurement',
    '2026-10-21 08:00:00+00'),
  ('b1600000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000002',
    (select project_id from v1_rt), 'RT-ELG-001-DSP002', '2026-10-29', 'DN-RT-002',
    'receipt_pending', '10000000-0000-4000-8000-000000000003', 'procurement',
    '2026-10-29 08:00:00+00');
insert into public.v1_material_dispatch_lines (
  id, dispatch_id, request_line_id, arrangement_line_id, source_kind,
  inventory_item_id, external_supplier, item_description, brand_origin, unit,
  approved_qty_snapshot, dispatched_qty
) values
  ('b1700000-0000-4000-8000-000000000001', 'b1600000-0000-4000-8000-000000000001',
    'b1200000-0000-4000-8000-000000000001', 'b1500000-0000-4000-8000-000000000001',
    'warehouse', 'b1300000-0000-4000-8000-000000000001', null,
    'Copper Pipe', 'Mueller', 'Mtr', 10, 10),
  ('b1700000-0000-4000-8000-000000000002', 'b1600000-0000-4000-8000-000000000001',
    'b1200000-0000-4000-8000-000000000002', 'b1500000-0000-4000-8000-000000000002',
    'external_supplier', null, 'Gloves Trading LLC',
    'Safety Gloves', null, 'Pairs', 20, 20),
  ('b1700000-0000-4000-8000-000000000003', 'b1600000-0000-4000-8000-000000000002',
    'b1200000-0000-4000-8000-000000000003', 'b1500000-0000-4000-8000-000000000003',
    'external_supplier', null, 'Pipe Trading LLC',
    'copper  pipe', 'Local', 'mtr', 5, 5),
  ('b1700000-0000-4000-8000-000000000004', 'b1600000-0000-4000-8000-000000000002',
    'b1200000-0000-4000-8000-000000000004', 'b1500000-0000-4000-8000-000000000004',
    'external_supplier', null, 'Pipe Trading LLC',
    'Copper Pipe', null, 'Mtr', 3, 3);
insert into public.v1_receipt_reviews (
  id, dispatch_id, request_id, reviewed_by_auth_user_id, reviewed_by_role, reviewed_at
) values (
  'b1800000-0000-4000-8000-000000000001', 'b1600000-0000-4000-8000-000000000001',
  'b1100000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002',
  'site_engineer', '2026-10-22 08:00:00+00'
);
insert into public.v1_receipt_review_lines (
  id, receipt_review_id, dispatch_line_id, outcome, dispatched_qty_snapshot,
  good_qty, missing_qty, damaged_qty, exception_qty, note
) values
  ('b1900000-0000-4000-8000-000000000001', 'b1800000-0000-4000-8000-000000000001',
    'b1700000-0000-4000-8000-000000000001', 'missing', 10, 8, 2, 0, 2,
    'Two metres short'),
  ('b1900000-0000-4000-8000-000000000002', 'b1800000-0000-4000-8000-000000000001',
    'b1700000-0000-4000-8000-000000000002', 'received', 20, 20, 0, 0, 0, null);

-- Grouped candidates ----------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true);
create temporary table v1_rt_c1 as
select public.v1_material_return_item_candidates((select project_id from v1_rt)) as payload;

select is(
  (select jsonb_array_length(payload -> 'items') from v1_rt_c1), 3,
  'Delivered material groups per description, size and unit across all buildings'
);
select is(
  (select item ->> 'returnable_qty' from v1_rt_c1, jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '13',
  'Returnable = confirmed good quantity plus unconfirmed dispatched quantity'
);
select is(
  (select item ->> 'unconfirmed_returnable_qty' from v1_rt_c1,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '5',
  'Dispatched-but-unconfirmed quantity is reported separately'
);
select is(
  (select item -> 'sources' -> 0 ->> 'dispatch_line_id' from v1_rt_c1,
    jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  'b1700000-0000-4000-8000-000000000003',
  'Sources list the newest delivery first'
);
select is(
  (select item -> 'sources' -> 0 ->> 'basis_kind' || '/' ||
      (item -> 'sources' -> 1 ->> 'basis_kind')
    from v1_rt_c1, jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  'dispatched_unconfirmed/received',
  'Each source states which basis applies'
);
select is(
  (select (item -> 'item_codes')::text || (item ->> 'size') || (item -> 'models')::text
      || (item -> 'equipment_tags')::text
    from v1_rt_c1, jsonb_array_elements(payload -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '["CP-015"]15mm["Type L"]["CH-01"]',
  'Item code, size, model and equipment tag come from the delivery and request line'
);
select ok(
  (select payload::text !~* '"(unit_cost|total_cost|rate|price|external_supplier|supplier_name)"\s*:'
    from v1_rt_c1),
  'Candidates expose no commercial or supplier field'
);
select is(
  (select jsonb_array_length(public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, '22mm') -> 'items')),
  1,
  'Search matches the size'
);
select is(
  (select item ->> 'returnable_qty' from jsonb_array_elements(
    public.v1_material_return_item_candidates(
      (select project_id from v1_rt), null, 'MR001') -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '8',
  'Searching a request number narrows the sources to that request'
);
select is(
  (select jsonb_array_length(public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, 'coper pipe') -> 'items')),
  2,
  'A close spelling finds the material through trigram similarity'
);
select is(
  (select jsonb_array_length(public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, '100%_') -> 'items')),
  0,
  'LIKE wildcards in a search are literal'
);
select is(
  (select jsonb_array_length(public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, null, (select building_id from v1_rt)) -> 'items')),
  2,
  'The optional building filter limits candidates to that scope'
);
select throws_ok(
  $$select public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, null, gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_CANDIDATES_INVALID',
  'A foreign scope is rejected'
);
select throws_ok(
  $$select public.v1_material_return_item_candidates(
    (select project_id from v1_rt), null, repeat('x', 121))$$,
  '22023', 'V1_MATERIAL_RETURN_CANDIDATES_INVALID',
  'An over-long search is rejected'
);

-- Draft with an unconfirmed and a confirmed source, plus a sized custom line.
create temporary table v1_rt_draft as
select public.v1_save_project_material_return_draft(jsonb_build_object(
  'project_id', (select project_id from v1_rt),
  'scope_id', (select building_id from v1_rt),
  'expected_version', 0,
  'purpose', 'Surplus after first fix',
  'lines', jsonb_build_array(
    jsonb_build_object('origin_kind', 'delivered',
      'dispatch_line_id', 'b1700000-0000-4000-8000-000000000003', 'return_qty', 4,
      'size', 'ignored for delivered lines'),
    jsonb_build_object('origin_kind', 'delivered',
      'receipt_review_line_id', 'b1900000-0000-4000-8000-000000000001', 'return_qty', 8),
    jsonb_build_object('origin_kind', 'custom', 'item_description', 'Pipe clamp',
      'unit', 'Nos', 'size', '15mm', 'model', 'C-15', 'return_qty', 12)
  )
), 'b1000000-0000-4000-8000-000000000010'::uuid) as payload;

select is(
  (select jsonb_array_length(payload -> 'lines') from v1_rt_draft), 3,
  'A draft accepts dispatch-line, legacy receipt-line and custom lines'
);
select is(
  (select line ->> 'basis_kind' || '|' || coalesce(line ->> 'receipt_review_line_id', 'none')
      || '|' || (line ->> 'size') || '|' || (line ->> 'good_quantity_snapshot')
    from v1_rt_draft, jsonb_array_elements(payload -> 'lines') line
    where line ->> 'dispatch_line_id' = 'b1700000-0000-4000-8000-000000000003'),
  'dispatched_unconfirmed|none|15mm|5.0000',
  'An unconfirmed line records its basis and copies the request size, not the client value'
);
select is(
  (select line ->> 'basis_kind' || '|' || (line ->> 'dispatch_line_id') || '|'
      || (line ->> 'item_code')
    from v1_rt_draft, jsonb_array_elements(payload -> 'lines') line
    where line ->> 'receipt_review_line_id' = 'b1900000-0000-4000-8000-000000000001'),
  'received|b1700000-0000-4000-8000-000000000001|CP-015',
  'A legacy receipt-line payload resolves to its dispatch line'
);
select is(
  (select (line ->> 'size') || '/' || (line ->> 'model') from v1_rt_draft,
    jsonb_array_elements(payload -> 'lines') line where line ->> 'origin_kind' = 'custom'),
  '15mm/C-15',
  'Custom lines keep size and model like Material Request lines'
);
select is(
  (select item ->> 'returnable_qty' from jsonb_array_elements(
    public.v1_material_return_item_candidates((select project_id from v1_rt)) -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '13',
  'A draft does not hold quantity'
);
select throws_ok(
  $$select public.v1_save_project_material_return_draft(jsonb_build_object(
    'project_id', (select project_id from v1_rt), 'scope_id', (select building_id from v1_rt),
    'expected_version', 0, 'purpose', 'Too much',
    'lines', jsonb_build_array(jsonb_build_object('origin_kind', 'delivered',
      'dispatch_line_id', 'b1700000-0000-4000-8000-000000000003', 'return_qty', 6))
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED',
  'A line above the dispatched quantity is rejected'
);
select throws_ok(
  $$select public.v1_save_project_material_return_draft(jsonb_build_object(
    'project_id', (select project_id from v1_rt), 'scope_id', (select building_id from v1_rt),
    'expected_version', 0, 'purpose', 'Twice',
    'lines', jsonb_build_array(
      jsonb_build_object('origin_kind', 'delivered',
        'dispatch_line_id', 'b1700000-0000-4000-8000-000000000001', 'return_qty', 1),
      jsonb_build_object('origin_kind', 'delivered',
        'receipt_review_line_id', 'b1900000-0000-4000-8000-000000000001', 'return_qty', 1))
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_LINE_DUPLICATE',
  'The same delivery cannot appear twice in one return'
);
select throws_ok(
  $$select public.v1_save_project_material_return_draft(jsonb_build_object(
    'project_id', (select project_id from v1_rt), 'scope_id', (select building_id from v1_rt),
    'expected_version', 0, 'purpose', 'Mismatch',
    'lines', jsonb_build_array(jsonb_build_object('origin_kind', 'delivered',
      'dispatch_line_id', 'b1700000-0000-4000-8000-000000000002',
      'receipt_review_line_id', 'b1900000-0000-4000-8000-000000000001', 'return_qty', 1))
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_SOURCE_INVALID',
  'A receipt line that belongs to another delivery is rejected'
);
select throws_ok(
  $$select public.v1_save_project_material_return_draft(jsonb_build_object(
    'project_id', (select project_id from v1_rt), 'scope_id', (select building_id from v1_rt),
    'expected_version', 0, 'purpose', 'Big size',
    'lines', jsonb_build_array(jsonb_build_object('origin_kind', 'custom',
      'item_description', 'Clamp', 'unit', 'Nos', 'size', repeat('x', 121), 'return_qty', 1))
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_CUSTOM_LINE_INVALID',
  'Custom technical fields are bounded'
);

-- Submit holds the quantity ----------------------------------------------------

select lives_ok(
  $$select public.v1_submit_project_material_return(jsonb_build_object(
    'return_id', (select payload ->> 'id' from v1_rt_draft),
    'expected_version', (select (payload ->> 'record_version')::int from v1_rt_draft)
  ), 'b1000000-0000-4000-8000-000000000011'::uuid)$$,
  'The drafter submits the return'
);
select is(
  (select line ->> 'eligible_quantity_at_submit' from jsonb_array_elements(
    public.v1_material_return_detail_projection(
      (select (payload ->> 'id')::uuid from v1_rt_draft)) -> 'lines') line
    where line ->> 'dispatch_line_id' = 'b1700000-0000-4000-8000-000000000003'),
  '5.0000',
  'Submission records the eligible quantity of an unconfirmed delivery'
);
select is(
  (select item ->> 'returnable_qty' from jsonb_array_elements(
    public.v1_material_return_item_candidates((select project_id from v1_rt)) -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  '1',
  'Submitted returns hold their quantity'
);
select throws_ok(
  $$select public.v1_save_project_material_return_draft(jsonb_build_object(
    'project_id', (select project_id from v1_rt), 'scope_id', (select common_id from v1_rt),
    'expected_version', 0, 'purpose', 'Second return',
    'lines', jsonb_build_array(jsonb_build_object('origin_kind', 'delivered',
      'dispatch_line_id', 'b1700000-0000-4000-8000-000000000003', 'return_qty', 2))
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED',
  'A second return cannot take quantity already held by the first'
);
create temporary table v1_rt_second as
select public.v1_save_project_material_return_draft(jsonb_build_object(
  'project_id', (select project_id from v1_rt), 'scope_id', (select common_id from v1_rt),
  'expected_version', 0, 'purpose', 'Second return',
  'lines', jsonb_build_array(jsonb_build_object('origin_kind', 'delivered',
    'dispatch_line_id', 'b1700000-0000-4000-8000-000000000003', 'return_qty', 1))
), 'b1000000-0000-4000-8000-000000000012'::uuid) as payload;
select is(
  (select payload ->> 'state' from v1_rt_second), 'draft',
  'The remaining quantity can be drafted from another building'
);
select is(
  (select (entry ->> 'committed_return_qty') from jsonb_array_elements(
    public.v1_material_return_creation_workspace((select project_id from v1_rt))
      -> 'candidates') entry
    where entry ->> 'receipt_review_line_id' = 'b1900000-0000-4000-8000-000000000001'),
  '8.0000',
  'The released creation workspace counts committed quantity per delivery'
);

-- Receipt guard ---------------------------------------------------------------

set local role postgres;
insert into public.v1_receipt_reviews (
  id, dispatch_id, request_id, reviewed_by_auth_user_id, reviewed_by_role, reviewed_at
) values (
  'b1800000-0000-4000-8000-000000000002', 'b1600000-0000-4000-8000-000000000002',
  'b1100000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002',
  'site_engineer', '2026-10-30 08:00:00+00'
);
select throws_ok(
  $$insert into public.v1_receipt_review_lines (
    receipt_review_id, dispatch_line_id, outcome, dispatched_qty_snapshot,
    good_qty, missing_qty, damaged_qty, exception_qty, note
  ) values ('b1800000-0000-4000-8000-000000000002',
    'b1700000-0000-4000-8000-000000000003', 'missing', 5, 3, 2, 0, 2, 'Short')$$,
  '22023', 'V1_RECEIPT_BELOW_ACTIVE_RETURNS',
  'A receipt cannot record less good material than is on active returns'
);
select lives_ok(
  $$insert into public.v1_receipt_review_lines (
    id, receipt_review_id, dispatch_line_id, outcome, dispatched_qty_snapshot,
    good_qty, missing_qty, damaged_qty, exception_qty, note
  ) values ('b1900000-0000-4000-8000-000000000003',
    'b1800000-0000-4000-8000-000000000002',
    'b1700000-0000-4000-8000-000000000003', 'missing', 5, 4, 1, 0, 1, 'Short')$$,
  'A receipt that covers the active returns is accepted'
);
select throws_ok(
  $$update public.v1_receipt_review_lines set good_qty = 3, missing_qty = 2,
      exception_qty = 2
    where id = 'b1900000-0000-4000-8000-000000000003'$$,
  '22023', 'V1_RECEIPT_BELOW_ACTIVE_RETURNS',
  'A later correction cannot drop below active returns either'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true);
select is(
  (select item ->> 'returnable_qty' from jsonb_array_elements(
    public.v1_material_return_item_candidates((select project_id from v1_rt)) -> 'items') item
    where item ->> 'key' = 'copper pipe' || chr(31) || '15mm' || chr(31) || 'mtr'),
  null,
  'After the receipt the basis is the good quantity and nothing is left to return'
);
select throws_ok(
  $$select public.v1_submit_project_material_return(jsonb_build_object(
    'return_id', (select payload ->> 'id' from v1_rt_second),
    'expected_version', (select (payload ->> 'record_version')::int from v1_rt_second)
  ), gen_random_uuid())$$,
  '22023', 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED',
  'Submit re-checks eligibility against the confirmed receipt'
);

-- Legacy writers -----------------------------------------------------------------

set local role postgres;
insert into public.v1_material_return_lines (
  id, material_return_id, receipt_review_line_id, dispatch_line_id, request_line_id,
  origin_kind, source_request_id, source_dispatch_id, source_kind,
  item_description, brand_origin, unit, good_quantity_snapshot, return_quantity,
  display_order
) values (
  'b1a00000-0000-4000-8000-000000000001',
  (select (payload ->> 'id')::uuid from v1_rt_second),
  'b1900000-0000-4000-8000-000000000002', 'b1700000-0000-4000-8000-000000000002',
  'b1200000-0000-4000-8000-000000000002', 'delivered',
  'b1100000-0000-4000-8000-000000000001', 'b1600000-0000-4000-8000-000000000001',
  'external_supplier', 'Safety Gloves', null, 'Pairs', 20, 1, 9
);
select is(
  (select basis_kind from public.v1_material_return_lines
    where id = 'b1a00000-0000-4000-8000-000000000001'),
  'received',
  'Legacy receipt-line inserts receive the received basis automatically'
);

-- Access ----------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-0000000000e6","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-unassigned-return-engineer"}}',
  true);
select throws_ok(
  $$select public.v1_material_return_item_candidates((select project_id from v1_rt))$$,
  '42501', 'V1_MATERIAL_RETURN_CREATE_DENIED',
  'An unassigned engineer cannot list return candidates'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true);
select throws_ok(
  $$select public.v1_material_return_item_candidates((select project_id from v1_rt))$$,
  '42501', 'V1_MATERIAL_RETURN_CREATE_DENIED',
  'Procurement does not draft site returns'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true);
select throws_ok(
  $$select public.v1_material_return_item_candidates(
    (select project_id from v1_rt), (select (payload ->> 'id')::uuid from v1_rt_second))$$,
  '42501', 'V1_MATERIAL_RETURN_DRAFT_NOT_EDITABLE',
  'Another engineer cannot open someone else''s draft through candidates'
);
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true);
select ok(
  (select jsonb_typeof(public.v1_material_return_item_candidates(
    (select project_id from v1_rt), (select (payload ->> 'id')::uuid from v1_rt_second))
    -> 'items') = 'array'),
  'Admin can list candidates for any editable draft'
);
select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$select public.v1_material_return_item_candidates((select project_id from v1_rt))$$,
  '42501', 'V1_MATERIAL_RETURN_CREATE_DENIED',
  'A request without an authenticated actor is denied'
);

select * from finish();
rollback;

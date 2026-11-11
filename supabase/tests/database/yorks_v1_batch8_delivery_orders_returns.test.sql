begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(79);

select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.v1_delivery_orders'::regclass)
  and (select relrowsecurity from pg_class
    where oid = 'public.v1_delivery_order_revisions'::regclass)
  and (select relrowsecurity from pg_class
    where oid = 'public.v1_material_returns'::regclass)
  and (select relrowsecurity from pg_class
    where oid = 'public.v1_material_return_lines'::regclass),
  'Batch 8 delivery-order and material-return relations enable RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.v1_delivery_orders', 'insert')
  and not has_table_privilege('authenticated', 'public.v1_material_returns', 'update')
  and has_function_privilege(
    'authenticated', 'public.v1_generate_delivery_order(jsonb,uuid)', 'execute'
  ) and has_function_privilege(
    'authenticated', 'public.v1_confirm_material_return(jsonb,uuid)', 'execute'
  ),
  'Batch 8 writes are available only through trusted RPCs'
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
      "project_ref":"B8-RET-001",
      "name":"Delivery and return project",
      "job_contract_reference":"N-19957.2",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Return preparer"
      }],
      "buildings":[{"code":"b8","name":"Returns Building"}],
      "attachments":[]
    }'::jsonb,
    '80000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the Batch 8 test project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects where project_ref = 'B8-RET-001'),
      'state', 'active', 'expected_version', 1, 'reason', 'Ready for logistics'
    ), '80000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The test project is active before its committed logistics facts are prepared'
);

set local role postgres;
create temporary table v1_b8_targets as
select project.id as project_id,
  (select id from public.v1_project_scopes
    where project_id = project.id and scope_kind = 'building' limit 1) as scope_id
from public.v1_projects project where project.project_ref = 'B8-RET-001';
grant select on table v1_b8_targets to authenticated;

-- Use real active Engineer identities for the cross-membership-label and
-- unassigned permission proofs. Reusing the seeded Admin identity with a
-- spoofed Engineer JWT would be rejected by v1_current_actor_is_active() and
-- would not exercise project membership authorization.
with personas(auth_user_id, email, display_name, app_role, app_user_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000005'::uuid,
      'supporting.project.engineer@yorks.local.test',
      'Supporting Project Engineer',
      'project_engineer',
      'usr-supporting-project-engineer'
    ),
    (
      '10000000-0000-4000-8000-000000000006'::uuid,
      'unassigned.site.engineer@yorks.local.test',
      'Unassigned Site Engineer',
      'site_engineer',
      'usr-unassigned-site-engineer'
    ),
    (
      '10000000-0000-4000-8000-000000000007'::uuid,
      'noor@yorks.ae',
      'Noor zaman',
      'senior_mechanical_engineer',
      'usr-senior-mechanical-engineer'
    ),
    (
      '10000000-0000-4000-8000-000000000008'::uuid,
      'ali@yorks.ae',
      'Ali Hadba',
      'project_manager',
      'usr-project-manager'
    )
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  source.instance_id,
  persona.auth_user_id,
  source.aud,
  source.role,
  persona.email,
  source.encrypted_password,
  source.email_confirmed_at,
  jsonb_build_object(
    'provider', 'email',
    'providers', jsonb_build_array('email'),
    'role', persona.app_role,
    'app_user_id', persona.app_user_id,
    'caps', '[]'::jsonb
  ),
  jsonb_build_object(
    'full_name', persona.display_name,
    'must_change_password', false
  ),
  source.created_at,
  source.updated_at,
  '',
  '',
  '',
  ''
from personas persona
cross join lateral (
  select seed_user.*
  from auth.users seed_user
  where seed_user.id = '10000000-0000-4000-8000-000000000001'::uuid
) source;

-- This is committed test fixture data from the already-tested dispatch and
-- receipt commands. The first dispatch is reviewed; the second remains at the
-- dispatch stage so the controlled-document gate is exercised before receipt.
insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state, record_version,
  created_by_auth_user_id, requester_display_name, requester_project_role,
  current_action_owner_role, current_action_code, submitted_at,
  project_engineer_snapshot
) values (
  '81000000-0000-4000-8000-000000000001',
  (select project_id from v1_b8_targets), (select scope_id from v1_b8_targets),
  'B8-RET-001-MR001', 'Receipt reviewed materials', 'normal', 'received', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer', 'site_engineer',
  'project_engineer', 'material_request_close_review', clock_timestamp(),
  '[{"display_name":"Local Project Engineer"}]'::jsonb
);
insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description, brand_origin,
  requested_qty, unit
) values
  ('81100000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001', 1, 'custom', 'Copper pipe', 'UAE', 5, 'Mtr'),
  ('81100000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001', 2, 'custom', 'Refrigerant valve', 'EU', 1, 'Nos');
insert into public.v1_inventory_items (
  id, item_description, brand_origin, unit, created_by_auth_user_id
) values (
  '81200000-0000-4000-8000-000000000001', 'Copper pipe', 'UAE', 'Mtr',
  '10000000-0000-4000-8000-000000000003'
);
insert into public.v1_inventory_balances (inventory_item_id, on_hand_qty)
values ('81200000-0000-4000-8000-000000000001', 0);
insert into public.v1_procurement_arrangements (
  id, request_id, arrangement_version, status, is_current,
  started_by_auth_user_id, saved_by_auth_user_id, saved_at
) values (
  '81300000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001', 1, 'approved', true,
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000003', clock_timestamp()
);
insert into public.v1_procurement_arrangement_lines (
  id, arrangement_id, request_line_id, source_kind, inventory_item_id,
  decision, arranged_qty, warehouse_available_at_save
) values (
  '81400000-0000-4000-8000-000000000001',
  '81300000-0000-4000-8000-000000000001',
  '81100000-0000-4000-8000-000000000001', 'warehouse',
  '81200000-0000-4000-8000-000000000001', 'full', 5, 5
), (
  '81400000-0000-4000-8000-000000000002',
  '81300000-0000-4000-8000-000000000001',
  '81100000-0000-4000-8000-000000000002', 'external_supplier',
  null, 'full', 1, null
);
insert into public.v1_material_request_line_approvals (
  request_line_id, arrangement_line_id, arrangement_id, approved_qty,
  approved_by_auth_user_id
) values (
  '81100000-0000-4000-8000-000000000001',
  '81400000-0000-4000-8000-000000000001',
  '81300000-0000-4000-8000-000000000001', 5,
  '10000000-0000-4000-8000-000000000001'
), (
  '81100000-0000-4000-8000-000000000002',
  '81400000-0000-4000-8000-000000000002',
  '81300000-0000-4000-8000-000000000001', 1,
  '10000000-0000-4000-8000-000000000001'
);
insert into public.v1_material_dispatches (
  id, request_id, project_id, dispatch_number, dispatch_date, delivery_reference, state,
  dispatched_by_auth_user_id, dispatched_by_role
) values (
  '81500000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  (select project_id from v1_b8_targets), 'B8-RET-001-DSP001', current_date, 'DN-B8-001',
  'received', '10000000-0000-4000-8000-000000000003', 'procurement'
), (
  '81500000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000001',
  (select project_id from v1_b8_targets), 'B8-RET-001-DSP002', current_date, 'DN-B8-002',
  'receipt_pending', '10000000-0000-4000-8000-000000000003', 'procurement'
);
insert into public.v1_material_dispatch_lines (
  id, dispatch_id, request_line_id, arrangement_line_id, source_kind,
  inventory_item_id, external_supplier, item_description, brand_origin, unit,
  approved_qty_snapshot, dispatched_qty
) values (
  '81600000-0000-4000-8000-000000000001',
  '81500000-0000-4000-8000-000000000001',
  '81100000-0000-4000-8000-000000000001',
  '81400000-0000-4000-8000-000000000001', 'warehouse',
  '81200000-0000-4000-8000-000000000001', null, 'Copper pipe', 'UAE', 'Mtr', 3, 3
), (
  '81600000-0000-4000-8000-000000000002',
  '81500000-0000-4000-8000-000000000001',
  '81100000-0000-4000-8000-000000000002',
  '81400000-0000-4000-8000-000000000002', 'external_supplier',
  null, 'Local Supplier', 'Refrigerant valve', 'EU', 'Nos', 1, 1
), (
  '81600000-0000-4000-8000-000000000003',
  '81500000-0000-4000-8000-000000000002',
  '81100000-0000-4000-8000-000000000001',
  '81400000-0000-4000-8000-000000000001', 'warehouse',
  '81200000-0000-4000-8000-000000000001', null,
  'Copper pipe', 'UAE', 'Mtr', 3, 1
);
insert into public.v1_receipt_reviews (
  id, dispatch_id, request_id, reviewed_by_auth_user_id, reviewed_by_role
) values (
  '81700000-0000-4000-8000-000000000001',
  '81500000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002', 'site_engineer'
);
insert into public.v1_receipt_review_lines (
  id, receipt_review_id, dispatch_line_id, outcome, dispatched_qty_snapshot,
  good_qty, exception_qty, note
) values (
  '81800000-0000-4000-8000-000000000001',
  '81700000-0000-4000-8000-000000000001',
  '81600000-0000-4000-8000-000000000001', 'received', 3, 3, 0, null
), (
  '81800000-0000-4000-8000-000000000002',
  '81700000-0000-4000-8000-000000000001',
  '81600000-0000-4000-8000-000000000002', 'received', 1, 1, 0, null
);

-- A project may have more than one Project Engineer. The supporting Engineer
-- must receive the same post-receipt controlled-document capability even when
-- the assignment was recorded with the other engineering membership label.
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, reason,
  assigned_by_auth_user_id, assigned_by_role
) values (
  (select project_id from v1_b8_targets),
  '10000000-0000-4000-8000-000000000005',
  'site_engineer', 'Supporting Engineer for Delivery Order proof',
  '10000000-0000-4000-8000-000000000001', 'project_engineer'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select ok(
  public.v1_can_generate_delivery_order(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'The assigned Project Engineer can generate a Delivery Order for a committed dispatch'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000005","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-supporting-project-engineer"}}',
  true
);
select ok(
  public.v1_can_generate_delivery_order(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'Every actively assigned Project Engineer can generate the same Delivery Order'
);

select ok(
  (public.v1_returns_documents_workspace_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) ->> 'can_generate_delivery_order')::boolean,
  'The assigned Engineer projection enables the Delivery Order UI action'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  public.v1_can_generate_delivery_order(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'The assigned Site Engineer can generate a Delivery Order for a committed dispatch'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000006","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-unassigned-site-engineer"}}',
  true
);
select ok(
  not public.v1_can_generate_delivery_order(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'An unassigned Site Engineer cannot generate the project Delivery Order'
);

select throws_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1,
      'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-UNASSIGNED'
    ), '82000000-0000-4000-8000-000000000099'::uuid
  )$$,
  '42501', 'V1_DELIVERY_ORDER_GENERATE_DENIED',
  'The trusted generation RPC rejects an unassigned Engineer'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select ok(
  jsonb_array_length(public.v1_material_request_document_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) -> 'project_engineers') = 1
  and (public.v1_material_request_document_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) #>> '{dispatch,reference}') = 'DN-B8-002'
  and (public.v1_material_request_document_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) ->> 'show_line_status')::boolean
  and (public.v1_material_request_document_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) -> 'receipt_statuses') @> '[{
    "request_line_id":"81100000-0000-4000-8000-000000000001",
    "requested_qty":"5.0000",
    "approved_qty":"5.0000",
    "dispatched_qty":"4.0000",
    "in_transit_qty":"1.0000",
    "reviewed_good_qty":"3.0000",
    "remaining_approved_qty":"1.0000",
    "status":"Awaiting receipt review"
  }]'::jsonb,
  'The controlled MR document projection includes truthful partial-dispatch progress'
);

select throws_ok(
  $$insert into public.v1_delivery_orders (
    request_id, dispatch_id, project_id, delivery_order_reference,
    created_by_auth_user_id, created_by_role
  ) values (
    '81000000-0000-4000-8000-000000000001',
    '81500000-0000-4000-8000-000000000001',
    (select project_id from v1_b8_targets), 'BYPASS-DO', auth.uid(), 'procurement'
  )$$,
  '42501', null,
  'Procurement cannot bypass the Delivery Order command with a direct insert'
);

select ok(
  (select (candidate ->> 'can_generate')::boolean
   from jsonb_array_elements(public.v1_returns_documents_workspace_projection(
     '81000000-0000-4000-8000-000000000001'::uuid
   ) -> 'delivery_orders') candidate
   where candidate ->> 'dispatch_id' = '81500000-0000-4000-8000-000000000002'),
  'A dispatched delivery is eligible for its Delivery Order before receipt review'
);

select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', '  b8-do-001  '
    ), '82000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Procurement generates the first immutable Delivery Order revision'
);

set local role postgres;
select is(
  (select delivery_order_reference from public.v1_delivery_orders), 'B8-DO-001',
  'The authorized reference is normalized and stored globally'
);

select ok(
  (select count(*) = 1 from public.v1_delivery_order_revisions)
  and (select count(*) = 2 from public.v1_delivery_order_revision_lines)
  and (select bool_and(
    dispatch_line_id is not null
    and delivery_quantity = good_quantity
  ) from public.v1_delivery_order_revision_lines),
  'The legacy received Delivery Order is preserved with dispatch-linked printable quantities'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', '  b8-do-001  '
    ), '82000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'A Delivery Order retry returns the committed snapshot'
);

set local role postgres;
select is(
  (select count(*)::integer from public.v1_delivery_order_revisions), 1,
  'A Delivery Order retry never duplicates its immutable revision'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-001'
    ), '82000000-0000-4000-8000-000000000003'::uuid
  )$$,
  'Regeneration appends a second Delivery Order revision'
);

set local role postgres;
select ok(
  (select count(*) = 2 from public.v1_delivery_order_revisions)
  and (select count(*) = 2 from public.v1_delivery_order_revision_lines
    where delivery_order_revision_id = (
      select id from public.v1_delivery_order_revisions where revision_number = 1
    ))
  and (select current_revision_id = (
    select id from public.v1_delivery_order_revisions where revision_number = 2
  ) from public.v1_delivery_orders),
  'Regeneration moves only the current pointer and preserves the prior revision snapshot'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-001'
    ), '82000000-0000-4000-8000-000000000004'::uuid
  )$$,
  'An assigned Site Engineer can generate the post-receipt Delivery Order revision'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000005","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-supporting-project-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-001'
    ), '82000000-0000-4000-8000-000000000005'::uuid
  )$$,
  'An assigned Project Engineer can generate without a role-label 403'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_save_material_return_draft(
    jsonb_build_object(
      'return_id', null, 'request_id', '81000000-0000-4000-8000-000000000001',
      'expected_version', 0, 'note', 'Unused copper',
      'lines', jsonb_build_array(jsonb_build_object(
        'receipt_review_line_id', '81800000-0000-4000-8000-000000000001',
        'return_qty', '2'
      ))
    ), '83000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Site Engineer saves an editable warehouse return draft'
);

set local role postgres;
create temporary table v1_b8_warehouse_return as
select id as return_id, record_version from public.v1_material_returns
where note = 'Unused copper';
grant select on table v1_b8_warehouse_return to authenticated;

set local role authenticated;
select lives_ok(
  $$select public.v1_submit_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_warehouse_return),
      'expected_version', (select record_version from v1_b8_warehouse_return)
    ), '83000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Site Engineer submits a frozen return snapshot'
);

set local role postgres;
select ok(
  (select state = 'awaiting_approval' and return_number = 'B8-RET-001-RTN001'
    from public.v1_material_returns
    where id = (select return_id from v1_b8_warehouse_return))
  and (select eligible_quantity_at_submit = 3 from public.v1_material_return_lines
    where material_return_id = (select return_id from v1_b8_warehouse_return)),
  'Return submission allocates a number, freezes eligibility and requires Engineering approval'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_confirm_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_warehouse_return),
      'expected_version', 2, 'line_mappings', '[]'::jsonb
    ), '83000000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501', 'V1_MATERIAL_RETURN_RECEIPT_DENIED',
  'Site Engineer cannot confirm a physical warehouse return'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000005","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-supporting-project-engineer"}}',
  true
);
select public.v1_decide_project_material_return(
  jsonb_build_object(
    'return_id', (select return_id from v1_b8_warehouse_return),
    'expected_version', 2, 'decision', 'approved', 'reason', null
  ), '83000000-0000-4000-8000-000000000020'::uuid
);
select public.v1_dispatch_project_material_return(
  jsonb_build_object(
    'return_id', (select return_id from v1_b8_warehouse_return),
    'expected_version', 3, 'driver_name', 'Batch 8 Driver',
    'vehicle_reference', 'B8-TRUCK-01',
    'delivery_note_reference', 'B8-RETURN-DN-01'
  ), '83000000-0000-4000-8000-000000000021'::uuid
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select lives_ok(
  $$select public.v1_confirm_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_warehouse_return),
      'expected_version', 4, 'line_mappings', '[]'::jsonb
    ), '83000000-0000-4000-8000-000000000004'::uuid
  )$$,
  'Procurement confirms the physical warehouse return'
);

select lives_ok(
  $$select public.v1_confirm_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_warehouse_return),
      'expected_version', 4, 'line_mappings', '[]'::jsonb
    ), '83000000-0000-4000-8000-000000000004'::uuid
  )$$,
  'A confirmation retry returns the original committed response'
);

set local role postgres;
select ok(
  (select state = 'confirmed' from public.v1_material_returns
    where id = (select return_id from v1_b8_warehouse_return))
  and (select on_hand_qty = 2 from public.v1_inventory_balances
    where inventory_item_id = '81200000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from public.v1_inventory_movements
    where source_entity_type = 'material_return_line'),
  'Confirmation increments stock and appends its movement exactly once'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_save_material_return_draft(
    jsonb_build_object(
      'return_id', null, 'request_id', '81000000-0000-4000-8000-000000000001',
      'expected_version', 0, 'note', 'Too much copper',
      'lines', jsonb_build_array(jsonb_build_object(
        'receipt_review_line_id', '81800000-0000-4000-8000-000000000001',
        'return_qty', '2'
      ))
    ), '83000000-0000-4000-8000-000000000005'::uuid
  )$$,
  'A second draft can be prepared without reserving stock'
);

set local role postgres;
create temporary table v1_b8_over_return as
select id as return_id, record_version from public.v1_material_returns
where note = 'Too much copper';
grant select on table v1_b8_over_return to authenticated;

set local role authenticated;
select throws_ok(
  $$select public.v1_submit_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_over_return),
      'expected_version', (select record_version from v1_b8_over_return)
    ), '83000000-0000-4000-8000-000000000006'::uuid
  )$$,
  '22023', 'V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED',
  'Submission rejects returns above good received less prior confirmed returns'
);

select lives_ok(
  $$select public.v1_save_material_return_draft(
    jsonb_build_object(
      'return_id', null, 'request_id', '81000000-0000-4000-8000-000000000001',
      'expected_version', 0, 'note', 'Supplier valve return',
      'lines', jsonb_build_array(jsonb_build_object(
        'receipt_review_line_id', '81800000-0000-4000-8000-000000000002',
        'return_qty', '1'
      ))
    ), '83000000-0000-4000-8000-000000000007'::uuid
  )$$,
  'A supplier-source return draft retains its receipt provenance'
);

set local role postgres;
create temporary table v1_b8_supplier_return as
select id as return_id, record_version from public.v1_material_returns
where note = 'Supplier valve return';
grant select on table v1_b8_supplier_return to authenticated;

set local role authenticated;
select lives_ok(
  $$select public.v1_submit_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_supplier_return),
      'expected_version', (select record_version from v1_b8_supplier_return)
    ), '83000000-0000-4000-8000-000000000008'::uuid
  )$$,
  'The supplier-source return is submitted for Procurement confirmation'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000005","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-supporting-project-engineer"}}',
  true
);
select public.v1_decide_project_material_return(
  jsonb_build_object(
    'return_id', (select return_id from v1_b8_supplier_return),
    'expected_version', 2, 'decision', 'approved', 'reason', null
  ), '83000000-0000-4000-8000-000000000022'::uuid
);
select public.v1_dispatch_project_material_return(
  jsonb_build_object(
    'return_id', (select return_id from v1_b8_supplier_return),
    'expected_version', 3, 'driver_name', 'Batch 8 Driver',
    'vehicle_reference', 'B8-TRUCK-02',
    'delivery_note_reference', 'B8-RETURN-DN-02'
  ), '83000000-0000-4000-8000-000000000023'::uuid
);

set local role postgres;
create temporary table v1_b8_supplier_return_line as
select id as return_line_id from public.v1_material_return_lines
where material_return_id = (select return_id from v1_b8_supplier_return);
grant select on table v1_b8_supplier_return_line to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select throws_ok(
  $$select public.v1_confirm_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_supplier_return),
      'expected_version', 4, 'line_mappings', '[]'::jsonb
    ), '83000000-0000-4000-8000-000000000009'::uuid
  )$$,
  '22023', 'V1_MATERIAL_RETURN_TARGET_ITEM_INVALID',
  'Supplier-source stock cannot be confirmed without an identified inventory item'
);

select lives_ok(
  $$select public.v1_confirm_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_supplier_return),
      'expected_version', 4,
      'line_mappings', jsonb_build_array(jsonb_build_object(
        'return_line_id', (select return_line_id from v1_b8_supplier_return_line),
        'inventory_item_id', null,
        'new_inventory_item', jsonb_build_object(
          'item_description', 'Refrigerant valve', 'brand_origin', 'EU', 'unit', 'Nos'
        )
      ))
    ), '83000000-0000-4000-8000-000000000010'::uuid
  )$$,
  'Procurement maps supplier material to a new controlled inventory item on confirmation'
);

set local role postgres;
select ok(
  (select count(*) = 1 from public.v1_inventory_items
    where item_description = 'Refrigerant valve' and unit = 'Nos')
  and (select count(*) = 2 from public.v1_inventory_movements
    where source_entity_type = 'material_return_line'),
  'Supplier return creates identified stock and one auditable movement'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_save_material_return_draft(
    jsonb_build_object(
      'return_id', null, 'request_id', '81000000-0000-4000-8000-000000000001',
      'expected_version', 0, 'note', 'Return awaiting warehouse check',
      'lines', jsonb_build_array(jsonb_build_object(
        'receipt_review_line_id', '81800000-0000-4000-8000-000000000001',
        'return_qty', '1'
      ))
    ), '83000000-0000-4000-8000-000000000011'::uuid
  )$$,
  'The remaining good quantity can be prepared as another return draft'
);

set local role postgres;
create temporary table v1_b8_rejected_return as
select id as return_id, record_version from public.v1_material_returns
where note = 'Return awaiting warehouse check';
grant select on table v1_b8_rejected_return to authenticated;

set local role authenticated;
select lives_ok(
  $$select public.v1_submit_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_rejected_return),
      'expected_version', (select record_version from v1_b8_rejected_return)
    ), '83000000-0000-4000-8000-000000000012'::uuid
  )$$,
  'The final eligible draft can be submitted for a warehouse decision'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000005","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-supporting-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_reject_material_return(
    jsonb_build_object(
      'return_id', (select return_id from v1_b8_rejected_return),
      'expected_version', 2, 'reason', 'Warehouse count does not match'
    ), '83000000-0000-4000-8000-000000000013'::uuid
  )$$,
  'Project Engineering rejects an awaiting-approval return with a required reason'
);

set local role postgres;
select ok(
  (select state = 'rejected' and rejection_reason = 'Warehouse count does not match'
    from public.v1_material_returns
    where id = (select return_id from v1_b8_rejected_return))
  and (select count(*) = 2 from public.v1_inventory_movements
    where source_entity_type = 'material_return_line'),
  'A rejected return records its decision without moving stock'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  jsonb_path_exists(
    public.v1_project_material_movements(
      (select project_id from v1_b8_targets)
    ), '$[*] ? (@.movement_kind == "dispatched")'
  ) and jsonb_path_exists(
    public.v1_project_material_movements(
      (select project_id from v1_b8_targets)
    ), '$[*] ? (@.movement_kind == "returned")'
  ),
  'An associated engineer sees committed outgoing and confirmed return facts'
);
select is(
  (select count(*) from jsonb_array_elements(
    public.v1_project_material_movements(
      (select project_id from v1_b8_targets)
    )
  ) movement where movement ->> 'movement_kind' = 'returned'),
  2::bigint,
  'Draft and rejected returns never enter the project material movement register'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000006","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-unassigned-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_project_material_movements(
    (select project_id from v1_b8_targets)
  )$$,
  '42501', 'V1_PROJECT_MATERIAL_MOVEMENT_DENIED',
  'An unassigned engineer cannot read another project material movement register'
);

-- Organization-wide engineering roles are exact Auth claims, but every
-- trusted command sees Project Engineer workflow authority. Neither role has
-- a dated membership row in this project and neither receives commercial,
-- warehouse or Admin capabilities.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000007","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-senior-mechanical-engineer"}}',
  true
);

select ok(
  public.v1_project_readable((select project_id from v1_b8_targets)),
  'Senior Mechanical Engineer has server-controlled access to every project'
);

select ok(
  public.v1_can_decide_arrangement(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'Senior Mechanical Engineer can approve an MR arrangement without assignment'
);

select ok(
  (public.v1_get_current_commercial_capabilities()
    #>> '{capabilities,view_commercials,effective}') = 'false'
  and not has_table_privilege(
    'authenticated', 'public.v1_inventory_items', 'select'
  ),
  'Senior Mechanical Engineer does not inherit commercial or warehouse authority'
);

select ok(
  (public.v1_returns_documents_workspace_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) ->> 'job_contract_reference') = 'N-19957.2'
  and (public.v1_returns_documents_workspace_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) ->> 'scope_code') = 'b8'
  and (public.v1_material_request_document_projection(
    '81000000-0000-4000-8000-000000000001'::uuid
  ) #>> '{request,job_contract_reference}') = 'N-19957.2',
  'Controlled MR and Delivery Order projections include job and building identity'
);

select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000002',
      'expected_request_version', 1,
      'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-DISPATCH'
    ), '82000000-0000-4000-8000-000000000010'::uuid
  )$$,
  'Senior Mechanical Engineer generates the dispatch-level Delivery Order'
);

set local role postgres;
select ok(
  (select revision.receipt_review_id is null
     from public.v1_delivery_order_revisions revision
     join public.v1_delivery_orders delivery_order
       on delivery_order.id = revision.delivery_order_id
    where delivery_order.dispatch_id = '81500000-0000-4000-8000-000000000002'
      and revision.revision_number = 1)
  and (select count(*) = 1
     from public.v1_delivery_order_revision_lines revision_line
     join public.v1_delivery_order_revisions revision
       on revision.id = revision_line.delivery_order_revision_id
     join public.v1_delivery_orders delivery_order
       on delivery_order.id = revision.delivery_order_id
    where delivery_order.dispatch_id = '81500000-0000-4000-8000-000000000002'
      and revision_line.delivery_quantity = 1
      and revision_line.receipt_review_line_id is null),
  'Dispatch-level Delivery Order snapshots dispatched quantity without inventing receipt facts'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000008","role":"authenticated","app_metadata":{"role":"project_manager","app_user_id":"usr-project-manager"}}',
  true
);

select ok(
  public.v1_can_decide_arrangement(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'Project Manager receives Project Engineer workflow authority'
);

select ok(
  public.v1_project_readable((select project_id from v1_b8_targets))
  and public.v1_can_decide_arrangement(
    '81000000-0000-4000-8000-000000000001'::uuid
  )
  and public.v1_can_generate_delivery_order(
    '81000000-0000-4000-8000-000000000001'::uuid
  ),
  'Project Manager can access every project, approve MRs and generate Delivery Orders'
);

select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '81000000-0000-4000-8000-000000000001',
      'dispatch_id', '81500000-0000-4000-8000-000000000002',
      'expected_request_version', 1,
      'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-DISPATCH'
    ), '82000000-0000-4000-8000-000000000011'::uuid
  )$$,
  'Project Manager can append a controlled dispatch Delivery Order revision'
);

set local role postgres;
select is(
  (select count(*)::integer
     from public.v1_delivery_order_revisions revision
     join public.v1_delivery_orders delivery_order
       on delivery_order.id = revision.delivery_order_id
    where delivery_order.dispatch_id = '81500000-0000-4000-8000-000000000002'),
  2,
  'Global Engineer regeneration preserves prior immutable dispatch revisions'
);

-- A Delivery Order created at dispatch is immutable evidence of what was sent.
-- Once the assigned Engineer confirms the receipt review, the current
-- printable Delivery Report must instead show the confirmed good quantity,
-- including a zero-quantity line for a fully missing or damaged item.
set local role postgres;
insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state, record_version,
  created_by_auth_user_id, requester_display_name, requester_project_role,
  current_action_owner_role, current_action_code, submitted_at,
  project_engineer_snapshot
) values (
  '82100000-0000-4000-8000-000000000001',
  (select project_id from v1_b8_targets), (select scope_id from v1_b8_targets),
  'B8-RET-001-MR002', 'Receipt report quantity proof', 'normal', 'dispatched', 1,
  '10000000-0000-4000-8000-000000000001', 'Local Project Engineer', 'project_engineer',
  'project_engineer', 'material_request_receipt_review', clock_timestamp(),
  '[{"display_name":"Local Project Engineer"}]'::jsonb
);
insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description, brand_origin,
  requested_qty, unit, technical_attributes
) values
  ('82200000-0000-4000-8000-000000000001',
    '82100000-0000-4000-8000-000000000001', 1, 'custom', 'Supply duct', 'UAE', 10, 'Nos',
    '{"size":"500x300mm","model":"GI"}'::jsonb),
  ('82200000-0000-4000-8000-000000000002',
    '82100000-0000-4000-8000-000000000001', 2, 'custom', 'Control panel', 'UAE', 2, 'Nos',
    '{"size":"600x400mm","planning_model_tag":"CP-01"}'::jsonb);
insert into public.v1_procurement_arrangements (
  id, request_id, arrangement_version, status, is_current,
  started_by_auth_user_id, saved_by_auth_user_id, saved_at
) values (
  '82300000-0000-4000-8000-000000000001',
  '82100000-0000-4000-8000-000000000001', 1, 'approved', true,
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000003', clock_timestamp()
);
insert into public.v1_procurement_arrangement_lines (
  id, arrangement_id, request_line_id, source_kind, inventory_item_id,
  decision, arranged_qty, warehouse_available_at_save
) values
  ('82400000-0000-4000-8000-000000000001',
    '82300000-0000-4000-8000-000000000001',
    '82200000-0000-4000-8000-000000000001', 'external_supplier', null, 'full', 10, null),
  ('82400000-0000-4000-8000-000000000002',
    '82300000-0000-4000-8000-000000000001',
    '82200000-0000-4000-8000-000000000002', 'external_supplier', null, 'full', 2, null);
insert into public.v1_material_request_line_approvals (
  request_line_id, arrangement_line_id, arrangement_id, approved_qty,
  approved_by_auth_user_id
) values
  ('82200000-0000-4000-8000-000000000001',
    '82400000-0000-4000-8000-000000000001',
    '82300000-0000-4000-8000-000000000001', 10,
    '10000000-0000-4000-8000-000000000001'),
  ('82200000-0000-4000-8000-000000000002',
    '82400000-0000-4000-8000-000000000002',
    '82300000-0000-4000-8000-000000000001', 2,
    '10000000-0000-4000-8000-000000000001');
insert into public.v1_material_dispatches (
  id, request_id, project_id, dispatch_number, dispatch_date, delivery_reference, state,
  dispatched_by_auth_user_id, dispatched_by_role
) values (
  '82500000-0000-4000-8000-000000000001',
  '82100000-0000-4000-8000-000000000001',
  (select project_id from v1_b8_targets), 'B8-RET-001-DSP003', current_date, 'DN-B8-003',
  'receipt_pending', '10000000-0000-4000-8000-000000000003', 'procurement'
);
insert into public.v1_material_dispatch_lines (
  id, dispatch_id, request_line_id, arrangement_line_id, source_kind,
  inventory_item_id, external_supplier, item_description, brand_origin, unit,
  approved_qty_snapshot, dispatched_qty
) values
  ('82600000-0000-4000-8000-000000000001',
    '82500000-0000-4000-8000-000000000001',
    '82200000-0000-4000-8000-000000000001',
    '82400000-0000-4000-8000-000000000001', 'external_supplier', null,
    'Local Supplier', 'Supply duct', 'UAE', 'Nos', 10, 10),
  ('82600000-0000-4000-8000-000000000002',
    '82500000-0000-4000-8000-000000000001',
    '82200000-0000-4000-8000-000000000002',
    '82400000-0000-4000-8000-000000000002', 'external_supplier', null,
    'Local Supplier', 'Control panel', 'UAE', 'Nos', 2, 2);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_generate_delivery_order(
    jsonb_build_object(
      'request_id', '82100000-0000-4000-8000-000000000001',
      'dispatch_id', '82500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'delivery_order_reference', 'B8-DO-RECEIPT-REVIEW'
    ), '82700000-0000-4000-8000-000000000001'::uuid
  )$$,
  'The committed dispatch first creates an immutable dispatch Delivery Order'
);

set local role postgres;
select is(
  (select sum(line.delivery_quantity)::text
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'
     and revision.snapshot_kind = 'dispatch'),
  '12.0000',
  'The immutable dispatch snapshot retains all 12 committed items before receipt review'
);

select ok(
  (select bool_and(
     line.size_text is not null and line.model_reference is not null
   )
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'
     and revision.snapshot_kind = 'dispatch')
  and (select public.v1_delivery_order_projection(delivery_order.id)
       #>> '{revisions,0,lines,0,size}'
       from public.v1_delivery_orders delivery_order
       where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001') = '500x300mm'
  and (select public.v1_delivery_order_projection(delivery_order.id)
       #>> '{revisions,0,lines,0,model}'
       from public.v1_delivery_orders delivery_order
       where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001') = 'GI',
  'Dispatch Delivery Order freezes and projects submitted MR size and model metadata'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_confirm_receipt(
    jsonb_build_object(
      'request_id', '82100000-0000-4000-8000-000000000001',
      'dispatch_id', '82500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'lines', jsonb_build_array(
        jsonb_build_object(
          'dispatch_line_id', '82600000-0000-4000-8000-000000000001',
          'outcome', 'missing', 'good_qty', '8', 'note', 'Two items missing'
        ),
        jsonb_build_object(
          'dispatch_line_id', '82600000-0000-4000-8000-000000000002',
          'outcome', 'damaged', 'good_qty', '0', 'note', 'Both items damaged'
        )
      )
    ), '82700000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Receipt review atomically appends the receipt-reviewed Delivery Report'
);

set local role postgres;
select ok(
  (select count(*) = 2
   from public.v1_delivery_order_revisions revision
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001')
  and (select sum(line.delivery_quantity) = 12
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'
     and revision.snapshot_kind = 'dispatch')
  and (select sum(line.delivery_quantity) = 8
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'
     and revision.snapshot_kind = 'receipt_review'
     and revision.id = delivery_order.current_revision_id)
  and (select count(*) = 2 and min(line.delivery_quantity) = 0
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'
     and revision.snapshot_kind = 'receipt_review'
     and revision.id = delivery_order.current_revision_id),
  'The current Delivery Report shows 8 good items and retains the fully damaged zero-quantity line'
);

select ok(
  (select bool_and(
     line.size_text is not null and line.model_reference is not null
   )
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001')
  and (select count(distinct (line.size_text, line.model_reference)) = 2
   from public.v1_delivery_order_revision_lines line
   join public.v1_delivery_order_revisions revision
     on revision.id = line.delivery_order_revision_id
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'),
  'Receipt-reviewed Delivery Report retains the same immutable size/model facts across revisions'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_confirm_receipt(
    jsonb_build_object(
      'request_id', '82100000-0000-4000-8000-000000000001',
      'dispatch_id', '82500000-0000-4000-8000-000000000001',
      'expected_request_version', 1, 'expected_dispatch_version', 1,
      'lines', jsonb_build_array(
        jsonb_build_object(
          'dispatch_line_id', '82600000-0000-4000-8000-000000000001',
          'outcome', 'missing', 'good_qty', '8', 'note', 'Two items missing'
        ),
        jsonb_build_object(
          'dispatch_line_id', '82600000-0000-4000-8000-000000000002',
          'outcome', 'damaged', 'good_qty', '0', 'note', 'Both items damaged'
        )
      )
    ), '82700000-0000-4000-8000-000000000002'::uuid
  )$$,
  'A receipt confirmation retry returns the stored result'
);

set local role postgres;
select is(
  (select count(*)::integer
   from public.v1_delivery_order_revisions revision
   join public.v1_delivery_orders delivery_order
     on delivery_order.id = revision.delivery_order_id
   where delivery_order.dispatch_id = '82500000-0000-4000-8000-000000000001'),
  2,
  'A receipt retry never duplicates the receipt-reviewed Delivery Report revision'
);

-- Project-wide Material Returns are a separate controlled document lifecycle.
-- They may trace a confirmed delivery or carry an explicit unmatched custom
-- row, but only Procurement confirmation creates a warehouse movement.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000008","role":"authenticated","app_metadata":{"role":"project_manager","app_user_id":"usr-project-manager"}}',
  true
);
select ok(
  public.v1_can_create_project_material_return(
    (select project_id from v1_b8_targets)
  ) and public.v1_can_approve_project_material_return(
    (select project_id from v1_b8_targets)
  ),
  'A global Project Manager can create and approve a return without project membership'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000007","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-senior-mechanical-engineer"}}',
  true
);
select ok(
  public.v1_can_create_project_material_return(
    (select project_id from v1_b8_targets)
  ) and public.v1_can_approve_project_material_return(
    (select project_id from v1_b8_targets)
  ),
  'A global Senior Mechanical Engineer has the same controlled return authority'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_save_project_material_return_draft(
    jsonb_build_object(
      'return_id', null,
      'project_id', (select project_id from v1_b8_targets),
      'scope_id', (select scope_id from v1_b8_targets),
      'expected_version', 0,
      'purpose', 'Return unmatched project ladder',
      'note', 'Project close-out stock reconciliation',
      'requested_return_date', current_date,
      'lines', jsonb_build_array(jsonb_build_object(
        'origin_kind', 'custom',
        'receipt_review_line_id', null,
        'item_description', 'Project return custom ladder',
        'brand_origin', 'Yorks test',
        'unit', 'Nos',
        'return_qty', '2',
        'note', 'No historical MR reference available'
      ))
    ), '82800000-0000-4000-8000-000000000001'::uuid
  )$$,
  'An assigned Site Engineer saves a project-wide custom return draft'
);

set local role postgres;
create temporary table v1_b8_project_returns as
select material_return.id, material_return.record_version,
  return_line.id as return_line_id
from public.v1_material_returns material_return
join public.v1_material_return_lines return_line
  on return_line.material_return_id = material_return.id
where material_return.purpose = 'Return unmatched project ladder';
grant select on table v1_b8_project_returns to authenticated;
select ok(
  (select material_return.state = 'draft'
      and material_return.request_id is null
    from public.v1_material_returns material_return
    where material_return.id = (select id from v1_b8_project_returns)),
  'The project-wide draft remains independent from any guessed Material Request'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_submit_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 1
    ), '82800000-0000-4000-8000-000000000002'::uuid
  )$$,
  'The creator explicitly submits the return for Engineering approval'
);

set local role postgres;
select ok(
  (select material_return.state = 'awaiting_approval'
      and material_return.return_number like 'B8-RET-001-RTN%'
    from public.v1_material_returns material_return
    where material_return.id = (select id from v1_b8_project_returns)),
  'Submission assigns the project return reference and Engineering queue state'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_decide_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 2,
      'decision', 'approved',
      'reason', null
    ), '82800000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501', 'V1_MATERIAL_RETURN_DECISION_DENIED',
  'Procurement cannot approve the return that it will physically receive'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000008","role":"authenticated","app_metadata":{"role":"project_manager","app_user_id":"usr-project-manager"}}',
  true
);
select lives_ok(
  $$select public.v1_decide_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 2,
      'decision', 'approved',
      'reason', 'Approved for warehouse return'
    ), '82800000-0000-4000-8000-000000000004'::uuid
  )$$,
  'The global Project Manager approves the controlled return'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_dispatch_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 3,
      'driver_name', 'Taimoor Shah',
      'vehicle_reference', 'AD-12345',
      'delivery_note_reference', 'RTN-DN-001'
    ), '82800000-0000-4000-8000-000000000005'::uuid
  )$$,
  'The project team records driver and delivery-note custody before transport'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_confirm_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 4,
      'receipt_note', 'Counted and accepted at warehouse',
      'line_receipts', jsonb_build_array(jsonb_build_object(
        'return_line_id', (select return_line_id from v1_b8_project_returns),
        'received_good_qty', '2',
        'damaged_qty', '0',
        'not_received_qty', '0',
        'inventory_item_id', null,
        'new_inventory_item', jsonb_build_object(
          'item_description', 'Project return custom ladder',
          'brand_origin', 'Yorks test',
          'unit', 'Nos'
        ),
        'note', 'Accepted in good condition'
      ))
    ), '82800000-0000-4000-8000-000000000006'::uuid
  )$$,
  'Procurement confirms the physical receipt and maps unmatched material'
);

set local role postgres;
select ok(
  (select material_return.state = 'confirmed'
    from public.v1_material_returns material_return
    where material_return.id = (select id from v1_b8_project_returns))
  and (select balance.on_hand_qty = 2
    from public.v1_inventory_items item
    join public.v1_inventory_balances balance
      on balance.inventory_item_id = item.id
    where item.item_description = 'Project return custom ladder')
  and (select count(*) = 1
    from public.v1_inventory_movements movement
    join public.v1_material_return_lines line
      on line.id = movement.source_entity_id
    where line.material_return_id = (select id from v1_b8_project_returns)
      and movement.movement_type = 'return'),
  'Only accepted-good quantity enters stock through one append-only movement'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_confirm_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_project_returns),
      'expected_version', 4,
      'receipt_note', 'Counted and accepted at warehouse',
      'line_receipts', jsonb_build_array(jsonb_build_object(
        'return_line_id', (select return_line_id from v1_b8_project_returns),
        'received_good_qty', '2', 'damaged_qty', '0', 'not_received_qty', '0',
        'inventory_item_id', null,
        'new_inventory_item', jsonb_build_object(
          'item_description', 'Project return custom ladder',
          'brand_origin', 'Yorks test', 'unit', 'Nos'
        ),
        'note', 'Accepted in good condition'
      ))
    ), '82800000-0000-4000-8000-000000000006'::uuid
  )$$,
  'A confirmation retry returns the stored result'
);

set local role postgres;
select is(
  (select count(*)::integer
    from public.v1_inventory_movements movement
    join public.v1_material_return_lines line
      on line.id = movement.source_entity_id
    where line.material_return_id = (select id from v1_b8_project_returns)
      and movement.movement_type = 'return'),
  1,
  'A confirmation retry never duplicates stock movement'
);

create temporary table v1_b8_delivered_return_source as
select review_line.id as receipt_review_line_id
from public.v1_receipt_review_lines review_line
join public.v1_material_dispatch_lines dispatch_line
  on dispatch_line.id = review_line.dispatch_line_id
where dispatch_line.dispatch_id = '82500000-0000-4000-8000-000000000001'
  and review_line.good_qty > 0
limit 1;
grant select on table v1_b8_delivered_return_source to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_save_project_material_return_draft(
    jsonb_build_object(
      'return_id', null,
      'project_id', (select project_id from v1_b8_targets),
      'scope_id', (select scope.id from public.v1_project_scopes scope
        where scope.project_id = (select project_id from v1_b8_targets)
          and scope.scope_kind = 'common'),
      'expected_version', 0,
      'purpose', 'Material moved to another building',
      'note', null,
      'requested_return_date', null,
      'lines', jsonb_build_array(jsonb_build_object(
        'origin_kind', 'delivered',
        'receipt_review_line_id', (select receipt_review_line_id
          from v1_b8_delivered_return_source),
        'item_description', null,
        'brand_origin', null,
        'unit', null,
        'return_qty', '1',
        'note', null
      ))
    ), '82800000-0000-4000-8000-000000000017'::uuid
  )$$,
  'Material delivered to one building can be returned from another building of the same project (4 Nov 2026)'
);

select lives_ok(
  $$select public.v1_save_project_material_return_draft(
    jsonb_build_object(
      'return_id', null,
      'project_id', (select project_id from v1_b8_targets),
      'scope_id', (select scope_id from v1_b8_targets),
      'expected_version', 0,
      'purpose', 'Trace delivered item then cancel',
      'note', null,
      'requested_return_date', null,
      'lines', jsonb_build_array(jsonb_build_object(
        'origin_kind', 'delivered',
        'receipt_review_line_id', (select receipt_review_line_id
          from v1_b8_delivered_return_source),
        'item_description', null,
        'brand_origin', null,
        'unit', null,
        'return_qty', '1',
        'note', 'Trace proof'
      ))
    ), '82800000-0000-4000-8000-000000000007'::uuid
  )$$,
  'A project return can be created directly from a confirmed delivered line'
);

set local role postgres;
create temporary table v1_b8_cancel_return as
select material_return.id
from public.v1_material_returns material_return
where material_return.purpose = 'Trace delivered item then cancel';
grant select on table v1_b8_cancel_return to authenticated;
select ok(
  (select line.source_request_id is not null
      and line.source_dispatch_id is not null
      and line.receipt_review_line_id is not null
    from public.v1_material_return_lines line
    join public.v1_material_returns material_return
      on material_return.id = line.material_return_id
    where material_return.purpose = 'Trace delivered item then cancel'),
  'Delivered-line returns retain MR, dispatch and receipt provenance'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_cancel_project_material_return(
    jsonb_build_object(
      'return_id', (select id from v1_b8_cancel_return),
      'expected_version', 1,
      'reason', 'Transport no longer required'
    ), '82800000-0000-4000-8000-000000000008'::uuid
  )$$,
  'The creator may cancel a draft with an audited reason before dispatch'
);

set local role postgres;
select ok(
  (select material_return.state = 'cancelled'
      and material_return.cancellation_reason = 'Transport no longer required'
    from public.v1_material_returns material_return
    where material_return.purpose = 'Trace delivered item then cancel')
  and not exists (
    select 1 from public.v1_inventory_movements movement
    join public.v1_material_return_lines line
      on line.id = movement.source_entity_id
    join public.v1_material_returns material_return
      on material_return.id = line.material_return_id
    where material_return.purpose = 'Trace delivered item then cancel'
  ),
  'Cancellation records the reason and never changes warehouse stock'
);

select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok(
  has_function_privilege('authenticated','public.v1_save_company_material_supply_plan(jsonb,uuid)','execute')
  and has_function_privilege('authenticated','public.v1_dispatch_company_materials(jsonb,uuid)','execute')
  and not has_table_privilege('authenticated','public.v1_company_material_dispatches','insert'),
  'Fulfilment mutations are exposed only through protected commands'
);

set local role postgres;
insert into public.v1_company_material_request_categories(id,category_code,display_name)
values('c3000000-0000-4000-8000-000000000001','ppe_fulfilment','PPE fulfilment');
insert into public.v1_company_material_request_units(id,unit_code,display_name)
values('c3000000-0000-4000-8000-000000000002','FULFILMENT','Fulfilment unit');
insert into public.v1_company_material_request_authorizations(
  auth_user_id,category_id,responsible_unit_id,authority
) values
('10000000-0000-4000-8000-000000000002','c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002','requester'),
('10000000-0000-4000-8000-000000000002','c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002','beneficiary'),
('10000000-0000-4000-8000-000000000002','c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002','receiver'),
('10000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002','approver');
insert into public.v1_company_material_request_approval_routes(
  id,category_id,responsible_unit_id,primary_approver_auth_user_id,policy_version
) values('c3000000-0000-4000-8000-000000000003','c3000000-0000-4000-8000-000000000001',
  'c3000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','cmr-full-v1');
insert into public.v1_company_material_requests(
  id,request_number,state,record_version,category_id,responsible_unit_id,purpose,timing,
  delivery_collection_point,beneficiary_auth_user_id,beneficiary_display_name,
  authorized_receiver_auth_user_id,authorized_receiver_display_name,
  created_by_auth_user_id,requester_display_name,requester_exact_role,
  approval_route_id,approval_policy_version,approver_auth_user_id,approver_display_name,submitted_at
) values('c3000000-0000-4000-8000-000000000010','CMR-TEST-FULL','approved_for_procurement',3,
  'c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002',
  'Issue two safety jackets','normal','Workshop issue desk',
  '10000000-0000-4000-8000-000000000002','Site Engineer',
  '10000000-0000-4000-8000-000000000002','Site Engineer',
  '10000000-0000-4000-8000-000000000002','Site Engineer','site_engineer',
  'c3000000-0000-4000-8000-000000000003','cmr-full-v1',
  '10000000-0000-4000-8000-000000000001','Project Engineer',clock_timestamp());
insert into public.v1_company_material_request_lines(
  id,request_id,display_order,item_description,requested_qty,unit
) values('c3000000-0000-4000-8000-000000000011','c3000000-0000-4000-8000-000000000010',
  1,'Safety jacket size L',2,'Nos');
insert into public.v1_company_material_requests(
  id,request_number,state,record_version,category_id,responsible_unit_id,purpose,timing,
  delivery_collection_point,beneficiary_auth_user_id,beneficiary_display_name,
  authorized_receiver_auth_user_id,authorized_receiver_display_name,
  created_by_auth_user_id,requester_display_name,requester_exact_role,
  approval_route_id,approval_policy_version,approver_auth_user_id,approver_display_name,submitted_at
) values('c3000000-0000-4000-8000-000000000012','CMR-TEST-RETURNED','returned_for_changes',3,
  'c3000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002',
  'Wrong jacket quantity','normal','Workshop issue desk',
  '10000000-0000-4000-8000-000000000002','Site Engineer',
  '10000000-0000-4000-8000-000000000002','Site Engineer',
  '10000000-0000-4000-8000-000000000002','Site Engineer','site_engineer',
  'c3000000-0000-4000-8000-000000000003','cmr-full-v1',
  '10000000-0000-4000-8000-000000000001','Project Engineer',clock_timestamp());
insert into public.v1_company_material_request_lines(
  id,request_id,display_order,item_description,requested_qty,unit
) values('c3000000-0000-4000-8000-000000000013','c3000000-0000-4000-8000-000000000012',
  1,'Safety jacket size M',1,'Nos');
insert into public.v1_inventory_items(id,item_description,unit,created_by_auth_user_id)
values('c3000000-0000-4000-8000-000000000020','Safety jacket size L','Nos',
  '10000000-0000-4000-8000-000000000003');
insert into public.v1_inventory_balances(inventory_item_id,on_hand_qty)
values('c3000000-0000-4000-8000-000000000020',5);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',true);
select throws_ok($$select public.v1_save_company_material_supply_plan(
  jsonb_build_object('request_id','c3000000-0000-4000-8000-000000000010',
  'expected_version',3,'lines','[]'::jsonb),'c3000000-0000-4000-8000-000000000030')$$,
  '42501','V1_COMPANY_SUPPLY_PLAN_DENIED','Requester cannot arrange approved company demand');
create temporary table cmr_revised as select public.v1_revise_and_resubmit_company_material_request(
  jsonb_build_object('request_id','c3000000-0000-4000-8000-000000000012',
    'expected_version',3,'purpose','Corrected jacket quantity',
    'delivery_collection_point','Workshop issue desk',
    'lines',jsonb_build_array(jsonb_build_object(
      'id','c3000000-0000-4000-8000-000000000013',
      'item_description','Safety jacket size M','brand_origin',null,
      'requested_qty','2','unit','Nos'))),
  'c3000000-0000-4000-8000-000000000040') response;
grant select on cmr_revised to authenticated;
select is((select response->>'state' from cmr_revised),'awaiting_company_approval',
  'Returned request is revised and rerouted on the same reference');
select is(public.v1_revise_and_resubmit_company_material_request(
  jsonb_build_object('request_id','c3000000-0000-4000-8000-000000000012',
    'expected_version',3,'purpose','Corrected jacket quantity',
    'delivery_collection_point','Workshop issue desk',
    'lines',jsonb_build_array(jsonb_build_object(
      'id','c3000000-0000-4000-8000-000000000013',
      'item_description','Safety jacket size M','brand_origin',null,
      'requested_qty','2','unit','Nos'))),
  'c3000000-0000-4000-8000-000000000040'),(select response from cmr_revised),
  'Returned revision retry is idempotent');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',true);
select is((select count(*)::integer from jsonb_array_elements(public.v1_list_company_material_request_work_inbox()) item where item->>'id'='c3000000-0000-4000-8000-000000000010'),1,
  'Procurement discovers approved company demand in its protected work inbox');
create temporary table cmr_full_plan as select public.v1_save_company_material_supply_plan(
  jsonb_build_object('request_id','c3000000-0000-4000-8000-000000000010',
    'expected_version',3,'lines',jsonb_build_array(jsonb_build_object(
      'request_line_id','c3000000-0000-4000-8000-000000000011','decision','full',
      'source_kind','warehouse','inventory_item_id','c3000000-0000-4000-8000-000000000020',
      'external_supplier',null,'arranged_qty','2','expected_available_date',null,
      'follow_up_date',null,'reason',null))),
  'c3000000-0000-4000-8000-000000000031') response;
grant select on cmr_full_plan to authenticated;
select is((select response->>'state' from cmr_full_plan),'ready_for_delivery',
  'Full warehouse plan makes the approved quantity ready');
set local role postgres;
select is((select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations
  where request_kind='company' and request_id='c3000000-0000-4000-8000-000000000010'),
  2::numeric,'Company demand reserves the shared warehouse pool');
set local role authenticated;
select is((select count(*)::integer from jsonb_array_elements(public.v1_inventory_register_page(p_register=>'reservations')->'reservations') r where r->>'request_id'='c3000000-0000-4000-8000-000000000010'),1,'Company reservation appears in the paged Inventory register');
select is(public.v1_save_company_material_supply_plan(
  jsonb_build_object('request_id','c3000000-0000-4000-8000-000000000010',
    'expected_version',3,'lines',jsonb_build_array(jsonb_build_object(
      'request_line_id','c3000000-0000-4000-8000-000000000011','decision','full',
      'source_kind','warehouse','inventory_item_id','c3000000-0000-4000-8000-000000000020',
      'external_supplier',null,'arranged_qty','2','expected_available_date',null,
      'follow_up_date',null,'reason',null))),
  'c3000000-0000-4000-8000-000000000031'),(select response from cmr_full_plan),
  'Supply-plan retry is idempotent');

select throws_ok($$select public.v1_cancel_company_material_request('c3000000-0000-4000-8000-000000000010',4,'Not needed',gen_random_uuid())$$,
'42501','V1_COMPANY_CANCEL_DENIED','Procurement cannot cancel another employee demand');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select lives_ok($$select public.v1_cancel_company_material_request('c3000000-0000-4000-8000-000000000010',4,'No longer needed','c3000000-0000-4000-8000-000000000080')$$,'Assigned Project Engineer approves cancellation before dispatch');
select is(public.v1_company_material_request_projection('c3000000-0000-4000-8000-000000000010')->>'can_dispatch','false','Cancelled demand cannot dispatch');
set local role postgres;
select is((select on_hand_qty from public.v1_inventory_balances where inventory_item_id='c3000000-0000-4000-8000-000000000020'),5::numeric,'Cancellation does not fabricate stock movement');
select is((select count(*)::integer from public.v1_inventory_reservations where request_kind='company' and request_id='c3000000-0000-4000-8000-000000000010' and state in ('active','partially_consumed')),0,'Cancellation atomically releases all Company reservations');
select is((select count(*)::integer from public.v1_company_material_supply_plans where request_id='c3000000-0000-4000-8000-000000000010' and is_current),0,'Historical plan retained but no longer current');
select is((select count(*)::integer from public.v1_company_material_supply_plans where request_id='c3000000-0000-4000-8000-000000000010'),1,'Cancellation preserves supply history');
select is((select count(*)::integer from public.v1_inventory_movements where source_entity_type='company_material_dispatch_line'),0,'Cancellation does not issue material');
select * from finish();rollback;

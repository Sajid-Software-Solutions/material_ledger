begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create function pg_temp.audit_actor(p_number int, p_role text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', '10000000-0000-4000-8000-' || lpad(p_number::text,12,'0'), 'role','authenticated','app_metadata',jsonb_build_object('role',p_role,'app_user_id','usr-local-' || replace(p_role,'_','-')))::text, true);
end $$;
create function pg_temp.audit_request(p_project uuid,p_scope uuid,p_item uuid,p_quantities numeric[]) returns uuid language plpgsql as $$
declare r uuid:=gen_random_uuid(); a uuid; arr_version int; q jsonb;
begin
  perform pg_temp.audit_actor(2,'site_engineer');
  select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'display_order',i,'source_kind','custom','item_description','Procurement audit stock','brand_origin','Audit','requested_qty',p_quantities[i]::text,'unit','Nos')) into q from generate_subscripts(p_quantities,1) i;
  perform public.v1_save_material_request_draft(jsonb_build_object('request_id',r,'expected_version',0,'project_id',p_project,'scope_id',p_scope,'title','Rollback-only procurement audit','timing','normal','lines',q));
  perform public.v1_submit_material_request(jsonb_build_object('request_id',r,'expected_version',1),gen_random_uuid());
  perform pg_temp.audit_actor(1,'project_engineer');
  perform public.v1_decide_material_request(jsonb_build_object('request_id',r,'expected_version',2,'decision','approved','reason',null),gen_random_uuid());
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_begin_arrangement(jsonb_build_object('request_id',r,'expected_version',(select record_version from public.v1_material_requests where id=r)),gen_random_uuid());
  select id,record_version into a,arr_version from public.v1_procurement_arrangements where request_id=r and status='working';
  select jsonb_agg(jsonb_build_object('arrangement_line_id',al.id,'source_kind','warehouse','inventory_item_id',p_item,'decision','full','arranged_qty',rl.requested_qty::text,'reason',null)) into q from public.v1_procurement_arrangement_lines al join public.v1_material_request_lines rl on rl.id=al.request_line_id where al.arrangement_id=a;
  perform public.v1_save_arrangement(jsonb_build_object('request_id',r,'arrangement_id',a,'expected_request_version',(select record_version from public.v1_material_requests where id=r),'expected_arrangement_version',arr_version,'lines',q),gen_random_uuid());
  return r;
end $$;
create temp table stock_targets(a uuid,b uuid,item uuid,payload jsonb,key uuid,company uuid,company_line uuid);
do $$
declare p uuid; s uuid; item uuid; a uuid; b uuid; d uuid; q jsonb; result jsonb; rejected boolean:=false;
begin
  perform pg_temp.audit_actor(1,'project_engineer');
  perform public.v1_create_project(jsonb_build_object('project_ref','AUDIT-'||substr(gen_random_uuid()::text,1,8),'name','Rollback-only Procurement Audit','parties','{}'::jsonb,'initial_members',jsonb_build_array(jsonb_build_object('auth_user_id','10000000-0000-4000-8000-000000000002','project_role','site_engineer','reason','Audit')),'buildings',jsonb_build_array(jsonb_build_object('code','audit','name','Audit Building')),'attachments','[]'::jsonb),gen_random_uuid());
  select id into p from public.v1_projects where name='Rollback-only Procurement Audit' order by created_at desc limit 1;
  perform public.v1_set_project_state(jsonb_build_object('project_id',p,'state','active','expected_version',1,'reason','Local rollback test'),gen_random_uuid());
  select id into s from public.v1_project_scopes where project_id=p and scope_kind='building' limit 1;
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('item_description','Procurement audit stock','brand_origin','Audit','unit','Nos','quantity_delta','8','reason','Local rollback test'),gen_random_uuid());
  select id into item from public.v1_inventory_items where item_description='Procurement audit stock' and brand_origin='Audit';
  a:=pg_temp.audit_request(p,s,item,array[4,4]::numeric[]);
  select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','4')) into q from public.v1_material_request_lines where request_id=a;
  perform public.v1_dispatch_materials(jsonb_build_object('request_id',a,'expected_version',(select record_version from public.v1_material_requests where id=a),'dispatch_date',current_date,'delivery_reference','AUDIT-FIRST','lines',q),gen_random_uuid());
  select id into d from public.v1_material_dispatches where request_id=a;
  select jsonb_agg(jsonb_build_object('dispatch_line_id',id,'outcome','missing','good_qty','0','note','Rollback audit missing fixture')) into q from public.v1_material_dispatch_lines where dispatch_id=d;
  perform pg_temp.audit_actor(2,'site_engineer');
  perform public.v1_confirm_receipt(jsonb_build_object('request_id',a,'dispatch_id',d,'expected_request_version',(select record_version from public.v1_material_requests where id=a),'expected_dispatch_version',(select record_version from public.v1_material_dispatches where id=d),'lines',q),gen_random_uuid());
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('inventory_item_id',item,'quantity_delta','6','reason','Local rollback replenishment'),gen_random_uuid());
  b:=pg_temp.audit_request(p,s,item,array[4]::numeric[]);
  select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','2')) into q from public.v1_material_request_lines where request_id=a;
  insert into stock_targets(a,b,item,payload,key) values(a,b,item,jsonb_build_object('request_id',a,
    'expected_version',(select record_version from public.v1_material_requests where id=a),
    'dispatch_date',current_date,'delivery_reference','AGGREGATE-TEST','lines',q),gen_random_uuid());
end $$;
grant select on stock_targets to authenticated;
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select ok((public.v1_material_request_projection(a)->>'dispatch_ready')::boolean,
  'Replacement demand after missing receipt appears ready for Procurement') from stock_targets;
select throws_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
  '22023','V1_DISPATCH_STOCK_CAP_EXCEEDED','Shared-stock replacement lines are capped in aggregate');
select pg_temp.audit_actor(2,'site_engineer');
select ok(not(public.v1_material_request_projection(a)->>'dispatch_ready')::boolean,
  'Site Engineer has no Procurement dispatch-ready authority') from stock_targets;
select throws_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
  '42501','V1_DISPATCH_DENIED','Site Engineer cannot bypass dispatch authority');
select pg_temp.audit_actor(1,'project_engineer');
select throws_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
  '42501','V1_DISPATCH_DENIED','Project Engineer cannot dispatch their own request');
reset role;
select is((select on_hand_qty from public.v1_inventory_balances where inventory_item_id=(select item from stock_targets)),
  6::numeric,'Rejected aggregate dispatch does not decrement stock');
select is((select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations where request_id=(select b from stock_targets)
 and state in ('active','partially_consumed')),4::numeric,'Competing Project reservation remains fully protected');

-- Add Company demand through the production supply-plan command. Its request
-- policy fixture is private to this rollback transaction.
insert into public.v1_company_material_request_categories(id,category_code,display_name)
values('af100000-0000-4000-8000-000000000001','aggregate_test','Aggregate test');
insert into public.v1_company_material_request_units(id,unit_code,display_name)
values('af100000-0000-4000-8000-000000000002','AGGREGATE_TEST','Aggregate test');
insert into public.v1_company_material_request_approval_routes(id,category_id,responsible_unit_id,primary_approver_auth_user_id,policy_version)
values('af100000-0000-4000-8000-000000000003','af100000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000002',
'10000000-0000-4000-8000-000000000001','aggregate-v1');
insert into public.v1_company_material_requests(id,request_number,state,record_version,category_id,responsible_unit_id,purpose,timing,
 delivery_collection_point,beneficiary_auth_user_id,beneficiary_display_name,authorized_receiver_auth_user_id,authorized_receiver_display_name,
 created_by_auth_user_id,requester_display_name,requester_exact_role,approval_route_id,approval_policy_version,approver_auth_user_id,approver_display_name,submitted_at)
values('af100000-0000-4000-8000-000000000010','CMR-AGGREGATE-TEST','approved_for_procurement',3,
 'af100000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000002','Aggregate test','normal','Workshop',
 '10000000-0000-4000-8000-000000000002','Site Engineer','10000000-0000-4000-8000-000000000002','Site Engineer',
 '10000000-0000-4000-8000-000000000002','Site Engineer','site_engineer','af100000-0000-4000-8000-000000000003','aggregate-v1',
 '10000000-0000-4000-8000-000000000001','Project Engineer',clock_timestamp());
insert into public.v1_company_material_request_lines(id,request_id,display_order,item_description,requested_qty,unit)
values('af100000-0000-4000-8000-000000000011','af100000-0000-4000-8000-000000000010',1,'Company aggregate test',3,'Nos');
select pg_temp.audit_actor(3,'procurement');
select public.v1_adjust_inventory(jsonb_build_object('inventory_item_id',item,'quantity_delta','3','reason','Company reservation fixture'),gen_random_uuid()) from stock_targets;
select public.v1_save_company_material_supply_plan(jsonb_build_object('request_id','af100000-0000-4000-8000-000000000010',
 'expected_version',3,'lines',jsonb_build_array(jsonb_build_object('request_line_id','af100000-0000-4000-8000-000000000011',
 'decision','full','source_kind','warehouse','inventory_item_id',item,'arranged_qty','3'))),gen_random_uuid()) from stock_targets;
update stock_targets set company='af100000-0000-4000-8000-000000000010',company_line=(select sl.id from public.v1_company_material_supply_lines sl
 join public.v1_company_material_supply_plans sp on sp.id=sl.plan_id where sp.request_id='af100000-0000-4000-8000-000000000010' and sp.is_current);
set local role authenticated;
select throws_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
 '22023','V1_DISPATCH_STOCK_CAP_EXCEEDED','Company and Project reservations share aggregate protection');
select throws_ok($$select public.v1_dispatch_company_materials(jsonb_build_object('request_id',company,'expected_version',4,
 'lines',jsonb_build_array(jsonb_build_object('supply_line_id',company_line,'dispatch_qty','2'),
 jsonb_build_object('supply_line_id',company_line,'dispatch_qty','2'))),gen_random_uuid()) from stock_targets$$,
 '22023','V1_COMPANY_DISPATCH_LINE_INVALID','Repeated Company supply lines cannot bypass cumulative approved cap');
reset role;
update stock_targets set payload=jsonb_set(payload,'{lines}',(select jsonb_agg(jsonb_build_object('request_line_id',value->>'request_line_id','dispatch_qty','1'))
 from jsonb_array_elements(payload->'lines')));
set local role authenticated;
select lives_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
 'Exact remaining free quantity can be dispatched across two replacement lines');
select lives_ok($$select public.v1_dispatch_materials(payload,key) from stock_targets$$,
 'Retry of confirmed aggregate dispatch is idempotent');
select throws_ok($$select public.v1_dispatch_materials(payload,gen_random_uuid()) from stock_targets$$,
 '40001','V1_DISPATCH_STATE_OR_VERSION_INVALID','Competing stale-version dispatcher cannot commit again');
reset role;
select is((select on_hand_qty from public.v1_inventory_balances where inventory_item_id=(select item from stock_targets)),
 7::numeric,'Idempotent aggregate dispatch decrements only two units once');
select is((select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations where inventory_item_id=(select item from stock_targets)
 and request_id<>(select a from stock_targets) and state in ('active','partially_consumed')),7::numeric,
 'Both other Project and Company reservations remain covered by on-hand stock');
select is((select count(*) from public.v1_material_dispatches where request_id=(select a from stock_targets)),2::bigint,
 'Only original and one replacement dispatch exist');
select * from finish();
rollback;

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
create temp table auto_do_targets(request_id uuid, dispatch_id uuid, ordinal integer, payload jsonb, command_key uuid);
do $$
declare p uuid; s uuid; item uuid; r uuid; d uuid; q jsonb; n integer;
begin
  perform pg_temp.audit_actor(1,'project_engineer');
  perform public.v1_create_project(jsonb_build_object('project_ref','AUTO-DO-TEST','name','Automatic delivery test','parties','{}'::jsonb,'initial_members',jsonb_build_array(jsonb_build_object('auth_user_id','10000000-0000-4000-8000-000000000002','project_role','site_engineer','reason','Test')),'buildings',jsonb_build_array(jsonb_build_object('code','auto','name','Auto Building')),'attachments','[]'::jsonb),gen_random_uuid());
  select id into p from public.v1_projects where project_ref='AUTO-DO-TEST';
  perform public.v1_set_project_state(jsonb_build_object('project_id',p,'state','active','expected_version',1,'reason','Local rollback test'),gen_random_uuid());
  select id into s from public.v1_project_scopes where project_id=p and scope_kind='building' limit 1;
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('item_description','Automatic DO stock','brand_origin','Test','unit','Nos','quantity_delta','8','reason','Local rollback test'),gen_random_uuid());
  select id into item from public.v1_inventory_items where item_description='Automatic DO stock' and brand_origin='Test';
  r:=pg_temp.audit_request(p,s,item,array[8]::numeric[]);
  select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','2')) into q from public.v1_material_request_lines where request_id=r;
  for n in 1..3 loop
    perform public.v1_dispatch_materials(jsonb_build_object('request_id',r,'expected_version',(select record_version from public.v1_material_requests where id=r),'dispatch_date',current_date,'delivery_reference',case when n=1 then 'SUPPLIER-ORIGINAL' else null end,'lines',q),gen_random_uuid());
    select id into d from public.v1_material_dispatches where request_id=r order by created_at desc limit 1;
    insert into auto_do_targets values(r,d,n,null,gen_random_uuid());
  end loop;
  update auto_do_targets t set payload=jsonb_build_object('request_id',r,'dispatch_id',t.dispatch_id,
    'expected_request_version',(select record_version from public.v1_material_requests where id=r),
    'expected_dispatch_version',(select record_version from public.v1_material_dispatches where id=t.dispatch_id));
end $$;
grant select on auto_do_targets to authenticated;
select ok((select relrowsecurity from pg_class where oid='public.v1_delivery_order_reference_counters'::regclass), 'DO counter enables RLS');
select ok(not has_table_privilege('authenticated','public.v1_delivery_order_reference_counters','SELECT,INSERT,UPDATE,DELETE'), 'DO counter is not directly available to authenticated users');
select ok(not has_table_privilege('anon','public.v1_delivery_order_reference_counters','SELECT,INSERT,UPDATE,DELETE'), 'DO counter is not available to anon');
select is((select delivery_reference from public.v1_material_dispatches where id=(select dispatch_id from auto_do_targets where ordinal=1)), 'SUPPLIER-ORIGINAL', 'Existing supplier delivery reference remains intact');
select is((select count(*)::integer from public.v1_material_dispatches where request_id=(select request_id from auto_do_targets limit 1) and delivery_reference is null),2,'Dispatch permits omitted supplier references');
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select lives_ok($$select public.v1_generate_delivery_order(payload||jsonb_build_object('delivery_order_reference','AUTO-DO-TEST-DO001'),command_key) from auto_do_targets where ordinal=1$$,'Retained clients can still provide an official reference');
select lives_ok($$select public.v1_generate_delivery_order(payload,command_key) from auto_do_targets where ordinal=2$$,'Procurement creates DO with no typed number');
reset role;
select is((select delivery_order_reference from public.v1_delivery_orders where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=2)), 'AUTO-DO-TEST-DO002', 'Automatic numbering skips the retained manual reference');
select is((select next_sequence from public.v1_delivery_order_reference_counters where project_id=(select project_id from public.v1_material_requests where id=(select request_id from auto_do_targets limit 1))),3,'Counter advances beyond the occupied number');
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select lives_ok($$select public.v1_generate_delivery_order(payload,command_key) from auto_do_targets where ordinal=2$$,'Same command retry returns the confirmed DO');
reset role;
select is((select count(*)::integer from public.v1_delivery_order_revisions where delivery_order_id=(select id from public.v1_delivery_orders where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=2))),1,'Retry creates no extra revision');
select is((select next_sequence from public.v1_delivery_order_reference_counters where project_id=(select project_id from public.v1_material_requests where id=(select request_id from auto_do_targets limit 1))),3,'Retry consumes no new number');
set local role authenticated;
select pg_temp.audit_actor(1,'project_engineer');
select lives_ok($$select public.v1_generate_delivery_order(payload,gen_random_uuid()) from auto_do_targets where ordinal=2$$,'Assigned Project Engineer can create a revision without retyping the number');
select pg_temp.audit_actor(2,'site_engineer');
select lives_ok($$select public.v1_generate_delivery_order(payload,gen_random_uuid()) from auto_do_targets where ordinal=1$$,'Assigned Site Engineer reuses a retained manual number');
select throws_ok($$select public.v1_generate_delivery_order(payload||jsonb_build_object('delivery_order_reference','RENAMED'),gen_random_uuid()) from auto_do_targets where ordinal=1$$,'22023','V1_DELIVERY_ORDER_REFERENCE_IMMUTABLE','A retained reference cannot be overwritten');
select pg_temp.audit_actor(4,'admin');
select lives_ok($$select public.v1_generate_delivery_order(payload,command_key) from auto_do_targets where ordinal=3$$,'Admin creates next automatic DO');
reset role;
select is((select delivery_order_reference from public.v1_delivery_orders where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=1)), 'AUTO-DO-TEST-DO001', 'Manual reference stays unchanged through revision');
select is((select delivery_order_reference from public.v1_delivery_orders where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=2)), 'AUTO-DO-TEST-DO002', 'Automatic reference stays unchanged through revision');
select is((select delivery_order_reference from public.v1_delivery_orders where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=3)), 'AUTO-DO-TEST-DO003', 'Next dispatch gets a distinct reference');
select is((select sum(dispatched_qty) from public.v1_material_dispatch_lines where dispatch_id=(select dispatch_id from auto_do_targets where ordinal=2)),2::numeric,'DO generation and revisions do not alter dispatched stock');
select ok(position('v1_assert_prepared_procurement_command' in pg_get_functiondef('public.v1_dispatch_materials(jsonb,uuid)'::regprocedure))>0, 'Prepared dispatch fencing remains installed');
select ok(position('request_line.technical_attributes' in pg_get_functiondef('public.v1_generate_delivery_order(jsonb,uuid)'::regprocedure))>0, 'DO item metadata hardening remains installed');
-- Authenticated readers never acquire counter authority. Revoked project
-- membership also remains a hard document-command denial.
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select throws_ok($$select * from public.v1_delivery_order_reference_counters$$,'42501','permission denied for table v1_delivery_order_reference_counters','Procurement cannot query the number allocator directly');
reset role;
update public.v1_project_members set effective_to=clock_timestamp(), revoked_by_auth_user_id='10000000-0000-4000-8000-000000000004', revoked_by_role='admin', revoked_reason='Test revocation'
where project_id=(select project_id from public.v1_material_requests where id=(select request_id from auto_do_targets limit 1))
  and member_auth_user_id='10000000-0000-4000-8000-000000000002' and effective_to is null;
set local role authenticated;
select pg_temp.audit_actor(2,'site_engineer');
select throws_ok($$select public.v1_generate_delivery_order(payload,gen_random_uuid()) from auto_do_targets where ordinal=1$$,'42501','V1_DELIVERY_ORDER_GENERATE_DENIED','Revoked Site Engineer cannot use automatic numbering to generate a document');
reset role;
select * from finish();
rollback;

\set ON_ERROR_STOP on
begin;
set local search_path=public,extensions;
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
  raise notice 'BEFORE: on_hand=%, other_request_reserved=%', (select on_hand_qty from public.v1_inventory_balances where inventory_item_id=item), (select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations where request_id=b and state in ('active','partially_consumed'));
  select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','2')) into q from public.v1_material_request_lines where request_id=a;
  begin
    result:=public.v1_dispatch_materials(jsonb_build_object('request_id',a,'expected_version',(select record_version from public.v1_material_requests where id=a),'dispatch_date',current_date,'delivery_reference','AUDIT-REPLACEMENT','lines',q),gen_random_uuid());
  exception when sqlstate '22023' then
    rejected:=true;
    raise notice 'REJECTED: %',sqlerrm;
  end;
  raise notice 'AFTER: rejected=%, on_hand=%, other_request_reserved=%', rejected, (select on_hand_qty from public.v1_inventory_balances where inventory_item_id=item), (select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations where request_id=b and state in ('active','partially_consumed'));
end $$;
rollback;

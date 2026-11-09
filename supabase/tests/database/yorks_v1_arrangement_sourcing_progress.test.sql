begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create function pg_temp.audit_actor(p_number int, p_role text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', '10000000-0000-4000-8000-' || lpad(p_number::text,12,'0'), 'role','authenticated','app_metadata',jsonb_build_object('role',p_role,'app_user_id','usr-local-' || replace(p_role,'_','-')))::text, true);
end $$;
create function pg_temp.audit_request(p_project uuid,p_scope uuid,p_item uuid,p_quantities numeric[],p_finish boolean default true) returns uuid language plpgsql as $$
declare r uuid:=gen_random_uuid(); a uuid; arr_version int; q jsonb;
begin
  perform pg_temp.audit_actor(2,'site_engineer');
  select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'display_order',i,'source_kind','custom','item_description','Procurement audit stock','brand_origin','Audit','requested_qty',p_quantities[i]::text,'unit','Nos')) into q from generate_subscripts(p_quantities,1) i;
  perform public.v1_save_material_request_draft(jsonb_build_object('request_id',r,'expected_version',0,'project_id',p_project,'scope_id',p_scope,'title','Rollback-only procurement audit','timing','scheduled','scheduled_date',(current_date+7)::text,'lines',q));
  perform public.v1_submit_material_request(jsonb_build_object('request_id',r,'expected_version',1),gen_random_uuid());
  perform pg_temp.audit_actor(1,'project_engineer');
  perform public.v1_decide_material_request(jsonb_build_object('request_id',r,'expected_version',2,'decision','approved','reason',null),gen_random_uuid());
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_begin_arrangement(jsonb_build_object('request_id',r,'expected_version',(select record_version from public.v1_material_requests where id=r)),gen_random_uuid());
  select id,record_version into a,arr_version from public.v1_procurement_arrangements where request_id=r and status='working';
  select jsonb_agg(jsonb_build_object('arrangement_line_id',al.id,'source_kind','warehouse','inventory_item_id',p_item,'decision','full','arranged_qty',rl.requested_qty::text,'reason',null)) into q from public.v1_procurement_arrangement_lines al join public.v1_material_request_lines rl on rl.id=al.request_line_id where al.arrangement_id=a;
  if p_finish then perform public.v1_save_arrangement(jsonb_build_object('request_id',r,'arrangement_id',a,'expected_request_version',(select record_version from public.v1_material_requests where id=r),'expected_arrangement_version',arr_version,'lines',q),gen_random_uuid()); end if;
  return r;
end $$;

create temp table progress_targets(request_id uuid,arrangement_id uuid,line_id uuid,request_version int,arrangement_version int);
do $$ declare p uuid; s uuid; item uuid; r uuid; begin
  perform pg_temp.audit_actor(1,'project_engineer');
  perform public.v1_create_project(jsonb_build_object('project_ref','SOURCING-TEST','name','Shared Sourcing Test','parties','{}'::jsonb,'initial_members',jsonb_build_array(jsonb_build_object('auth_user_id','10000000-0000-4000-8000-000000000002','project_role','site_engineer','reason','Test')),'buildings',jsonb_build_array(jsonb_build_object('code','p','name','Progress Building')),'attachments','[]'::jsonb),gen_random_uuid());
  select id into p from public.v1_projects where project_ref='SOURCING-TEST';
  perform public.v1_set_project_state(jsonb_build_object('project_id',p,'state','active','expected_version',1,'reason','Test'),gen_random_uuid());
  select id into s from public.v1_project_scopes where project_id=p and scope_kind='building' limit 1;
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('item_description','Sourcing test stock','unit','Nos','quantity_delta','8','reason','Test'),gen_random_uuid());
  select id into item from public.v1_inventory_items where item_description='Sourcing test stock';
  r:=pg_temp.audit_request(p,s,item,array[4,4]::numeric[],false);
  insert into progress_targets select r,a.id,l.id,m.record_version,a.record_version from public.v1_material_requests m
    join public.v1_procurement_arrangements a on a.request_id=m.id and a.status='working'
    join public.v1_procurement_arrangement_lines l on l.arrangement_id=a.id where m.id=r;
end $$;
grant select on progress_targets to authenticated;
create function pg_temp.sourcing_payload(p_revision int default 0,p_qty text default '2',p_source text default 'external_supplier')
returns jsonb language sql security definer as $$
  select jsonb_build_object('request_id',t.request_id,'arrangement_id',t.arrangement_id,
    'expected_request_version',request_version,'expected_arrangement_version',arrangement_version,'expected_revision',p_revision,
    'lines',jsonb_agg(jsonb_build_object('request_line_id',al.request_line_id,'ready_qty',p_qty,
      'source_kind',p_source,'inventory_item_id',case when p_source='warehouse' then
        (select id from public.v1_inventory_items where item_description='Sourcing test stock') else null end,
      'expected_available_date',(current_date+2)::text) order by al.id))
  from progress_targets t join public.v1_procurement_arrangement_lines al on al.id=t.line_id
  group by t.request_id,t.arrangement_id,request_version,arrangement_version;
$$;
create function pg_temp.sourcing_final_payload() returns jsonb language sql security definer as $$
  select jsonb_build_object('request_id',t.request_id,'arrangement_id',t.arrangement_id,
    'expected_request_version',request_version,'expected_arrangement_version',arrangement_version,'lines',
    jsonb_agg(jsonb_build_object('arrangement_line_id',line_id,'source_kind','external_supplier','decision','full',
      'arranged_qty','4','external_source_ready',true) order by line_id))
  from progress_targets t group by t.request_id,t.arrangement_id,request_version,arrangement_version;
$$;
select ok((select relrowsecurity from pg_class where oid='public.v1_arrangement_sourcing_revisions'::regclass),'Sourcing revisions enable RLS');
select ok(not has_table_privilege('authenticated','public.v1_arrangement_sourcing_revisions','select')
 and not has_table_privilege('authenticated','public.v1_arrangement_sourcing_revisions','insert')
 and not has_table_privilege('anon','public.v1_arrangement_sourcing_revisions','select'),'No direct API table access');
select ok(not has_function_privilege('anon','public.v1_get_arrangement_sourcing_progress(uuid,uuid)','execute')
 and not has_function_privilege('anon','public.v1_save_arrangement_sourcing_progress(jsonb,uuid)','execute'),'Anonymous RPC access denied');
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select is(public.v1_get_arrangement_sourcing_progress(request_id),null::jsonb,'No shared progress before explicit publication') from progress_targets limit 1;
select is(public.v1_arrangement_projection(request_id)->>'timing','scheduled','Workspace exposes request timing') from progress_targets limit 1;
select is(public.v1_arrangement_projection(request_id)->>'scheduled_date',(current_date+7)::text,'Workspace exposes scheduled date') from progress_targets limit 1;
select is((public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(),'b5000000-0000-4000-8000-000000000001')->>'revision')::int,1,'Procurement publishes validated progress');
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'partial_line_count')::int,2,'Partial counts use lines rather than sum of unlike units') from progress_targets limit 1;
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'ready_line_count')::int,0,'Future expected date does not make any line ready') from progress_targets limit 1;
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'is_current')::boolean,true,'Live matching base is current') from progress_targets limit 1;
select is((public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(),'b5000000-0000-4000-8000-000000000001')->>'revision')::int,1,'Identical retry never adds another revision');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(),gen_random_uuid())$$,
 '40001','V1_ARRANGEMENT_SOURCING_REVISION_CONFLICT','Stale simultaneous revision is rejected');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(jsonb_set(pg_temp.sourcing_payload(1),'{expected_request_version}','999'),gen_random_uuid())$$,
 '40001','V1_ARRANGEMENT_SOURCING_BASE_CONFLICT','Request base cannot silently drift');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1,'-1'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID','Negative ready quantity rejected');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1,'4.00001'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID','Ready quantity cannot round past precision');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1,'5'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID','Ready quantity cannot exceed request');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1,'NaN'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID','Non-finite quantity rejected');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(jsonb_set(pg_temp.sourcing_payload(1),'{lines,0,unit_cost}','"99"'),gen_random_uuid())$$,
 '22023',null,'Commercial input rejected from shared facts');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(jsonb_set(pg_temp.sourcing_payload(1),'{lines,0,request_line_id}','"00000000-0000-4000-8000-000000000001"'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_LINES_INVALID','Cross-request line rejected');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(jsonb_set(pg_temp.sourcing_payload(1),'{lines}',(pg_temp.sourcing_payload(1)->'lines')-0),gen_random_uuid())$$,
 '22023',null,'Missing lines cannot silently disappear');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(jsonb_set(pg_temp.sourcing_payload(1),'{lines,0,expected_available_date}','"2026-02-31"'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_DATE_INVALID','Invalid real calendar date rejected');
select pg_temp.audit_actor(1,'project_engineer');
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'revision')::int,1,'Assigned Project Engineer can see shared progress') from progress_targets limit 1;
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1),gen_random_uuid())$$,
 '42501','V1_ARRANGEMENT_SOURCING_DENIED','Project Engineer cannot change Procurement readiness');
select pg_temp.audit_actor(2,'site_engineer');
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'revision')::int,1,'Assigned Site Engineer can see shared progress') from progress_targets limit 1;
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1),gen_random_uuid())$$,
 '42501','V1_ARRANGEMENT_SOURCING_DENIED','Site Engineer cannot change Procurement readiness');
select pg_temp.audit_actor(13,'accountant');
select throws_ok($$select public.v1_get_arrangement_sourcing_progress(request_id) from progress_targets limit 1$$,
 '42501','V1_ARRANGEMENT_SOURCING_DENIED','Accountant cannot read technical progress');
select pg_temp.audit_actor(4,'admin');
select is((public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(1,'0'),gen_random_uuid())->>'waiting_line_count')::int,2,'Authorized Admin can correct readiness with a new revision');
reset role;
select is((select count(*) from public.v1_arrangement_sourcing_revisions s where s.request_id=(select request_id from progress_targets limit 1)),2::bigint,'Correction retains earlier sourcing revision');
select throws_ok($$update public.v1_arrangement_sourcing_revisions set lines='[]'::jsonb$$,
 '42501','V1_ARRANGEMENT_SOURCING_HISTORY_IMMUTABLE','Sourcing history cannot be rewritten');
select is((select count(*) from public.v1_inventory_reservations where request_id=(select request_id from progress_targets limit 1)),0::bigint,'Publication makes no stock reservation');
select is((select count(*) from public.v1_procurement_progress where request_id=(select request_id from progress_targets limit 1)),0::bigint,'Publication never copies or writes owner-private checkpoints');
select is((select state from public.v1_material_requests where id=(select request_id from progress_targets limit 1)),'arranging','Publication never finalizes the arrangement');
select is((select count(*) from public.v1_notifications where entity_id=(select arrangement_id from progress_targets limit 1)),0::bigint,'Progress updates do not spam team notifications');
update public.v1_inventory_balances set on_hand_qty=3 where inventory_item_id=(select id from public.v1_inventory_items where item_description='Sourcing test stock');
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(2,'2','warehouse'),gen_random_uuid())$$,
 '22023','V1_ARRANGEMENT_SOURCING_STOCK_CHANGED','Combined warehouse ready quantities cannot exceed current stock');
select is((public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(2,'1','warehouse'),gen_random_uuid())->>'revision')::int,3,'Valid observed warehouse quantities can be shared');
reset role;
update public.v1_material_requests set record_version=record_version+1 where id=(select request_id from progress_targets limit 1);
set local role authenticated;
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'is_current')::boolean,false,'Edited request makes prior sourcing explicitly stale') from progress_targets limit 1;
reset role;
update public.v1_material_requests set record_version=record_version-1 where id=(select request_id from progress_targets limit 1);
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.v1_get_arrangement_sourcing_progress(request_id) from progress_targets limit 1$$,
 '42501','V1_ARRANGEMENT_SOURCING_DENIED','Revoked actor cannot keep reading progress');
reset role;
update public.v1_profiles set is_active=true where auth_user_id='10000000-0000-4000-8000-000000000003';
update public.v1_projects set state='archived' where id=(select project_id from public.v1_material_requests where id=(select request_id from progress_targets limit 1));
set local role authenticated;
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(3),gen_random_uuid())$$,
 '42501','V1_ARRANGEMENT_SOURCING_DENIED','Archived project blocks sourcing updates');
reset role;
update public.v1_projects set state='active' where id=(select project_id from public.v1_material_requests where id=(select request_id from progress_targets limit 1));
set local role authenticated;
select throws_ok($$select public.v1_save_arrangement(jsonb_set(pg_temp.sourcing_final_payload(),'{lines,0,external_source_ready}','false'),gen_random_uuid())$$,
 '22023','V1_EXTERNAL_SOURCE_READINESS_REQUIRED','Scheduled completion requires actual external readiness even when adoption policy is optional');
select lives_ok($$select public.v1_save_arrangement(pg_temp.sourcing_final_payload(),'b5000000-0000-4000-8000-000000000002')$$,'Final completion continues through existing arrangement command');
select is((public.v1_get_arrangement_sourcing_progress(request_id)->>'is_current')::boolean,false,'Final arrangement replaces shared preparation facts') from progress_targets limit 1;
select throws_ok($$select public.v1_save_arrangement_sourcing_progress(pg_temp.sourcing_payload(3),gen_random_uuid())$$,
 '55000','V1_ARRANGEMENT_SOURCING_STATE_INVALID','Final arrangement cannot be edited by a progress RPC');
select lives_ok($$select public.v1_save_arrangement(pg_temp.sourcing_final_payload(),'b5000000-0000-4000-8000-000000000002')$$,'Final completion retry stays idempotent');
reset role;
select is((select count(*) from public.v1_notifications where entity_id=(select arrangement_id from progress_targets limit 1)
 and event_code='arrangement_preparation_completed' and recipient_auth_user_id='10000000-0000-4000-8000-000000000001'),1::bigint,'Project Engineer receives exactly one completion alert');
select is((select count(*) from public.v1_notifications where entity_id=(select arrangement_id from progress_targets limit 1)
 and event_code='arrangement_preparation_completed' and recipient_auth_user_id='10000000-0000-4000-8000-000000000002'),1::bigint,'Site Engineer requester receives exactly one completion alert');
select is((select count(*) from public.v1_notifications where entity_id=(select arrangement_id from progress_targets limit 1)
 and event_code='arrangement_preparation_completed' and recipient_auth_user_id='10000000-0000-4000-8000-000000000013'),0::bigint,'Accountant is not subscribed to technical completion');
select ok(not coalesce((public.v1_permission_authoritative_resolution(
 '10000000-0000-4000-8000-000000000001','dispatch.create',
 (select project_id from public.v1_material_requests where id=(select request_id from progress_targets limit 1)))->>'effective')::boolean,false),
 'Project Engineer remains unable to dispatch');
select ok(not coalesce((public.v1_permission_authoritative_resolution(
 '10000000-0000-4000-8000-000000000002','dispatch.create',
 (select project_id from public.v1_material_requests where id=(select request_id from progress_targets limit 1)))->>'effective')::boolean,false),
 'Site Engineer remains unable to dispatch');
select ok((select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000001'),
 'Project Engineer completion push is eligible without dispatch permission');
select ok((select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000002'),
 'Site Engineer completion push is eligible without dispatch permission');
select is((select count(*) from public.v1_notification_push_outbox o join public.v1_notifications n on n.id=o.notification_id
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id in ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002')),
 2::bigint,'Completion inserts one transport outbox entry for each Engineering recipient');
update public.v1_project_members set effective_to=clock_timestamp(),
 revoked_by_auth_user_id='10000000-0000-4000-8000-000000000004', revoked_by_role='admin',
 revoked_reason='Test revocation'
 where project_id=(select project_id from public.v1_material_requests where id=(select request_id from progress_targets limit 1))
 and member_auth_user_id='10000000-0000-4000-8000-000000000001';
select ok(not (select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000001'),
 'Removed Engineering membership suppresses queued completion push');
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000002';
select ok(not (select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000002'),
 'Inactive recipient suppresses queued completion push');
update public.v1_profiles set is_active=true where auth_user_id='10000000-0000-4000-8000-000000000002';
update public.v1_procurement_arrangements set is_current=false where id=(select arrangement_id from progress_targets limit 1);
select ok(not (select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000002'),
 'Superseded arrangement suppresses queued completion push');
update public.v1_procurement_arrangements set is_current=true where id=(select arrangement_id from progress_targets limit 1);
update public.v1_material_requests set state='cancelled',cancelled_at=clock_timestamp(),
 cancelled_by_auth_user_id='10000000-0000-4000-8000-000000000004',cancellation_reason='Test cancelled request'
 where id=(select request_id from progress_targets limit 1);
select ok(not (select public.v1_push_notification_entity_allowed(n) from public.v1_notifications n
 where n.entity_id=(select arrangement_id from progress_targets limit 1) and n.event_code='arrangement_preparation_completed'
 and n.recipient_auth_user_id='10000000-0000-4000-8000-000000000002'),
 'Cancelled request suppresses queued completion push');
select * from finish();
rollback;

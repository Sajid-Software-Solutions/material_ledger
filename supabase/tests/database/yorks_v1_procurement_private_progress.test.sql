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
  perform public.v1_save_material_request_draft(jsonb_build_object('request_id',r,'expected_version',0,'project_id',p_project,'scope_id',p_scope,'title','Rollback-only procurement audit','timing','normal','lines',q));
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
  perform public.v1_create_project(jsonb_build_object('project_ref','PROGRESS-TEST','name','Private Progress Test','parties','{}'::jsonb,'initial_members',jsonb_build_array(jsonb_build_object('auth_user_id','10000000-0000-4000-8000-000000000002','project_role','site_engineer','reason','Test')),'buildings',jsonb_build_array(jsonb_build_object('code','p','name','Progress Building')),'attachments','[]'::jsonb),gen_random_uuid());
  select id into p from public.v1_projects where project_ref='PROGRESS-TEST';
  perform public.v1_set_project_state(jsonb_build_object('project_id',p,'state','active','expected_version',1,'reason','Test'),gen_random_uuid());
  select id into s from public.v1_project_scopes where project_id=p and scope_kind='building' limit 1;
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('item_description','Progress test stock','unit','Nos','quantity_delta','8','reason','Test'),gen_random_uuid());
  select id into item from public.v1_inventory_items where item_description='Progress test stock';
  r:=pg_temp.audit_request(p,s,item,array[4]::numeric[],false);
  insert into progress_targets select r,a.id,l.id,m.record_version,a.record_version from public.v1_material_requests m
    join public.v1_procurement_arrangements a on a.request_id=m.id and a.status='working'
    join public.v1_procurement_arrangement_lines l on l.arrangement_id=a.id where m.id=r;
end $$;
grant select on progress_targets to authenticated;
create function pg_temp.progress_payload(p_revision int default 0) returns jsonb language sql as $$
  select jsonb_build_object('request_id',request_id,'editor_kind','arrangement','arrangement_id',arrangement_id,
    'expected_revision',p_revision,'base_request_version',request_version,'base_arrangement_version',arrangement_version,
    'schema_version',1,'inputs',jsonb_build_object('note','  raw note  ','lines',jsonb_build_array(jsonb_build_object(
      'arrangement_line_id',line_id,'decision','partial','source_kind','','inventory_item_id','','arranged_qty','1.',
      'reason','','external_supplier','','external_ready',false,'expected_available_date','20','external_reference',''))),
    'commercial_inputs',jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('arrangement_line_id',line_id,'unit_cost','12.'))))
  from progress_targets;
$$;
create function pg_temp.final_payload() returns jsonb language sql as $$
  select jsonb_build_object('request_id',request_id,'arrangement_id',arrangement_id,'expected_request_version',request_version,
    'expected_arrangement_version',arrangement_version,'procurement_note','Final note','lines',jsonb_build_array(jsonb_build_object(
      'arrangement_line_id',line_id,'decision','full','source_kind','external_supplier','external_supplier','Supplier',
      'arranged_qty','4','reason',null,'unit_cost','12','external_source_ready',true))) from progress_targets;
$$;
create function pg_temp.prepare_payload(p_key uuid) returns jsonb language sql as $$
  select jsonb_build_object('request_id',request_id,'editor_kind','arrangement','arrangement_id',arrangement_id,
    'checkpoint_revision',1,'command_name','v1_save_arrangement','command_key',p_key,'command_payload',pg_temp.final_payload())
  from progress_targets;
$$;
select ok((select bool_and(relrowsecurity) from pg_class where oid in
 ('public.v1_procurement_progress'::regclass,'public.v1_procurement_progress_commercials'::regclass,
  'public.v1_procurement_command_intents'::regclass)), 'Private relations all enable RLS');
select ok(not has_table_privilege('authenticated','public.v1_procurement_progress','select')
  and not has_table_privilege('authenticated','public.v1_procurement_progress_commercials','insert')
  and not has_table_privilege('authenticated','public.v1_procurement_command_intents','update'),
  'No direct API read or mutation bypass');
select ok(not has_function_privilege('anon','public.v1_get_procurement_progress(uuid,text,uuid)','execute'),
  'Anonymous checkpoint reads denied');
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id),null::jsonb,'Absent checkpoint is null') from progress_targets;
select is((public.v1_save_procurement_progress(pg_temp.progress_payload(),'af000000-0000-4000-8000-000000000001')->>'revision')::int,1,
  'Procurement can checkpoint incomplete raw input');
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id)#>>'{inputs,lines,0,arranged_qty}','1.',
 'Trailing decimal is retained exactly') from progress_targets;
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id)#>>'{commercial_inputs,lines,0,unit_cost}','12.',
 'Authorized incomplete cost has protected account recovery') from progress_targets;
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id)#>>'{inputs,note}','  raw note  ',
 'Meaningful raw whitespace is preserved') from progress_targets;
select is((public.v1_save_procurement_progress(pg_temp.progress_payload(),'af000000-0000-4000-8000-000000000001')->>'revision')::int,1,
 'Same checkpoint command retry does not bump revision');
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(),'af000000-0000-4000-8000-000000000002')$$,
 '40001','V1_PROCUREMENT_PROGRESS_REVISION_CONFLICT','Competing stale checkpoint write rejected');
select throws_ok($$select public.v1_save_procurement_progress(jsonb_set(pg_temp.progress_payload(1),'{base_request_version}','999'),gen_random_uuid())$$,
 '40001','V1_PROCUREMENT_PROGRESS_BASE_CONFLICT','Stale live request base rejected');
select throws_ok($$select public.v1_save_procurement_progress(jsonb_set(pg_temp.progress_payload(1),'{inputs,lines,0,arrangement_line_id}','"00000000-0000-4000-8000-000000000001"'),gen_random_uuid())$$,
 '22023','V1_PROCUREMENT_PROGRESS_LINE_ID_INVALID','Foreign line identity rejected');
select throws_ok($$select public.v1_save_procurement_progress(jsonb_set(pg_temp.progress_payload(1),'{inputs,unit_cost}','"secret"'),gen_random_uuid())$$,
 '22023',null,'Commercial keys cannot enter technical recovery');
select pg_temp.audit_actor(1,'project_engineer');
select throws_ok($$select public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id) from progress_targets$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Project Engineer cannot read Procurement checkpoint');
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(),gen_random_uuid())$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Project Engineer cannot write checkpoint');
select pg_temp.audit_actor(2,'site_engineer');
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(),gen_random_uuid())$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Site Engineer cannot write checkpoint');
select pg_temp.audit_actor(4,'admin');
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id),null::jsonb,
 'Admin cannot read another owner private checkpoint') from progress_targets;
select lives_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(),gen_random_uuid())$$,
 'Admin can save its own independent private checkpoint');
select pg_temp.audit_actor(3,'procurement');
select is(public.v1_prepare_procurement_command(pg_temp.prepare_payload('af000000-0000-4000-8000-000000000003'),
 'af000000-0000-4000-8000-000000000004')->>'status','prepared','Final intent can be protected before final command');
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id)#>>'{pending_command,command_key}',
 'af000000-0000-4000-8000-000000000003','Pending command can be discovered on a fresh device') from progress_targets;
select is(public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000003')->>'status',
 'prepared','Unsubmitted prepared command is distinguishable from confirmed') from progress_targets;
select is(public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000003')->'command_payload',
 pg_temp.final_payload(),'Authorized exact immutable payload can be retried') from progress_targets;
reset role;
insert into public.v1_user_capabilities(auth_user_id,capability,is_granted,reason)
values('10000000-0000-4000-8000-000000000003','view_commercials',false,'Revocation test')
on conflict(auth_user_id,capability) do update set is_granted=false;
set local role authenticated;
select ok(not(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id) ? 'commercial_inputs'),
 'Revoked commercial access removes the entire commercial response key') from progress_targets;
select is(public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000003')->>'status',
 'access_changed','Revoked commercial access cannot retrieve a frozen cost payload') from progress_targets;
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(1),gen_random_uuid())$$,
 '42501','V1_PROCUREMENT_PROGRESS_COMMERCIAL_DENIED','Revoked commercial management cannot save costs');
reset role;
delete from public.v1_user_capabilities where auth_user_id='10000000-0000-4000-8000-000000000003' and capability='view_commercials';
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id) from progress_targets$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Actor revocation immediately blocks protected recovery');
reset role;
update public.v1_profiles set is_active=true where auth_user_id='10000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.progress_payload(1),gen_random_uuid())$$,
 '55000','V1_PROCUREMENT_COMMAND_UNRESOLVED','Unresolved final intent cannot be overwritten by progress edits');
select throws_ok($$select public.v1_save_arrangement(jsonb_set(pg_temp.final_payload(),'{procurement_note}','"changed"'),
 'af000000-0000-4000-8000-000000000003')$$,'40001','V1_PROCUREMENT_COMMAND_INTENT_CHANGED','Changed frozen final payload rejected');
select is(public.v1_abandon_procurement_command(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000003')->>'status',
 'abandoned','Explicit edit-again safely abandons an uncommitted intent') from progress_targets;
select throws_ok($$select public.v1_save_arrangement(pg_temp.final_payload(),'af000000-0000-4000-8000-000000000003')$$,
 '40001','V1_PROCUREMENT_COMMAND_INTENT_CHANGED','Delayed final command cannot commit after abandon');
select lives_ok($$select public.v1_prepare_procurement_command(pg_temp.prepare_payload('af000000-0000-4000-8000-000000000005'),gen_random_uuid())$$,
 'A new final command can be prepared after safe abandon');
select lives_ok($$select public.v1_save_arrangement(pg_temp.final_payload(),'af000000-0000-4000-8000-000000000005')$$,
 'Prepared exact arrangement commits through existing protected workflow');
select is(public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000005')->>'status',
 'confirmed','Arrangement phase3 command result is reconciled by original key') from progress_targets;
select ok(not(public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000005') ? 'command_payload'),
 'Confirmed outcome returns fresh authorized workspace, not old payload') from progress_targets;
select is(public.v1_abandon_procurement_command(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000005')->>'status',
 'confirmed','Confirmed stock/workflow effect cannot be abandoned') from progress_targets;
select is((public.v1_discard_procurement_progress(jsonb_build_object('request_id',request_id,'editor_kind','arrangement',
 'arrangement_id',arrangement_id,'expected_revision',1),gen_random_uuid())->>'revision')::int,2,
 'Confirmed checkpoint retires without deleting workflow history') from progress_targets;
select is(public.v1_get_procurement_progress(request_id,'arrangement',arrangement_id)->'inputs','{}'::jsonb,
 'Retired checkpoint leaves only a revision tombstone') from progress_targets;
select pg_temp.audit_actor(2,'site_engineer');
select throws_ok($$select public.v1_get_procurement_command_outcome(request_id,'v1_save_arrangement','af000000-0000-4000-8000-000000000005') from progress_targets$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Engineering cannot read protected pending/confirmed outcome');
reset role;
select is((select count(*) from public.v1_inventory_reservations r join progress_targets t on t.request_id=r.request_id),0::bigint,
 'Incomplete checkpoints and external final source do not reserve warehouse stock');

create temp table dispatch_progress_target as select t.request_id,m.record_version,l.id as line_id
 from progress_targets t join public.v1_material_requests m on m.id=t.request_id
 join public.v1_material_request_lines l on l.request_id=t.request_id;
grant select on dispatch_progress_target to authenticated;
create function pg_temp.dispatch_progress_payload() returns jsonb language sql as $$
 select jsonb_build_object('request_id',request_id,'editor_kind','dispatch','arrangement_id',null,'expected_revision',0,
 'base_request_version',record_version,'base_arrangement_version',null,'schema_version',1,'inputs',jsonb_build_object(
 'dispatch_date','2026-','delivery_reference','','driver_name','  driver ','vehicle_reference','',
 'lines',jsonb_build_array(jsonb_build_object('request_line_id',line_id,'dispatch_qty','-')))) from dispatch_progress_target;
$$;
create function pg_temp.dispatch_final_payload() returns jsonb language sql as $$
 select jsonb_build_object('request_id',request_id,'expected_version',record_version,'dispatch_date',current_date,
 'delivery_reference','PROGRESS-DISPATCH','lines',jsonb_build_array(jsonb_build_object('request_line_id',line_id,'dispatch_qty','4')))
 from dispatch_progress_target;
$$;
select pg_temp.audit_actor(3,'procurement');
set local role authenticated;
select lives_ok($$select public.v1_save_procurement_progress(pg_temp.dispatch_progress_payload(),gen_random_uuid())$$,
 'Dispatch progress accepts unfinished reference, date and decimal text');
select is(public.v1_get_procurement_progress(request_id,'dispatch',null)#>>'{inputs,lines,0,dispatch_qty}','-',
 'Dispatch incomplete quantity survives without being silently interpreted') from dispatch_progress_target;
select throws_ok($$select public.v1_save_procurement_progress(pg_temp.dispatch_progress_payload()||jsonb_build_object('commercial_inputs',jsonb_build_object('lines','[]'::jsonb)),gen_random_uuid())$$,
 '42501','V1_PROCUREMENT_PROGRESS_COMMERCIAL_DENIED','Dispatch checkpoint never accepts costs');
select lives_ok($$select public.v1_prepare_procurement_command(jsonb_build_object('request_id',request_id,'editor_kind','dispatch',
 'arrangement_id',null,'checkpoint_revision',1,'command_name','v1_dispatch_materials',
 'command_key','af000000-0000-4000-8000-000000000006','command_payload',pg_temp.dispatch_final_payload()),gen_random_uuid())
 from dispatch_progress_target$$,'Dispatch final manifest can be protected before transaction');
select lives_ok($$select public.v1_dispatch_materials(pg_temp.dispatch_final_payload(),'af000000-0000-4000-8000-000000000006')$$,
 'Prepared dispatch commits normally');
select is(public.v1_get_procurement_command_outcome(request_id,'v1_dispatch_materials','af000000-0000-4000-8000-000000000006')->>'status',
 'confirmed','Dispatch ambiguous response reconciles by original command identity') from dispatch_progress_target;
select ok(not(public.v1_material_request_projection(request_id)->>'dispatch_ready')::boolean,
 'Entire approved quantity in transit is not counted ready again') from dispatch_progress_target;
select lives_ok($$select public.v1_dispatch_materials(pg_temp.dispatch_final_payload(),'af000000-0000-4000-8000-000000000006')$$,
 'Frozen dispatch retry does not create a duplicate document');
select throws_ok($$select public.v1_discard_procurement_progress(jsonb_build_object('request_id',request_id,'editor_kind','dispatch','arrangement_id',null,
 'expected_revision',0),gen_random_uuid()) from dispatch_progress_target$$,
 '40001','V1_PROCUREMENT_PROGRESS_REVISION_CONFLICT','Stale checkpoint deletion cannot remove accepted progress');
reset role;
select is((select count(*) from public.v1_material_dispatches where request_id=(select request_id from dispatch_progress_target)),1::bigint,
 'Prepared final intent creates exactly one dispatch across retries');

-- Minimal receipts remain independent of optional full-workspace hydration.
create temp table expected_dispatch_receipt as
 select d.request_id,d.id from public.v1_material_dispatches d
 join dispatch_progress_target t on t.request_id=d.request_id;
grant select on expected_dispatch_receipt to authenticated;
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_save_arrangement',
 'af000000-0000-4000-8000-000000000005')#>>'{receipt,effect_id}',arrangement_id::text,
 'Arrangement receipt witnesses the exact nested-key effect') from progress_targets;
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006')#>>'{receipt,effect_id}',
 (select id::text from expected_dispatch_receipt where request_id=t.request_id),
 'Dispatch receipt identifies the exact committed dispatch') from dispatch_progress_target t;
select ok(not(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006') ? 'workspace'),
 'Minimal acknowledgement has no optional workspace dependency') from dispatch_progress_target;
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000099')->>'status','not_found',
 'Lookup miss remains unknown rather than rejected') from dispatch_progress_target;
select is((public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006',true)->>'automatic_checks_remaining')::int,3,
 'Automatic check claims one shared server budget slot') from dispatch_progress_target;
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006',true)->>'check_deferred','true',
 'Competing tab cannot consume a second check inside backoff') from dispatch_progress_target;
reset role;
select is((select automatic_check_count::int from public.v1_procurement_command_intents
 where command_key='af000000-0000-4000-8000-000000000006'),1,
 'Rejected concurrent poll does not increment shared budget');
do $$ declare j int; r uuid; begin
 select request_id into r from dispatch_progress_target;
 for j in 1..3 loop
   update public.v1_procurement_command_intents set automatic_check_after=clock_timestamp()-interval '1 second'
    where command_key='af000000-0000-4000-8000-000000000006';
   perform public.v1_reconcile_procurement_command_outcome(r,'v1_dispatch_materials',
    'af000000-0000-4000-8000-000000000006',true);
 end loop;
end $$;
set local role authenticated;
select is((public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006',true)->>'automatic_checks_remaining')::int,0,
 'Reload and reconnect cannot reset exhausted server budget') from dispatch_progress_target;
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006')->>'status','confirmed',
 'Explicit status check remains available after automatic budget') from dispatch_progress_target;
select is((public.v1_get_procurement_progress_recovery(request_id,'dispatch',null)
 #>>'{pending_command,automatic_checks}')::int,4,
 'Fresh device hydrates exhausted shared budget before sending automatic polls') from dispatch_progress_target;
select ok(not(public.v1_get_procurement_progress(request_id,'dispatch',null)->'pending_command' ? 'automatic_checks'),
 'Released clients retain the original strict pending-command JSON shape') from dispatch_progress_target;

select pg_temp.audit_actor(1,'project_engineer');
select throws_ok($$select public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006') from dispatch_progress_target$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Project Engineer cannot read Procurement command receipts');
select pg_temp.audit_actor(2,'site_engineer');
select throws_ok($$select public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006') from dispatch_progress_target$$,
 '42501','V1_PROCUREMENT_PROGRESS_DENIED','Site Engineer cannot read Procurement command receipts');
select pg_temp.audit_actor(4,'admin');
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006')->>'status','not_found',
 'Admin cannot witness another actor private command by knowing its key') from dispatch_progress_target;
reset role;
select ok(not has_function_privilege('anon',
 'public.v1_reconcile_procurement_command_outcome(uuid,text,uuid,boolean)','execute'),
 'Anonymous receipt and budget reads denied');
create or replace function public.v1_logistics_workspace_projection(p_request_id uuid)
 returns jsonb language plpgsql security definer set search_path='' as $$
 begin raise exception 'SYNTHETIC_VIEW_FAILURE'; end $$;
set local role authenticated;
select pg_temp.audit_actor(3,'procurement');
select is(public.v1_reconcile_procurement_command_outcome(request_id,'v1_dispatch_materials',
 'af000000-0000-4000-8000-000000000006')->>'status','confirmed',
 'Broken optional workspace cannot erase a durable dispatch receipt') from dispatch_progress_target;
reset role;
select is((select count(*) from public.v1_material_dispatches
 where request_id=(select request_id from dispatch_progress_target)),1::bigint,
 'Repeated reconciliation creates no dispatch effect');
select * from finish();
rollback;

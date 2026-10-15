begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok((select relrowsecurity from pg_class where oid =
  'public.v1_material_request_recovery_archival_jobs'::regclass),
  'archival obligations have RLS');
select ok(not has_table_privilege('authenticated',
  'public.v1_material_request_recovery_archival_jobs','select,insert,update,delete'),
  'signed-in actors cannot inspect or alter cleanup obligations');
select ok(not has_table_privilege('anon',
  'public.v1_material_request_recovery_archival_jobs','select,insert,update,delete'),
  'anonymous actors cannot inspect or alter cleanup obligations');
select ok(not has_function_privilege('authenticated',
  'public.v1_process_material_request_recovery_archival(integer)','execute')
  and not has_function_privilege('anon',
  'public.v1_process_material_request_recovery_archival(integer)','execute')
  and has_function_privilege('service_role',
  'public.v1_process_material_request_recovery_archival(integer)','execute'),
  'only server workers can drain recovery archival');
select is((select count(*) from cron.job
  where jobname='yorks-v1-mr-recovery-archival'),1::bigint,
  'exactly one durable scheduled worker is installed');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',true);
select public.v1_create_project('{"project_ref":"ARCHIVE-BOUND","name":"Bounded recovery archival","parties":{},"initial_members":[{"auth_user_id":"10000000-0000-4000-8000-000000000002","project_role":"site_engineer","reason":"Recovery creator"}],"buildings":[{"code":"B1","name":"Test building"}],"attachments":[]}',
  'ad151000-0000-4000-8000-000000000001');
reset role;

insert into public.v1_material_requests
  (id,project_id,scope_id,timing,state,record_version,created_by_auth_user_id,
   current_action_owner_role,current_action_code)
select 'ad150000-0000-4000-8000-000000000001',p.id,s.id,'normal','draft',1,
 '10000000-0000-4000-8000-000000000002','site_engineer','draft_owner'
from public.v1_projects p join public.v1_project_scopes s on s.project_id=p.id
and s.scope_kind='common' where p.project_ref='ARCHIVE-BOUND';
insert into public.v1_material_request_private_drafts
 (draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at)
values ('ad150000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000002',4,
 '{"title":"Original recovery","unknown_future":{"keep":[1,2,3]},"lines":[]}',now());
update public.v1_material_requests set state='awaiting_request_approval',
 request_number='ARCHIVE-BOUND-MR001',submitted_at=now()
where id='ad150000-0000-4000-8000-000000000001';
select is((select count(*) from public.v1_material_request_private_drafts
  where draft_id='ad150000-0000-4000-8000-000000000001'),0::bigint,
  'uncontended progression still archives atomically');
select is((select draft_data->'unknown_future'
  from public.v1_material_request_recovery_archive
  where draft_id='ad150000-0000-4000-8000-000000000001' and sync_version=4),
  '{"keep":[1,2,3]}'::jsonb,'unknown input is preserved verbatim');
select is((select count(*) from public.v1_material_request_recovery_archival_jobs
  where draft_id='ad150000-0000-4000-8000-000000000001'),0::bigint,
  'uncontended progression creates no background work');

-- Model the committed state after a lock-contended trigger: recovery contents
-- remain intact; the same transaction persisted the progressed MR and this job.
insert into public.v1_material_request_private_drafts
 (draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at)
values ('ad150000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000002',5,
 '{"title":"Contended recovery","unknown_future":{"keep":"exactly"},"lines":[]}',now());
insert into public.v1_material_request_recovery_archival_jobs
 (draft_id,owner_auth_user_id) values
 ('ad150000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002'),
 ('ad150000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',true);
select throws_ok($$select public.v1_sync_material_request_private_draft(
 '{"draft_id":"ad150000-0000-4000-8000-000000000001","expected_sync_version":5,"client_updated_at":"2026-10-15T00:00:00Z","draft_data":{"title":"stale autosave","lines":[]}}',gen_random_uuid())$$,
 '55000','V1_PRIVATE_DRAFT_ALREADY_SAVED',
 'committed request fences old autosave while archival is pending');
select throws_ok($$select public.v1_get_my_material_request_private_draft(
 'ad150000-0000-4000-8000-000000000001')$$,'55000','V1_PRIVATE_DRAFT_ALREADY_SAVED',
 'pending archival never appears as editable recovery');
select is((select count(*) from jsonb_array_elements(
 public.v1_list_my_material_request_private_drafts()) d
 where d->>'draft_id'='ad150000-0000-4000-8000-000000000001'),0::bigint,
 'pending archival is absent from private recovery lists');
select throws_ok($$select public.v1_process_material_request_recovery_archival(50)$$,
 '42501','permission denied for function v1_process_material_request_recovery_archival',
 'a Site Engineer cannot invoke privileged cleanup');
reset role;

select is(public.v1_process_material_request_recovery_archival(50)->>'completed','2',
 'worker retires duplicate obligations without duplicate archive writes');
select is((select count(*) from public.v1_material_request_recovery_archive
 where draft_id='ad150000-0000-4000-8000-000000000001' and sync_version=5),1::bigint,
 'one exact historical snapshot survives duplicate jobs');
select is((select draft_data->'unknown_future' from public.v1_material_request_recovery_archive
 where draft_id='ad150000-0000-4000-8000-000000000001' and sync_version=5),
 '{"keep":"exactly"}'::jsonb,'deferred archival preserves unknown recovery fields');
select is(public.v1_process_material_request_recovery_archival(50),
 '{"completed":0,"deferred":0}'::jsonb,'a worker replay is harmless');
select is((select state from public.v1_material_requests
 where id='ad150000-0000-4000-8000-000000000001'),'awaiting_request_approval',
 'cleanup never changes workflow state');

-- Malformed or stale queue obligations cannot erase unsubmitted input.
insert into public.v1_material_request_private_drafts
 (draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at)
values ('ad150000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000002',1,'{"lines":[],"preserve":true}',now());
insert into public.v1_material_request_recovery_archival_jobs
 (draft_id,owner_auth_user_id) values
 ('ad150000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002'),
 ('ad150000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003');
select is(public.v1_process_material_request_recovery_archival(50)->>'deferred','2',
 'missing and wrong-owner fences preserve durable obligations for inspection');
select is((select count(*) from public.v1_material_request_private_drafts
 where draft_id='ad150000-0000-4000-8000-000000000002'),1::bigint,
 'missing committed fence cannot erase an active private draft');
select is((select count(*) from public.v1_material_request_recovery_archival_jobs
 where attempt_count=1 and last_error_code='55000'
 and next_attempt_at>last_attempt_at),2::bigint,
 'worker errors retain bounded backoff and a safe code without payload logging');

-- All four required roles retain their prior owner-only recovery rules.
do $$declare r record; begin
 for r in select auth_user_id,canonical_role_snapshot as app_role
 from public.v1_profiles where auth_user_id in (
 '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004')
 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r.auth_user_id,
   'role','authenticated','app_metadata',jsonb_build_object('role',r.app_role))::text,true);
  perform public.v1_sync_material_request_private_draft(
   '{"draft_id":"ad150000-0000-4000-8000-000000000003","expected_sync_version":0,"client_updated_at":"2026-10-15T00:00:00Z","draft_data":{"lines":[]}}',gen_random_uuid());
 end loop;
end $$;
select is((select count(*) from public.v1_material_request_private_drafts
 where draft_id='ad150000-0000-4000-8000-000000000003'),4::bigint,
 'Project/Site Engineer, Procurement and Admin keep independent private drafts');

select * from finish();
rollback;

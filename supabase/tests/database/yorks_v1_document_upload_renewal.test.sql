begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values
 ('a2150000-0000-4000-8000-000000000011','upload-workshop@yorks.local.test','{"role":"workshop_in_charge"}','{"full_name":"Upload Workshop"}'),
 ('a2150000-0000-4000-8000-000000000012','upload-document@yorks.local.test','{"role":"document_controller"}','{"full_name":"Upload Document"}');
insert into public.v1_projects(id,project_ref,name,state,created_by_auth_user_id,created_by_role)
values('a2150000-0000-4000-8000-000000000001','UPLOAD-RESUME-001','Upload renewal fixture','active','10000000-0000-4000-8000-000000000001','project_engineer');
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,assigned_by_auth_user_id,assigned_by_role,reason)
select 'a2150000-0000-4000-8000-000000000001',actor,case when actor='10000000-0000-4000-8000-000000000001' then 'project_engineer' else 'site_engineer' end,
 now()-interval '1 day','10000000-0000-4000-8000-000000000004','admin','Upload renewal test'
from unnest(array['10000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000002'::uuid]) actor;
create temporary table upload_cases(actor uuid,exact_role text,payload jsonb,key uuid,intent jsonb);
grant all on upload_cases to authenticated;
grant select on upload_cases to service_role;
insert into upload_cases(actor,exact_role,payload,key)
select actor,exact_role,jsonb_build_object(
  'project_id','a2150000-0000-4000-8000-000000000001',
  'entity_type','project','entity_id','a2150000-0000-4000-8000-000000000001',
  'document_id',null,'classification','operational',
  'file_name',exact_role||'.pdf','mime_type','application/pdf',
  'byte_size',12,'sha256',repeat('a',64),'origin','uploaded',
  'source_entity_type',null,'source_entity_id',null,'source_revision',null
),original_key
from (values
  ('10000000-0000-4000-8000-000000000001'::uuid,'project_engineer','a2150000-0000-4000-8000-000000000101'::uuid),
  ('10000000-0000-4000-8000-000000000002'::uuid,'site_engineer','a2150000-0000-4000-8000-000000000102'::uuid),
  ('10000000-0000-4000-8000-000000000003'::uuid,'procurement','a2150000-0000-4000-8000-000000000103'::uuid),
  ('10000000-0000-4000-8000-000000000004'::uuid,'admin','a2150000-0000-4000-8000-000000000104'::uuid),
  ('10000000-0000-4000-8000-000000000009'::uuid,'senior_mechanical_engineer','a2150000-0000-4000-8000-000000000105'::uuid),
  ('10000000-0000-4000-8000-000000000010'::uuid,'project_manager','a2150000-0000-4000-8000-000000000106'::uuid),
  ('a2150000-0000-4000-8000-000000000011'::uuid,'workshop_in_charge','a2150000-0000-4000-8000-000000000108'::uuid),
  ('a2150000-0000-4000-8000-000000000012'::uuid,'document_controller','a2150000-0000-4000-8000-000000000109'::uuid)
) personas(actor,exact_role,original_key);
select ok(has_function_privilege('authenticated','public.v1_resume_document_upload(uuid,uuid)','execute')
 and not has_function_privilege('anon','public.v1_resume_document_upload(uuid,uuid)','execute'),
 'Only authenticated clients can request a protected upload resume');
select ok(not has_table_privilege('authenticated','public.v1_document_upload_intents','update'),
 'Clients cannot extend upload expiry by editing the intent table');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000001", "role": "authenticated", "app_metadata": {"role": "project_engineer"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000001';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000001'),'a2150000-0000-4000-8000-000000000101')$$,'project_engineer can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000002", "role": "authenticated", "app_metadata": {"role": "site_engineer"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000002';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000002'),'a2150000-0000-4000-8000-000000000102')$$,'site_engineer can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000003", "role": "authenticated", "app_metadata": {"role": "procurement"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000003';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000003'),'a2150000-0000-4000-8000-000000000103')$$,'procurement can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000004", "role": "authenticated", "app_metadata": {"role": "admin"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000004';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000004'),'a2150000-0000-4000-8000-000000000104')$$,'admin can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000009", "role": "authenticated", "app_metadata": {"role": "senior_mechanical_engineer"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000009';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000009'),'a2150000-0000-4000-8000-000000000105')$$,'senior_mechanical_engineer can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000010", "role": "authenticated", "app_metadata": {"role": "project_manager"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='10000000-0000-4000-8000-000000000010';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000010'),'a2150000-0000-4000-8000-000000000106')$$,'project_manager can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "a2150000-0000-4000-8000-000000000011", "role": "authenticated", "app_metadata": {"role": "workshop_in_charge"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='a2150000-0000-4000-8000-000000000011';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='a2150000-0000-4000-8000-000000000011'),'a2150000-0000-4000-8000-000000000108')$$,'workshop_in_charge can resume only their currently authorized upload');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "a2150000-0000-4000-8000-000000000012", "role": "authenticated", "app_metadata": {"role": "document_controller"}}',true);
update upload_cases set intent=public.v1_prepare_document_upload(payload,key)
where actor='a2150000-0000-4000-8000-000000000012';
select lives_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='a2150000-0000-4000-8000-000000000012'),'a2150000-0000-4000-8000-000000000109')$$,'document_controller can resume only their currently authorized upload');
set local role postgres;
create temporary table original_upload as select i.* from public.v1_document_upload_intents i join upload_cases c on i.id=(c.intent->>'upload_intent_id')::uuid where c.exact_role='project_engineer';
grant select on original_upload to authenticated,service_role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000001", "role": "authenticated", "app_metadata": {"role": "project_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000999')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','project_engineer cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000002", "role": "authenticated", "app_metadata": {"role": "site_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','site_engineer cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000003", "role": "authenticated", "app_metadata": {"role": "procurement"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','procurement cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000004", "role": "authenticated", "app_metadata": {"role": "admin"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','admin cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000009", "role": "authenticated", "app_metadata": {"role": "senior_mechanical_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','senior_mechanical_engineer cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000010", "role": "authenticated", "app_metadata": {"role": "project_manager"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','project_manager cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000013", "role": "authenticated", "app_metadata": {"role": "accountant"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','accountant cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "a2150000-0000-4000-8000-000000000011", "role": "authenticated", "app_metadata": {"role": "workshop_in_charge"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','workshop_in_charge cannot resume another upload or substitute its original key');
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "a2150000-0000-4000-8000-000000000012", "role": "authenticated", "app_metadata": {"role": "document_controller"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','document_controller cannot resume another upload or substitute its original key');
set local role postgres;
select is((select expires_at from public.v1_document_upload_intents where id=(select id from original_upload)),(select expires_at from original_upload),'A live intent is not extended by resume');
insert into storage.objects(bucket_id,name,owner_id,metadata) select bucket_id,object_path,actor_auth_user_id::text,'{"size":12,"mimetype":"application/pdf"}'::jsonb from original_upload;
update public.v1_document_upload_intents set created_at=clock_timestamp()-interval '16 minutes',expires_at=clock_timestamp()-interval '1 minute' where id=(select id from original_upload);
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000001", "role": "authenticated", "app_metadata": {"role": "project_engineer"}}',true);
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok(
  $$select public.v1_create_document_version((select id from original_upload),
    repeat('a',64),12,'application/pdf')$$,
  '22023','V1_DOCUMENT_UPLOAD_INTENT_EXPIRED',
  'The old expired intent cannot finalize until authenticated server renewal succeeds'
);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select lives_ok($$select public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')$$,'Expired uncommitted upload is renewed under the original intent row lock');
set local role postgres;
select ok((select expires_at>clock_timestamp()+interval '14 minutes' and expires_at<=clock_timestamp()+interval '15 minutes' from public.v1_document_upload_intents where id=(select id from original_upload)),'Only a fresh bounded fifteen-minute upload window is granted');
select ok((select i.id=o.id and i.idempotency_key=o.idempotency_key and i.object_path=o.object_path and i.expected_sha256=o.expected_sha256 and i.byte_size=o.byte_size and i.planned_revision_number=o.planned_revision_number from public.v1_document_upload_intents i join original_upload o on i.id=o.id),'Renewal preserves the exact key, object, payload hash, size and planned revision');
select is((select count(*) from storage.objects where name=(select object_path from original_upload)),1::bigint,'Already transferred immutable bytes are retained');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select lives_ok($$select public.v1_create_document_version((select id from original_upload),repeat('a',64),12,'application/pdf')$$,'Renewed intent finalizes the original stored object');
set local role postgres;
update public.v1_document_upload_intents set expires_at=clock_timestamp()-interval '1 minute' where id=(select id from original_upload);
create temporary table finalized_upload as select * from public.v1_document_upload_intents where id=(select id from original_upload);
grant select on finalized_upload to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000001", "role": "authenticated", "app_metadata": {"role": "project_engineer"}}',true);
select is(public.v1_resume_document_upload((select id from original_upload),'a2150000-0000-4000-8000-000000000101')->>'finalized_version_id',(select finalized_version_id::text from finalized_upload),'A previously committed upload returns its original exact receipt after expiry');
set local role postgres;
select is((select expires_at from public.v1_document_upload_intents where id=(select id from original_upload)),(select expires_at from finalized_upload),'Finalized intent expiry is never renewed');
select is((select count(*) from public.v1_document_versions where document_id=(select finalized_document_id from finalized_upload)),1::bigint,'Resume cannot duplicate a committed document version');
select is((select count(*) from public.v1_audit_events where event_type='document_version_created' and idempotency_key='a2150000-0000-4000-8000-000000000101'),1::bigint,'Resume creates no duplicate finalization audit');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
insert into upload_cases(actor,exact_role,payload,key,intent)
select actor,'replacement_'||label,
  payload||jsonb_build_object('document_id',
    (select finalized_document_id from finalized_upload),
    'file_name','replacement-'||label||'.pdf'),replacement_key,
  public.v1_prepare_document_upload(
    payload||jsonb_build_object('document_id',
      (select finalized_document_id from finalized_upload),
      'file_name','replacement-'||label||'.pdf'),replacement_key)
from upload_cases cross join (values
  ('expired','a2150000-0000-4000-8000-000000000201'::uuid),
  ('winner','a2150000-0000-4000-8000-000000000202'::uuid)
) replacements(label,replacement_key)
where exact_role='project_engineer';
set local role postgres;
update public.v1_document_upload_intents
set created_at=clock_timestamp()-interval '16 minutes',
    expires_at=clock_timestamp()-interval '1 minute'
where id=(select (intent->>'upload_intent_id')::uuid from upload_cases
  where exact_role='replacement_expired');
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'yorks-documents',intent->>'object_path',actor::text,
  '{"size":12,"mimetype":"application/pdf"}'::jsonb
from upload_cases where exact_role='replacement_winner';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.v1_create_document_version(
  (select (intent->>'upload_intent_id')::uuid from upload_cases
    where exact_role='replacement_winner'),repeat('a',64),12,'application/pdf');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select throws_ok(
  $$select public.v1_resume_document_upload(
    (select (intent->>'upload_intent_id')::uuid from upload_cases
      where exact_role='replacement_expired'),
    'a2150000-0000-4000-8000-000000000201')$$,
  '40001','V1_DOCUMENT_UPLOAD_VERSION_CONFLICT',
  'An occupied replacement revision requires explicit review, never silent renewal/replan'
);
set local role postgres;
select ok((select expires_at<clock_timestamp() and finalized_at is null
  from public.v1_document_upload_intents
  where id=(select (intent->>'upload_intent_id')::uuid from upload_cases
    where exact_role='replacement_expired')),
  'Conflicting original intent remains uncommitted, expired and preserved');
update public.v1_project_members set effective_to=clock_timestamp()-interval '1 second',revoked_by_auth_user_id='10000000-0000-4000-8000-000000000004',revoked_by_role='admin',revoked_reason='Upload renewal revoked membership' where project_id='a2150000-0000-4000-8000-000000000001' and member_auth_user_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000002", "role": "authenticated", "app_metadata": {"role": "site_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000002'),'a2150000-0000-4000-8000-000000000102')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','A revoked Site Engineer cannot renew a formerly writable upload');
set local role postgres;
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000002", "role": "authenticated", "app_metadata": {"role": "site_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000002'),'a2150000-0000-4000-8000-000000000102')$$,'42501','V1_ACTIVE_ACTOR_REQUIRED','Inactive actor cannot renew any upload');
set local role postgres;
update public.v1_profiles set is_active=true where auth_user_id='10000000-0000-4000-8000-000000000002';
update auth.users set raw_app_meta_data=jsonb_set(raw_app_meta_data,'{role}','"procurement"') where id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000002", "role": "authenticated", "app_metadata": {"role": "site_engineer"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where actor='10000000-0000-4000-8000-000000000002'),'a2150000-0000-4000-8000-000000000102')$$,'42501','V1_ACTIVE_ACTOR_REQUIRED','A stale old role claim cannot renew an upload');
set local role postgres;
update auth.users set raw_app_meta_data=jsonb_set(raw_app_meta_data,'{role}','"site_engineer"') where id='10000000-0000-4000-8000-000000000002';
update public.v1_projects set state='archived' where id='a2150000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub": "10000000-0000-4000-8000-000000000003", "role": "authenticated", "app_metadata": {"role": "procurement"}}',true);
select throws_ok($$select public.v1_resume_document_upload((select (intent->>'upload_intent_id')::uuid from upload_cases where exact_role='procurement'),'a2150000-0000-4000-8000-000000000103')$$,'42501','V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED','An archived project cannot regain document-write authority through renewal');
select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(13);
update public.v1_push_transport_control set operator_paused=false where id;
insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id)
values('9a000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003',
'material_request_submitted','material_request','9a000000-0000-4000-8000-000000000002');
insert into public.v1_push_device_tokens(token,auth_user_id,platform)
values('p0-fake-token-for-testing-only','10000000-0000-4000-8000-000000000003','web');
update public.v1_push_device_tokens set web_origin='https://yorks-r35.vercel.app',installation_id=gen_random_uuid(),enrolled_at=clock_timestamp()-interval '1 minute' where token like 'p0-%';
update public.v1_notification_push_outbox set dispatch_lease_until=clock_timestamp()+interval '2 minutes'
where notification_id='9a000000-0000-4000-8000-000000000001';
create temporary table device_fixture as select
'9a000000-0000-4000-8000-000000000001'::uuid as id,
(public.v1_claim_notification_push('9a000000-0000-4000-8000-000000000001')->>'claimId')::uuid as claim,
encode(extensions.digest('p0-fake-token-for-testing-only','sha256'),'hex') as hash;
select is(public.v1_begin_push_device(id,claim,hash),'ready','Current owner device begins once') from device_fixture;
select is(public.v1_begin_push_device(id,claim,hash),'sending','Repeated begin cannot duplicate send') from device_fixture;
select is(public.v1_finish_push_device(id,gen_random_uuid(),hash,null),false,'Stale device finish rejected') from device_fixture;
select is(public.v1_finish_push_device(id,claim,hash,null),true,'Accepted send recorded') from device_fixture;
select is(public.v1_begin_push_device(id,claim,hash),'sent','Accepted device never resends') from device_fixture;
select is(public.v1_finish_push_device(id,claim,hash,'TOKEN_UNREGISTERED'),false,'Duplicate finish cannot delete token') from device_fixture;
select ok(exists(select 1 from public.v1_push_device_tokens where token='p0-fake-token-for-testing-only'),'Token preserved after stale finish');
select is(public.v1_begin_push_device(id,claim,repeat('0',64)),'not_owned','Unknown token hash cannot be sent') from device_fixture;
select ok(not has_function_privilege('authenticated','public.v1_begin_push_device(uuid,uuid,text)','execute')
 and not has_function_privilege('anon','public.v1_finish_push_device(uuid,uuid,text,text)','execute'),'Untrusted roles cannot use device RPCs');
select ok(not has_table_privilege('service_role','public.v1_push_device_deliveries','UPDATE'),'Service cannot bypass fenced device RPCs');
-- Exercise token pruning with a second current device outcome.
insert into public.v1_push_device_tokens(token,auth_user_id,platform)
values('p0-stale-token-for-testing-only','10000000-0000-4000-8000-000000000003','web');
update public.v1_push_device_tokens set web_origin='https://yorks-r35.vercel.app',installation_id=gen_random_uuid(),enrolled_at=clock_timestamp()-interval '1 minute' where token='p0-stale-token-for-testing-only';
update device_fixture set hash=encode(extensions.digest('p0-stale-token-for-testing-only','sha256'),'hex');
select is(public.v1_begin_push_device(id,claim,hash),'ready','Second device independently claims') from device_fixture;
select is(public.v1_finish_push_device(id,claim,hash,'TOKEN_UNREGISTERED'),true,'Definitive revocation recorded') from device_fixture;
select ok(not exists(select 1 from public.v1_push_device_tokens where token='p0-stale-token-for-testing-only'),'Only definitively revoked owner token removed');
select * from finish();
rollback;

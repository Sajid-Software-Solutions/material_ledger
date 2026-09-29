begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(11);
insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id)
values('9f100000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003',
'material_request_submitted','material_request','9f100000-0000-4000-8000-000000000002');
update public.v1_notification_push_outbox set status='no_devices'
where notification_id='9f100000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',true);
select throws_ok($$select public.v1_register_push_installation('fake-token-preview-00000000','web','https://yorks-random-preview.vercel.app','9f100000-0000-4000-8000-000000000003')$$,'22023','V1_PUSH_ORIGIN_NOT_ALLOWED','Preview origin cannot enroll');
select is(public.v1_register_push_installation('fake-token-canonical-old-00000','web','https://yorks-r35.vercel.app','9f100000-0000-4000-8000-000000000003'),true,'Canonical installation enrolls');
select is(public.v1_register_push_installation('fake-token-canonical-new-00000','web','https://yorks-r35.vercel.app','9f100000-0000-4000-8000-000000000003'),true,'Same installation rotates');
set local role postgres;
select ok((select retired_at is not null from public.v1_push_device_tokens where token='fake-token-canonical-old-00000'),'Old token preserved and retired');
select is((select count(*) from public.v1_push_device_tokens where installation_id='9f100000-0000-4000-8000-000000000003' and retired_at is null),1::bigint,'One active token per enrolled installation');
select is((select status from public.v1_notification_push_outbox where notification_id='9f100000-0000-4000-8000-000000000001'),'no_devices','Enabling notifications never replays history');
select ok(not has_function_privilege('anon','public.v1_register_push_installation(text,text,text,uuid)','execute'),'Anonymous enrollment denied');
select ok(not has_table_privilege('authenticated','public.v1_push_transport_control','UPDATE'),'Client cannot add preview origins to approved list');
-- Simulate a still-pending event from before enrollment: never alert this new browser.
update public.v1_push_transport_control set operator_paused=false where id;
update public.v1_notification_push_outbox set status='pending',
 dispatch_lease_until=clock_timestamp()+interval '2 minutes'
 where notification_id='9f100000-0000-4000-8000-000000000001';
create temporary table installation_claim as select
'9f100000-0000-4000-8000-000000000001'::uuid as id,
(public.v1_claim_notification_push('9f100000-0000-4000-8000-000000000001')->>'claimId')::uuid as claim;
select is(public.v1_begin_push_device(id,claim,encode(extensions.digest('fake-token-canonical-new-00000','sha256'),'hex')),
'not_owned','Newly enrolled browser cannot receive pre-enrollment pending history') from installation_claim;
insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id)
values('9f100000-0000-4000-8000-000000000009','10000000-0000-4000-8000-000000000003',
'material_request_submitted','material_request','9f100000-0000-4000-8000-000000000009');
update public.v1_notification_push_outbox set dispatch_lease_until=clock_timestamp()+interval '2 minutes'
where notification_id='9f100000-0000-4000-8000-000000000009';
update installation_claim set id='9f100000-0000-4000-8000-000000000009',
claim=(public.v1_claim_notification_push('9f100000-0000-4000-8000-000000000009')->>'claimId')::uuid;
select is(public.v1_begin_push_device(id,claim,encode(extensions.digest('fake-token-canonical-old-00000','sha256'),'hex')),
'not_owned','Rotated token cannot receive new events') from installation_claim;
select is(public.v1_begin_push_device(id,claim,encode(extensions.digest('fake-token-canonical-new-00000','sha256'),'hex')),
'ready','Current canonical installation receives new events') from installation_claim;
select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create function pg_temp.settle_id(p_n integer) returns uuid language sql immutable as $$
 select ('be100000-0000-4000-8000-'||lpad(p_n::text,12,'0'))::uuid
$$;
select ok(not has_function_privilege('anon','public.v1_settle_rental_command_intent(text,uuid)','execute'),
 'Anonymous callers cannot settle rental commands');
select ok(not has_table_privilege('authenticated','public.v1_idempotency_keys','insert,update,delete'),
 'Clients cannot remove fences or rewrite idempotency evidence');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Project Engineer cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Site Engineer cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Procurement cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Accountant cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Senior Mechanical Engineer cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000010","role":"authenticated","app_metadata":{"role":"project_manager"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Project Manager cannot settle rental commands');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','Stale Admin JWT cannot settle after actual role revocation');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select throws_ok($$select public.v1_settle_rental_command_intent('v1_submit_material_request',pg_temp.settle_id(1))$$,'22023','V1_RENTAL_COMMAND_INVALID','Settlement cannot fence an unrelated workflow command');
select throws_ok($$select public.v1_settle_rental_command_intent(null,pg_temp.settle_id(1))$$,'22023','V1_RENTAL_COMMAND_INVALID','Null command is rejected');
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',null)$$,'22023','V1_RENTAL_COMMAND_INVALID','Null command key is rejected');

select is(public.v1_get_rental_command_outcome('v1_save_rental_property',pg_temp.settle_id(1))->>'state','unconfirmed',
 'Absent command stays unconfirmed until explicit resolution');
select is(public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))->>'state','abandoned',
 'Active Admin explicitly fences an absent intent');
select is(public.v1_get_rental_command_outcome('v1_save_rental_property',pg_temp.settle_id(1))->>'state','abandoned',
 'Outcome read distinguishes abandoned from a confirmed save');
select is(public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(1))->>'state','abandoned',
 'Repeating resolution retains the original abandoned outcome');
select throws_ok($$select public.v1_save_rental_property('{"unit_code":"SETTLE-DELAYED","property_name":"Delayed fixture","property_type":"shop","occupancy_state":"vacant"}',null,pg_temp.settle_id(1))$$,
 '22023','V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD','Delayed original save cannot execute after its key was fenced');
reset role;
select is((select count(*)::int from public.v1_audit_events where event_type='rental_command_intent_abandoned'
 and entity_id=pg_temp.settle_id(1)),1,'Repeated and delayed requests append one abandonment audit event');
select ok(not exists(select 1 from public.v1_rental_properties where unit_code='SETTLE-DELAYED'),'Delayed save created no business record');
select ok((select completed_at is not null and request_hash='rental-abandoned:'||pg_temp.settle_id(1)::text
 from public.v1_idempotency_keys where actor_auth_user_id='10000000-0000-4000-8000-000000000004'
 and command_name='v1_save_rental_property' and idempotency_key=pg_temp.settle_id(1)),
 'Fence stores a completed marker with a sentinel impossible for an ordinary payload hash');

insert into public.v1_idempotency_keys(actor_auth_user_id,command_name,idempotency_key,request_hash,response_json)
values('10000000-0000-4000-8000-000000000004','v1_record_rent_payment',pg_temp.settle_id(2),'orphaned-claim',null),
 ('10000000-0000-4000-8000-000000000003','v1_record_rent_payment',pg_temp.settle_id(3),'other-actor-claim','{"receipt_id":"other-actor-protected"}');
set local role authenticated;
select is(public.v1_settle_rental_command_intent('v1_record_rent_payment',pg_temp.settle_id(2))->>'state','abandoned',
 'An orphan incomplete claim can be explicitly fenced');
select is(public.v1_get_rental_command_outcome('v1_record_rent_payment',pg_temp.settle_id(3))->>'state','unconfirmed',
 'Another actor completion remains inaccessible');
select is(public.v1_settle_rental_command_intent('v1_record_rent_payment',pg_temp.settle_id(3))->>'state','abandoned',
 'Same key for another actor fences only this actor intent');
reset role;
select is((select response_json->>'receipt_id' from public.v1_idempotency_keys
 where actor_auth_user_id='10000000-0000-4000-8000-000000000003' and command_name='v1_record_rent_payment'
 and idempotency_key=pg_temp.settle_id(3)),'other-actor-protected','Other actor response remains unchanged and undisclosed');

-- A real public command wins first; settlement must never relabel or overwrite it.
set local role authenticated;
select lives_ok($$select public.v1_save_rental_property('{"property_id":"be200000-0000-4000-8000-000000000001","unit_code":"SETTLE-COMMITTED","property_name":"Committed fixture","property_type":"shop","occupancy_state":"vacant"}',null,pg_temp.settle_id(4))$$,
 'Admin commits a real save before attempting intent resolution');
select is(public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(4))->>'state','confirmed',
 'A real committed save is confirmed rather than abandoned');
select is(public.v1_get_rental_command_outcome('v1_save_rental_property',pg_temp.settle_id(4))->>'state','confirmed',
 'Outcome remains confirmed after repeated resolution');
select lives_ok($$select public.v1_save_rental_property('{"property_id":"be200000-0000-4000-8000-000000000001","unit_code":"SETTLE-COMMITTED","property_name":"Committed fixture","property_type":"shop","occupancy_state":"vacant"}',null,pg_temp.settle_id(4))$$,
 'Real same-payload retry still returns the original committed result');
reset role;
select is((select count(*)::int from public.v1_audit_events where event_type='rental_command_intent_abandoned'
 and entity_id=pg_temp.settle_id(4)),0,'Confirmed commands never receive abandonment audit');
select is((select count(*)::int from public.v1_rental_properties where unit_code='SETTLE-COMMITTED'),1,
 'Resolution and same-key retry retain exactly one committed record');
select is((select record_version from public.v1_rental_properties where unit_code='SETTLE-COMMITTED'),1,
 'Confirmed resolution does not mutate property version');
select is((select before_data->>'request_hash' from public.v1_audit_events
 where event_type='rental_command_intent_abandoned' and entity_id=pg_temp.settle_id(2)),
 'orphaned-claim','Audit preserves the original fingerprint of an orphaned incomplete claim');
set local role authenticated;
select is(public.v1_settle_rental_command_intent('v1_save_rental_cheque',pg_temp.settle_id(1))->>'state','abandoned',
 'The same UUID can be settled independently for a different rental command');
select is(public.v1_settle_rental_command_intent('v1_save_rental_cheque',pg_temp.settle_id(1))->>'state','abandoned',
 'Different-command same-key settlement also repeats idempotently');
reset role;
select is((select count(*)::int from public.v1_audit_events where event_type='rental_command_intent_abandoned'
 and entity_id=pg_temp.settle_id(1)),2,'Command-scoped audit identities retain one event per independently settled command');
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok($$select public.v1_settle_rental_command_intent('v1_save_rental_property',pg_temp.settle_id(5))$$,
 '42501','V1_RENTAL_ADMIN_REQUIRED','Inactive Admin cannot create a recovery fence');
select throws_ok($$select public.v1_get_rental_command_outcome('v1_save_rental_property',pg_temp.settle_id(1))$$,
 '42501','V1_RENTAL_ADMIN_REQUIRED','Inactive Admin cannot read even its own abandoned outcome');
reset role;
select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
select ok(not enabled,'Rental producer defaults disabled') from public.v1_rental_notification_control where id;
select ok(not external_push_enabled,'Initial rental cohort defaults inbox-only') from public.v1_rental_notification_control where id;
select ok(not active,'Rental cron registration defaults inactive') from cron.job where jobname='yorks-rental-notifications';
select is(public.v1_run_rental_notifications()->>'emitted','0','Disabled producer emits nothing');
select ok(not has_function_privilege('authenticated','public.v1_run_rental_notifications()','execute'),'Even an authenticated Admin cannot invoke scheduler');
select ok(not has_function_privilege('anon','public.v1_run_rental_notifications()','execute'),'Anonymous scheduler execution denied');
select ok(not has_function_privilege('authenticated','public.v1_rental_notification_candidates()','execute'),'Clients cannot enumerate protected rental obligations');
select ok(not has_table_privilege('authenticated','public.v1_rental_notification_events','select'),'Clients cannot read other recipients or deduplication ledger');
select ok(not has_table_privilege('authenticated','public.v1_rental_notification_control','update'),'Clients cannot activate producer');

insert into public.v1_rental_properties(id,unit_code,property_name,property_type,location,occupancy_state,created_by_auth_user_id,updated_by_auth_user_id)
values('bc100000-0000-4000-8000-000000000001','RN-NOTICE','Rental notification notice fixture','shop','Dubai','occupied','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'),
('bc100000-0000-4000-8000-000000000002','RN-EXPIRED','Rental notification expired fixture','shop','Dubai','occupied','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_rental_leases(id,property_id,contract_number,contract_type,contract_status,tenant_name,lease_start,lease_end,monthly_rent,billing_start,created_by_auth_user_id,updated_by_auth_user_id)
values('bc200000-0000-4000-8000-000000000001','bc100000-0000-4000-8000-000000000001','RN-NOTICE-CONTRACT','lease','active','Protected tenant',public.v1_rental_business_date()-100,public.v1_rental_business_date()+30,100,public.v1_rental_business_date()-100,'10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'),
('bc200000-0000-4000-8000-000000000002','bc100000-0000-4000-8000-000000000002','RN-EXPIRED-CONTRACT','lease','active','Protected tenant',public.v1_rental_business_date()-100,public.v1_rental_business_date()-1,100,null,'10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_rental_periods(id,lease_id,period_month,due_date,amount_due)
values('bc300000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001',date_trunc('month',public.v1_rental_business_date())::date,public.v1_rental_business_date()-10,100),
('bc300000-0000-4000-8000-000000000002','bc200000-0000-4000-8000-000000000002',date_trunc('month',public.v1_rental_business_date())::date,public.v1_rental_business_date()-10,100);
insert into public.v1_rental_periods(id,lease_id,period_month,due_date,amount_due)
values('bc300000-0000-4000-8000-000000000003','bc200000-0000-4000-8000-000000000001',(date_trunc('month',public.v1_rental_business_date())+interval '1 month')::date,public.v1_rental_business_date(),100);
insert into public.v1_rental_receipts(id,property_id,lease_id,period_id,amount_received,payment_date,payment_method,recorded_by_auth_user_id,recorded_by_role,idempotency_key)
values('bc400000-0000-4000-8000-000000000001','bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001','bc300000-0000-4000-8000-000000000001',25,public.v1_rental_business_date(),'cash','10000000-0000-4000-8000-000000000004','admin','bc400000-0000-4000-8000-000000000099');
insert into public.v1_rental_receipts(id,property_id,lease_id,period_id,amount_received,payment_date,payment_method,recorded_by_auth_user_id,recorded_by_role,idempotency_key)
values('bc400000-0000-4000-8000-000000000003','bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001','bc300000-0000-4000-8000-000000000003',25,public.v1_rental_business_date(),'cash','10000000-0000-4000-8000-000000000004','admin','bc400000-0000-4000-8000-000000000097');
insert into public.v1_rental_cheques(id,property_id,lease_id,cheque_number,cheque_type,bank_name,cheque_date,amount,status,created_by_auth_user_id,updated_by_auth_user_id)
values('bc500000-0000-4000-8000-000000000001','bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001','RN-DUE','pdc','Protected bank',public.v1_rental_business_date(),100,'received','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'),
('bc500000-0000-4000-8000-000000000002','bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001','RN-RETURNED','pdc','Protected bank',public.v1_rental_business_date()-3,100,'returned','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
savepoint rental_initial_inbox;
update public.v1_rental_notification_control set enabled=true where id;
select ok((public.v1_run_rental_notifications()->>'emitted')::int>0,'Initial run creates durable inbox without external push');
select is((select count(*)::int from public.v1_rental_notification_events e join public.v1_notification_push_outbox o on o.notification_id=e.notification_id),0,'Initial cohort creates no retryable outbox jobs');
select ok(not exists(select 1 from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where public.v1_push_notification_entity_allowed(n)),'Initial cohort suppresses foreground popups as well as external transport');
update public.v1_rental_notification_control set external_push_enabled=true where id;
select is(public.v1_run_rental_notifications()->>'emitted','0','Later push enablement does not replay initial milestones');
select ok(not exists(select 1 from public.v1_rental_notification_events where external_push_eligible),'Initial suppression is retained as explicit ledger evidence');
rollback to rental_initial_inbox;
savepoint rental_initial_digest;
update public.v1_rental_notification_control set enabled=true,external_push_enabled=true,last_success_at=null where id;
select ok((public.v1_run_rental_notifications()->>'emitted')::int>1,'First enabled run retains current milestones and a completeness digest');
select is((select count(*)::int from public.v1_rental_notification_events where external_push_eligible),1,'First external evaluation permits only one completeness digest per Admin');
select ok(not exists(select 1 from public.v1_rental_notification_events where external_push_eligible and event_code<>'rental_completeness_review'),'Initial lease/cheque/debt cohort stays inbox-only');
select is((select count(*)::int from public.v1_rental_notification_events e join public.v1_notification_push_outbox o on o.notification_id=e.notification_id),1,'Initial global enqueue creates only the one legitimate completeness push job');
rollback to rental_initial_digest;
update public.v1_rental_notification_control set enabled=true,external_push_enabled=true,initial_evaluation_complete=true,last_success_at=statement_timestamp()-interval '1 day' where id;
select ok((public.v1_run_rental_notifications()->>'emitted')::int between 1 and 100,'Enabled run is bounded to 100 current events');
select is(public.v1_run_rental_notifications()->>'emitted','0','Identical retry does not duplicate a milestone or daily digest');
select ok(not exists(select 1 from public.v1_rental_notification_events e where public.v1_permission_exact_role(e.recipient_auth_user_id)<>'admin'),'All emitted recipients are exact active Admins');
select ok(not public.v1_push_notification_entity_allowed(jsonb_populate_record(n,jsonb_build_object('recipient_auth_user_id',p.auth_user_id))),
  'Rental delivery denied to '||public.v1_permission_exact_role(p.auth_user_id))
  from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id
  cross join public.v1_profiles p where e.obligation_id='bc500000-0000-4000-8000-000000000001'
    and p.auth_user_id in('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc300000-0000-4000-8000-000000000001' and event_code='rental_rent_overdue'),1,'Partly paid confirmed obligation still produces overdue attention');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc300000-0000-4000-8000-000000000003' and event_code='rental_rent_due'),1,'Partly paid current obligation produces due attention within grace');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc300000-0000-4000-8000-000000000003' and event_code='rental_rent_overdue'),0,'Within-grace due period is not prematurely overdue');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc300000-0000-4000-8000-000000000002'),0,'Unconfirmed billing never produces rent debt attention');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc200000-0000-4000-8000-000000000001' and event_code='rental_lease_notice_due'),1,'Current notice window creates one notification');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc200000-0000-4000-8000-000000000002' and event_code='rental_lease_expired'),1,'Expired lease creates current expiry event without replaying prior notice');
select is((select count(*)::int from public.v1_rental_notification_events where obligation_id='bc200000-0000-4000-8000-000000000002' and event_code='rental_lease_notice_due'),0,'Expired lease does not replay notice interval');
select ok(public.v1_push_notification_entity_allowed(n),'Current rental event passes protected eligibility') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.obligation_id='bc500000-0000-4000-8000-000000000002';
select is(public.v1_notification_module_route(n),'/rentals/bc100000-0000-4000-8000-000000000001','Cheque event targets its property') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.obligation_id='bc500000-0000-4000-8000-000000000002';
select is(public.v1_notification_module_route(n),'/rentals','Completeness digest targets register') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.event_code='rental_completeness_review';
update public.v1_rental_cheques set note='Correction without lifecycle transition',record_version=record_version+1 where id='bc500000-0000-4000-8000-000000000002';
select is(public.v1_run_rental_notifications()->>'emitted','0','Editing a returned cheque note does not repeat its lifecycle alert');

insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id)
values('bc600000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','rental_cheque_returned','rental_property','bc100000-0000-4000-8000-000000000001');
select ok(not public.v1_push_notification_entity_allowed(n),'A forged rental prefix without ledger identity is rejected') from public.v1_notifications n where id='bc600000-0000-4000-8000-000000000001';
select is(public.v1_notification_module_route(n),null,'Forged rental event has no protected route') from public.v1_notifications n where id='bc600000-0000-4000-8000-000000000001';
update public.v1_rental_cheques set status='cancelled',record_version=record_version+1 where id='bc500000-0000-4000-8000-000000000002';
select ok(not public.v1_push_notification_entity_allowed(n),'Resolved returned cheque suppresses pending attention') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.obligation_id='bc500000-0000-4000-8000-000000000002';
insert into public.v1_rental_receipts(id,property_id,lease_id,period_id,amount_received,payment_date,payment_method,recorded_by_auth_user_id,recorded_by_role,idempotency_key)
values('bc400000-0000-4000-8000-000000000002','bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001','bc300000-0000-4000-8000-000000000001',75,public.v1_rental_business_date(),'cash','10000000-0000-4000-8000-000000000004','admin','bc400000-0000-4000-8000-000000000098');
select ok(not public.v1_push_notification_entity_allowed(n),'Paid balance suppresses pending overdue push') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.obligation_id='bc300000-0000-4000-8000-000000000001';
insert into public.v1_rental_cheques(id,property_id,lease_id,cheque_number,cheque_type,bank_name,cheque_date,amount,status,created_by_auth_user_id,updated_by_auth_user_id)
select gen_random_uuid(),'bc100000-0000-4000-8000-000000000001','bc200000-0000-4000-8000-000000000001',
  'RN-BOUND-'||i::text,'pdc','Protected bank',public.v1_rental_business_date(),100,'scheduled',
  '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'
from generate_series(1,105) i;
select is(public.v1_run_rental_notifications()->>'emitted','100','Large current workload respects hard 100-event cap');
select is(public.v1_run_rental_notifications()->>'emitted','5','Next run drains only remaining obligations without replay');
select is(public.v1_run_rental_notifications()->>'emitted','0','Drained workload remains idempotent');
insert into public.v1_user_notification_preferences(auth_user_id,workflow_push_enabled,updated_by)
values('10000000-0000-4000-8000-000000000004',false,'10000000-0000-4000-8000-000000000004')
on conflict(auth_user_id) do update set workflow_push_enabled=false;
select ok(not public.v1_notification_push_allowed('10000000-0000-4000-8000-000000000004','rental_completeness_review'),'Rental events respect workflow push preference');
select ok(exists(select 1 from public.v1_rental_notification_events where event_code='rental_completeness_review'),'Disabling optional push preserves rental inbox evidence');
savepoint rental_test_clock;
create or replace function public.v1_rental_business_date() returns date language sql stable set search_path='' as $$
  select (statement_timestamp() at time zone 'Asia/Dubai')::date+1
$$;
select is(public.v1_run_rental_notifications()->>'emitted','1','Next business day creates only one fresh completeness digest');
select is((select count(*)::int from public.v1_rental_notification_events where event_code='rental_completeness_review'),2,'Daily digest retains one stable identity per business date');
select is((select count(*)::int from public.v1_notification_push_outbox o join public.v1_rental_notification_events e on e.notification_id=o.notification_id
  where e.event_code='rental_completeness_review' and e.business_date=public.v1_rental_business_date()),0,'Disabled workflow push creates no outbox while retaining fresh daily inbox');
rollback to rental_test_clock;
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000004';
select ok(not public.v1_push_notification_entity_allowed(n),'Inactive Admin loses rental delivery eligibility') from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where e.obligation_id='bc500000-0000-4000-8000-000000000001';
select ok(not exists(select 1 from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id where public.v1_notification_module_route(n) is not null),'Inactive recipient loses rental route context');
select is(public.v1_run_rental_notifications()->>'emitted','0','No current Admin cannot generate a new recipient');
select * from finish();
rollback;

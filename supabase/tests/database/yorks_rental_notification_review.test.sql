-- Regression: the first evaluation is a cohort, not merely its first 100 rows.
-- All fixtures and emitted notifications are rolled back; no live rows are used.
begin isolation level repeatable read;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

insert into public.v1_rental_properties(id,unit_code,property_name,property_type,location,occupancy_state,created_by_auth_user_id,updated_by_auth_user_id)
values('bd100000-0000-4000-8000-000000000001','RN-COHORT','Rental cohort review fixture','shop','Dubai','occupied',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_rental_leases(id,property_id,contract_number,contract_type,contract_status,tenant_name,lease_start,lease_end,monthly_rent,billing_start,created_by_auth_user_id,updated_by_auth_user_id)
values('bd200000-0000-4000-8000-000000000001','bd100000-0000-4000-8000-000000000001','RN-COHORT-CONTRACT','lease','active','Cohort fixture tenant',
 public.v1_rental_business_date()-365,public.v1_rental_business_date()+365,100,public.v1_rental_business_date()-365,
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_rental_periods(id,lease_id,period_month,due_date,amount_due)
values('bd300000-0000-4000-8000-000000000001','bd200000-0000-4000-8000-000000000001',
 date_trunc('month',public.v1_rental_business_date())::date,public.v1_rental_business_date()-20,100);
insert into public.v1_rental_cheques(id,property_id,lease_id,cheque_number,cheque_type,bank_name,cheque_date,amount,status,created_by_auth_user_id,updated_by_auth_user_id)
select gen_random_uuid(),'bd100000-0000-4000-8000-000000000001','bd200000-0000-4000-8000-000000000001',
 'RN-COHORT-'||i::text,'pdc','Cohort fixture bank',public.v1_rental_business_date(),100,'received',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'
from generate_series(1,105) i;
update public.v1_rental_notification_control
set enabled=true,external_push_enabled=true,last_success_at=null,last_emitted_count=0 where id;
create temporary table rental_cohort_expected as
select count(*)::int total from public.v1_rental_notification_candidates() c
cross join public.v1_profiles p where public.v1_permission_exact_role(p.auth_user_id)='admin';
select ok((select total between 106 and 199 from rental_cohort_expected),'Fixture spans two bounded initial batches');
select is(public.v1_run_rental_notifications()->>'emitted','100','First initial batch respects the hard cap');
select is((select count(*)::int from public.v1_rental_notification_events where external_push_eligible and event_code<>'rental_completeness_review'),0,
 'First initial batch does not alert existing obligations externally');
select is((public.v1_run_rental_notifications()->>'emitted')::int,(select total-100 from rental_cohort_expected),
 'Second batch retains every remaining initial obligation');
select is((select count(*)::int from public.v1_rental_notification_events where external_push_eligible and event_code<>'rental_completeness_review'),0,
 'Later initial batches remain inbox-only rather than causing an alert burst');
select is((select count(*)::int from public.v1_notification_push_outbox o join public.v1_rental_notification_events e on e.notification_id=o.notification_id
 where e.event_code<>'rental_completeness_review'),0,'No initial obligation is queued by the global enqueue trigger');
select is((select count(*)::int from public.v1_rental_notification_events where external_push_eligible and event_code='rental_completeness_review'),
 (select count(*)::int from public.v1_profiles p where public.v1_permission_exact_role(p.auth_user_id)='admin'),
 'Initial completeness digest remains eligible once for each active Admin');
select is(public.v1_run_rental_notifications()->>'emitted','0','Completed initial cohort does not replay');

insert into public.v1_rental_cheques(id,property_id,lease_id,cheque_number,cheque_type,bank_name,cheque_date,amount,status,created_by_auth_user_id,updated_by_auth_user_id)
values('bd500000-0000-4000-8000-000000000001','bd100000-0000-4000-8000-000000000001','bd200000-0000-4000-8000-000000000001',
 'RN-COHORT-FRESH','pdc','Cohort fixture bank',public.v1_rental_business_date(),100,'received',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
select is((public.v1_run_rental_notifications()->>'emitted')::int,
 (select count(*)::int from public.v1_profiles p where public.v1_permission_exact_role(p.auth_user_id)='admin'),
 'Genuinely new obligation emits after initial drain');
select ok(bool_and(e.external_push_eligible),'Fresh obligation keeps normal external eligibility')
from public.v1_rental_notification_events e where e.obligation_id='bd500000-0000-4000-8000-000000000001';
select ok(bool_and(public.v1_push_notification_entity_allowed(n)),'Fresh relevant obligation passes final delivery guard')
from public.v1_notifications n join public.v1_rental_notification_events e on e.notification_id=n.id
where e.obligation_id='bd500000-0000-4000-8000-000000000001';

-- Urgent catalogue semantics must also hold at the protected server filter.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select ok(exists(select 1 from jsonb_array_elements(public.v1_notification_page(p_urgent_only=>true)->'records') r
 where r->>'event_code'='rental_rent_overdue' and r->>'entity_id'='bd100000-0000-4000-8000-000000000001'),
 'Admin Urgent inbox includes the confirmed overdue rental obligation');
select ok(not exists(select 1 from jsonb_array_elements(public.v1_notification_page(p_urgent_only=>true)->'records') r
 where r->>'event_code' in('rental_cheque_due','rental_completeness_review')),'Urgent inbox does not include ordinary rental reminders');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select ok(not exists(select 1 from jsonb_array_elements(public.v1_notification_page(p_urgent_only=>true)->'records') r
 where r->>'entity_id'='bd100000-0000-4000-8000-000000000001'),'Accountant cannot see the Admin rental urgency feed');
set local role postgres;
select * from finish();
rollback;

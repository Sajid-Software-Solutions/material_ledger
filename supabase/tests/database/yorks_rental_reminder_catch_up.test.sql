-- A person who newly receives rental reminders catches up quietly: existing
-- reminders arrive already seen and are never pushed; new ones alert them.
-- Fictional fixtures; everything is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Admin ...0004 already receives rental reminders; PR ...0014 is new.
update public.v1_rental_notification_control
set enabled = true, external_push_enabled = true,
  initial_evaluation_complete = true
where id;
insert into public.v1_rental_notification_recipients (
  recipient_auth_user_id, caught_up_at
)
select p.auth_user_id, clock_timestamp()
from public.v1_profiles p
where public.v1_permission_exact_role(p.auth_user_id) = 'admin'
on conflict (recipient_auth_user_id) do update
  set caught_up_at = excluded.caught_up_at;
delete from public.v1_rental_notification_recipients
where recipient_auth_user_id = '10000000-0000-4000-8000-000000000014';

insert into public.v1_rental_properties (
  id, unit_code, property_name, property_type, location, occupancy_state,
  created_by_auth_user_id, updated_by_auth_user_id
) values (
  'bd600000-0000-4000-8000-000000000001', 'RN-CATCHUP',
  'Catch-up fixture shop', 'shop', 'Dubai', 'occupied',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_rental_leases (
  id, property_id, contract_number, contract_type, contract_status,
  tenant_name, lease_start, lease_end, monthly_rent, billing_start,
  created_by_auth_user_id, updated_by_auth_user_id
) values (
  'bd610000-0000-4000-8000-000000000001',
  'bd600000-0000-4000-8000-000000000001', 'RN-CATCHUP-LEASE', 'lease',
  'active', 'Catch-up fixture tenant',
  public.v1_rental_business_date() - 365,
  public.v1_rental_business_date() + 365, 100,
  public.v1_rental_business_date() - 365,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_rental_cheques (
  id, property_id, lease_id, cheque_number, cheque_type, bank_name,
  cheque_date, amount, status, created_by_auth_user_id,
  updated_by_auth_user_id
)
select gen_random_uuid(), 'bd600000-0000-4000-8000-000000000001',
  'bd610000-0000-4000-8000-000000000001', 'RN-CATCHUP-' || i::text, 'pdc',
  'Fixture bank', public.v1_rental_business_date(), 100, 'received',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
from generate_series(1, 6) i;

-- The Admin has already been told about everything open today.
select public.v1_run_rental_notifications();
create temporary table pr_before as
select count(*)::int n from public.v1_rental_notification_events
where recipient_auth_user_id = '10000000-0000-4000-8000-000000000014';

select ok(
  (select n from pr_before) >= 6,
  'The new PR recipient receives the open reminders in their inbox'
);
select is(
  (select count(*)::int
   from public.v1_rental_notification_events e
   join public.v1_notifications n on n.id = e.notification_id
   where e.recipient_auth_user_id = '10000000-0000-4000-8000-000000000014'
     and (e.external_push_eligible or n.seen_at is null)),
  0,
  'Catch-up reminders are already seen and never pushed'
);
select is(
  (select count(*)::int
   from public.v1_notification_push_outbox o
   join public.v1_rental_notification_events e
     on e.notification_id = o.notification_id
   where e.recipient_auth_user_id = '10000000-0000-4000-8000-000000000014'),
  0,
  'Nothing is queued for push during catch-up'
);
select isnt(
  (select caught_up_at from public.v1_rental_notification_recipients
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000014'),
  null,
  'PR is caught up once every open reminder is recorded'
);
select is(
  public.v1_run_rental_notifications() ->> 'emitted',
  '0',
  'Running again sends nothing twice'
);

-- A genuinely new reminder alerts PR as normal.
insert into public.v1_rental_cheques (
  id, property_id, lease_id, cheque_number, cheque_type, bank_name,
  cheque_date, amount, status, created_by_auth_user_id,
  updated_by_auth_user_id
) values (
  'bd620000-0000-4000-8000-000000000001',
  'bd600000-0000-4000-8000-000000000001',
  'bd610000-0000-4000-8000-000000000001', 'RN-CATCHUP-NEW', 'pdc',
  'Fixture bank', public.v1_rental_business_date(), 100, 'received',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
select public.v1_run_rental_notifications();
select ok(
  (select e.external_push_eligible and n.seen_at is null
   from public.v1_rental_notification_events e
   join public.v1_notifications n on n.id = e.notification_id
   where e.recipient_auth_user_id = '10000000-0000-4000-8000-000000000014'
     and e.obligation_id = 'bd620000-0000-4000-8000-000000000001'),
  'A new reminder after catch-up is unread and pushed'
);
select ok(
  (select bool_and(e.external_push_eligible)
   from public.v1_rental_notification_events e
   where e.obligation_id = 'bd620000-0000-4000-8000-000000000001'),
  'The new reminder reaches every recipient normally'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.v1_rental_notification_recipients', 'select'
  ),
  'The recipient register is not readable by signed-in users'
);

select * from finish();
rollback;

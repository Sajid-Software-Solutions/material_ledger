begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

-- All domain writes below use the public Admin RPCs. Helpers construct fixture
-- payloads only; no application role gets normalized-table access.
create function pg_temp.rental_id(p_suffix integer)
returns uuid language sql immutable as $$
  select ('84100000-0000-4000-8000-' || lpad(p_suffix::text, 12, '0'))::uuid
$$;
create function pg_temp.rental_payload(
  p_property integer,
  p_lease integer,
  p_start date default date_trunc('month', current_date)::date,
  p_end date default (date_trunc('month', current_date) + interval '2 month - 1 day')::date,
  p_status text default 'active'
)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'property_id', pg_temp.rental_id(p_property),
    'lease_id', pg_temp.rental_id(p_lease),
    'unit_code', 'SAFE-' || p_property,
    'property_name', 'Safety fixture ' || p_property,
    'property_type', 'shop', 'location', 'Test location', 'occupied', true,
    'tenant_name', 'Safety tenant ' || p_property,
    'contract_number', 'SAFE-LEASE-' || p_lease,
    'contract_type', 'lease', 'contract_status', p_status,
    'lease_start', p_start, 'lease_end', p_end,
    'monthly_rent', 100, 'security_deposit', 0,
    'monthly_due_day', 1, 'grace_period_days', 0,
    'default_payment_method', 'bank_transfer', 'payment_frequency', 'monthly'
  )
$$;

select plan(53);

select ok(
  not has_table_privilege('authenticated', 'public.v1_rental_properties', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.v1_rental_leases', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.v1_rental_periods', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.v1_rental_receipts', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.v1_rental_cheques', 'SELECT,INSERT,UPDATE,DELETE'),
  'All five rental relations remain inaccessible through ordinary authenticated table APIs'
);
select ok(
  not has_function_privilege('anon', 'public.v1_get_rental_portfolio()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.v1_get_rental_export_data()', 'EXECUTE'),
  'Anonymous callers cannot invoke rental read/export endpoints'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}', true);
select throws_ok($$select v1_get_rental_portfolio()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'Project Engineer cannot read Rentals');
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}', true);
select throws_ok($$select v1_get_rental_portfolio()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'Site Engineer cannot read Rentals');
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}', true);
select throws_ok($$select v1_get_rental_portfolio()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'Procurement cannot read Rentals');
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}', true);
select throws_ok($$select v1_get_rental_portfolio()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'Accountant cannot inherit Admin rental visibility');
-- The token still says Admin; the protected live Auth user is Procurement.
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"admin"}}', true);
select throws_ok($$select v1_get_rental_portfolio()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'A stale Admin JWT cannot read the rental portfolio after live role revocation');
select throws_ok($$select v1_get_rental_export_data()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'A stale Admin JWT cannot export tenant or commercial records');
select throws_ok($$select v1_import_rental_workbook('{"properties":[],"payments":[],"cheques":[]}', pg_temp.rental_id(1))$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'A stale Admin JWT cannot import Rentals');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}', true);
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(10, 11), null, pg_temp.rental_id(100))$$, 'Active Admin creates an occupied property');
create temp table rental_safe_snapshot as
  select v1_get_rental_property(pg_temp.rental_id(10)) detail;
select lives_ok($$select v1_record_rent_payment((v1_get_rental_property(pg_temp.rental_id(10))->'periods'->0->>'id')::uuid, 10, current_date, 'cash', null, null, pg_temp.rental_id(101))$$, 'Active Admin records a partial receipt');
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(10, 11)||'{"contact_number":"12345"}', 1, pg_temp.rental_id(102))$$, 'Contact edits succeed after a receipt without rebuilding financial history');
select is(
  v1_get_rental_property(pg_temp.rental_id(10))->'periods'->0->>'id',
  (select detail->'periods'->0->>'id' from rental_safe_snapshot),
  'A paid metadata edit preserves the stable rent period identifier'
);
select is((v1_get_rental_property(pg_temp.rental_id(10))->'periods'->0->>'amount_paid')::numeric, 10::numeric, 'A paid metadata edit preserves the receipt allocation');
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(10, 11)||'{"contact_number":"12345"}', 1, pg_temp.rental_id(102))$$, 'A lost-response metadata retry returns its original committed result');
select is((v1_get_rental_property(pg_temp.rental_id(10))->'property'->>'record_version')::integer, 2, 'A same-key metadata retry increments the property version only once');
select throws_ok($$select v1_save_rental_property(pg_temp.rental_payload(10, 11)||'{"monthly_rent":200}', 2, pg_temp.rental_id(103))$$, '23514', 'V1_RENTAL_PAID_SCHEDULE_CANNOT_BE_REBUILT', 'Financial changes cannot rewrite a paid schedule');
select is((v1_get_rental_property(pg_temp.rental_id(10))->'lease'->>'monthly_rent')::numeric, 100::numeric, 'Rejected paid-schedule changes roll back the lease and property together');

select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(20, 21), null, pg_temp.rental_id(110))$$, 'Admin creates a second independent property');
select throws_ok($$select v1_save_rental_property(pg_temp.rental_payload(10, 21), 2, pg_temp.rental_id(111))$$, '23514', 'V1_RENTAL_LEASE_PROPERTY_MISMATCH', 'A supplied lease ID cannot rewrite another property lease');
select is(v1_get_rental_property(pg_temp.rental_id(20))->'lease'->>'tenant_name', 'Safety tenant 20', 'The rejected cross-property lease command preserves the other tenant');
select lives_ok($$select v1_save_rental_cheque(jsonb_build_object('cheque_id', pg_temp.rental_id(22), 'property_id', pg_temp.rental_id(20), 'lease_id', pg_temp.rental_id(21), 'period_id', (v1_get_rental_property(pg_temp.rental_id(20))->'periods'->0->>'id')::uuid, 'cheque_number', 'SAFE-CHEQUE', 'cheque_type', 'pdc', 'bank_name', 'Test bank', 'cheque_date', current_date, 'amount', 100), null, pg_temp.rental_id(112))$$, 'Admin links a cheque to a real period');
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(20, 21)||'{"email":"updated@example.invalid"}', 1, pg_temp.rental_id(113))$$, 'Metadata edits succeed with a cheque-linked schedule');
select is(v1_get_rental_property(pg_temp.rental_id(20))->'cheques'->0->>'period_id', v1_get_rental_property(pg_temp.rental_id(20))->'periods'->0->>'id', 'Cheque-linked metadata edits preserve period linkage');
select throws_ok($$select v1_save_rental_property(pg_temp.rental_payload(20, 21)||'{"monthly_rent":200}', 2, pg_temp.rental_id(114))$$, '23514', 'V1_RENTAL_LINKED_SCHEDULE_CANNOT_BE_REBUILT', 'Financial edits do not reinterpret a cheque-linked schedule');
select throws_ok($$select v1_transition_rental_cheque(pg_temp.rental_id(22), null, 'received', null, pg_temp.rental_id(115))$$, '40001', 'V1_RENTAL_CHEQUE_VERSION_CONFLICT', 'Cheque transitions require an expected version');
select throws_ok($$select v1_transition_rental_cheque(pg_temp.rental_id(22), 999, 'received', null, pg_temp.rental_id(116))$$, '40001', 'V1_RENTAL_CHEQUE_VERSION_CONFLICT', 'Cheque transitions reject stale expected versions');
select throws_ok($$select v1_save_rental_cheque(jsonb_build_object('cheque_id', pg_temp.rental_id(23), 'property_id', pg_temp.rental_id(20), 'lease_id', pg_temp.rental_id(21), 'cheque_number', 'MISSING-CHEQUE', 'cheque_type', 'pdc', 'bank_name', 'Test bank', 'cheque_date', current_date, 'amount', 100), 999, pg_temp.rental_id(117))$$, 'P0002', 'V1_RENTAL_CHEQUE_NOT_FOUND', 'A missing cheque update cannot silently become a create');
select lives_ok($$select v1_transition_rental_cheque(pg_temp.rental_id(22), 1, 'received', null, pg_temp.rental_id(118)); select v1_transition_rental_cheque(pg_temp.rental_id(22), 2, 'deposited', null, pg_temp.rental_id(119)); select v1_transition_rental_cheque(pg_temp.rental_id(22), 3, 'cleared', null, pg_temp.rental_id(120))$$, 'The valid cheque lifecycle remains available');
select throws_ok($$select v1_save_rental_cheque(jsonb_build_object('cheque_id', pg_temp.rental_id(22), 'property_id', pg_temp.rental_id(20), 'lease_id', pg_temp.rental_id(21), 'period_id', (v1_get_rental_property(pg_temp.rental_id(20))->'periods'->0->>'id')::uuid, 'cheque_number', 'SAFE-CHEQUE', 'cheque_type', 'pdc', 'bank_name', 'Test bank', 'cheque_date', current_date, 'amount', 50000), 4, pg_temp.rental_id(121))$$, '23514', 'V1_RENTAL_CHEQUE_TERMS_LOCKED', 'A cleared cheque cannot have its banking terms rewritten');

select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(30, 31, date_trunc('month', current_date)::date, (date_trunc('month', current_date)+interval '1 month - 1 day')::date), null, pg_temp.rental_id(130)); select v1_save_rental_property(pg_temp.rental_payload(30, 32, (date_trunc('month', current_date)+interval '1 month')::date, (date_trunc('month', current_date)+interval '2 month - 1 day')::date), 1, pg_temp.rental_id(131))$$, 'An explicit new current lease preserves the previous lease schedule');
select is((select (item->>'outstanding')::numeric from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'id'=pg_temp.rental_id(30)::text), 100::numeric, 'Previous-lease unpaid rent remains in the property portfolio balance');
select throws_ok($$select v1_save_rental_property(pg_temp.rental_payload(30, 31), 2, pg_temp.rental_id(132))$$, '23514', 'V1_RENTAL_HISTORICAL_LEASE_READ_ONLY', 'A historical lease cannot be silently resurrected over the current lease');
select is(jsonb_array_length(v1_get_rental_property(pg_temp.rental_id(30))->'periods'), 2, 'A rejected historical lease edit retains both schedules');

select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(40, 41, date_trunc('month', current_date)::date, (date_trunc('month', current_date)+interval '2 month - 1 day')::date, 'terminated'), null, pg_temp.rental_id(140)); select v1_record_rent_payment((v1_get_rental_property(pg_temp.rental_id(40))->'periods'->1->>'id')::uuid, 100, current_date, 'cash', null, null, pg_temp.rental_id(141))$$, 'A fixture prepays a future period while current rent remains unpaid');
select throws_ok($$select v1_archive_rental_property(pg_temp.rental_id(40), null, 'Test archive', pg_temp.rental_id(142))$$, '40001', 'V1_RENTAL_PROPERTY_VERSION_CONFLICT', 'Archive requires an expected property version');
select throws_ok($$select v1_archive_rental_property(pg_temp.rental_id(40), 1, 'Test archive', pg_temp.rental_id(143))$$, '23514', 'V1_RENTAL_ARCHIVE_BLOCKED_BY_OPEN_OBLIGATION', 'Future-period prepayments cannot hide current debt from the archive guard');
select is((v1_get_rental_property(pg_temp.rental_id(40))->'property'->>'is_archived')::boolean, false, 'A blocked archive leaves the property active');
select lives_ok($$select v1_record_rent_payment((v1_get_rental_property(pg_temp.rental_id(40))->'periods'->0->>'id')::uuid, 100, current_date, 'cash', null, null, pg_temp.rental_id(144)); select v1_archive_rental_property(pg_temp.rental_id(40), 1, 'Resolved obligations', pg_temp.rental_id(145))$$, 'A terminated lease with every due obligation settled can still be archived');

-- Unpaid schedule revisions keep surviving month IDs rather than replacing all
-- periods. This verifies preservation, without imposing a new rent policy.
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(50, 51), null, pg_temp.rental_id(150))$$, 'Admin creates an unreferenced unpaid schedule');
create temp table rental_unpaid_snapshot as select v1_get_rental_property(pg_temp.rental_id(50)) detail;
select lives_ok($$select v1_save_rental_property(pg_temp.rental_payload(50, 51)||'{"monthly_rent":200}', 1, pg_temp.rental_id(151))$$, 'Explicit unpaid financial revisions remain possible');
select is(v1_get_rental_property(pg_temp.rental_id(50))->'periods'->0->>'id', (select detail->'periods'->0->>'id' from rental_unpaid_snapshot), 'An unpaid financial revision preserves retained month identities');
select is((v1_get_rental_property(pg_temp.rental_id(50))->'periods'->0->>'amount_due')::numeric, 200::numeric, 'The authoritative revised amount is reflected in the existing period');

select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',pg_temp.rental_id(10),'contact_number','Sparse update'),2,pg_temp.rental_id(160))$$,'A sparse metadata edit preserves required identity and paid lease facts');
select is((v1_get_rental_property(pg_temp.rental_id(10))->'lease'->>'monthly_rent')::numeric,100::numeric,'Omitted rent remains unchanged on a sparse metadata edit');

select is(v1_get_rental_command_outcome('v1_record_rent_payment',pg_temp.rental_id(101))->>'state','confirmed','The original actor can confirm a committed payment without retrieving its raw payload');
select is(v1_get_rental_command_outcome('v1_record_rent_payment',pg_temp.rental_id(999))->>'state','unconfirmed','An unknown or in-flight key is never called a failed payment');
select throws_ok($$select v1_get_rental_command_outcome('unrelated_command',pg_temp.rental_id(101))$$,'22023','V1_RENTAL_COMMAND_INVALID','The outcome read cannot enumerate unrelated command families');
select is((v1_get_rental_property(pg_temp.rental_id(10))->'property'->>'outstanding')::numeric,90::numeric,'Property detail shows the same authoritative unpaid balance as the register');

reset role;
insert into v1_idempotency_keys(actor_auth_user_id,command_name,idempotency_key,request_hash,response_json)
values('10000000-0000-4000-8000-000000000003','v1_record_rent_payment',pg_temp.rental_id(999),'other-actor-fixture','{"receipt_id":"protected"}');
set local role authenticated;
select is(v1_get_rental_command_outcome('v1_record_rent_payment',pg_temp.rental_id(999))->>'state','unconfirmed','An Admin outcome lookup never exposes another actor command completion');
reset role;
update v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok($$select v1_get_rental_property(pg_temp.rental_id(10))$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'An inactive Admin profile cannot read property or receipt details');
select throws_ok($$select v1_get_rental_export_data()$$, '42501', 'V1_RENTAL_ADMIN_REQUIRED', 'An inactive Admin profile cannot export protected rental facts');

select throws_ok($$select v1_get_rental_command_outcome('v1_record_rent_payment',pg_temp.rental_id(101))$$,'42501','V1_RENTAL_ADMIN_REQUIRED','An inactive Admin cannot query payment completion state');
select * from finish();
rollback;

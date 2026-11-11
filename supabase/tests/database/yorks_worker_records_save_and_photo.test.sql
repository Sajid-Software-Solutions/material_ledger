begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated', 'public.v1_save_worker_record(jsonb,bigint,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_set_worker_photo(uuid,text,bigint,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon', 'public.v1_save_worker_record(jsonb,bigint,uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_worker_employment_record_snapshot(uuid)', 'execute'
  ),
  'Only the two reviewed write RPCs are client-callable'
);

-- A worker that exists in Workforce but has no employment record yet.
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
) values (
  '7c000000-0000-4000-8000-000000000001', 'WR-SAVE-001',
  'Save Test Existing', 'Technician', 'Yorks Test Company LLC',
  'yorks_employee', '2026-01-01',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
-- View-only grant for the Site Engineer (a PR officer without manage).
insert into public.v1_permission_assignments(
  id, auth_user_id, capability_key, effect, scope_kind, origin,
  effective_from, reason, changed_by_auth_user_id
) values (
  '7c100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  'worker_records.view', 'grant', 'organization', 'permission_management',
  '2026-08-01', 'View-only worker records test',
  '10000000-0000-4000-8000-000000000004'
);

-- Accountant creates, retries and updates -------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

select is(
  public.v1_save_worker_record(
    '{"full_name":"Save Test New","designation":"Helper","employer_company":"Yorks Test Company LLC","joining_date":"2026-11-01","trade_license_no":"CN-SAVE-1","passport_no":" qq7654321 ","basic_salary":"700","housing_allowance":"500","other_allowance":"0"}'::jsonb,
    null, '7c200000-0000-4000-8000-000000000001'
  ) ->> 'total_salary',
  '1200.00',
  'Accountant creates a new worker with a record'
);
select is(
  public.v1_save_worker_record(
    '{"full_name":"Save Test New","designation":"Helper","employer_company":"Yorks Test Company LLC","joining_date":"2026-11-01","trade_license_no":"CN-SAVE-1","passport_no":" qq7654321 ","basic_salary":"700","housing_allowance":"500","other_allowance":"0"}'::jsonb,
    null, '7c200000-0000-4000-8000-000000000001'
  ) ->> 'passport_no',
  'QQ7654321',
  'A retry with the same key returns the same record; the passport is normalized'
);
reset role;
select is(
  (select count(*) from public.v1_workforce_workers
   where full_name = 'Save Test New'),
  1::bigint,
  'The retry did not create a second worker'
);
select is(
  (select count(*) from public.v1_worker_employment_record_revisions revision
   join public.v1_workforce_workers worker on worker.id = revision.worker_id
   where worker.full_name = 'Save Test New'),
  1::bigint,
  'The retry did not append a second revision'
);
select ok(
  (select response_json::text from public.v1_idempotency_keys
   where idempotency_key = '7c200000-0000-4000-8000-000000000001')
    !~* 'salary|passport|QQ7654321',
  'The idempotency ledger stores no salary or passport value'
);
select ok(
  not exists (
    select 1 from public.v1_audit_events event
    where event.entity_type = 'worker_employment_record'
      and (coalesce(event.before_data, '{}'::jsonb)::text
        || coalesce(event.after_data, '{}'::jsonb)::text)
        ~* 'QQ7654321|1200'
  ),
  'The audit trail records changed field names, not values'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);
select is(
  public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Save Test Existing","designation":"Technician","employer_company":"Yorks Test Company LLC","basic_salary":"950.50","housing_allowance":"500","other_allowance":"150"}'::jsonb,
    0, '7c200000-0000-4000-8000-000000000002'
  ) ->> 'total_salary',
  '1600.50',
  'A first record is added to an existing worker at expected version 0'
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Save Test Existing","designation":"Technician","employer_company":"Yorks Test Company LLC","basic_salary":"1"}'::jsonb,
    0, '7c200000-0000-4000-8000-000000000003')$$,
  '40001', null,
  'A stale version is a conflict and overwrites nothing'
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Save Test Existing","designation":"Technician","employer_company":"Yorks Test Company LLC","passport_no":"QQ7654321"}'::jsonb,
    1, '7c200000-0000-4000-8000-000000000004')$$,
  '23505', null,
  'A passport already held by another worker is refused'
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Save Test Existing","designation":"Technician","employer_company":"Yorks Test Company LLC","basic_salary":"-5"}'::jsonb,
    1, '7c200000-0000-4000-8000-000000000005')$$,
  '22023', null,
  'A negative amount is refused'
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Save Test Existing","designation":"Technician","employer_company":"Yorks Test Company LLC","current_status":"left_company"}'::jsonb,
    1, '7c200000-0000-4000-8000-000000000006')$$,
  null, null,
  'Status and other Workforce fields cannot be changed through this command'
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"full_name":"No Joining Date","designation":"Helper","employer_company":"Yorks Test Company LLC"}'::jsonb,
    null, '7c200000-0000-4000-8000-000000000007')$$,
  '22023', null,
  'A new worker needs a joining date'
);
select throws_ok(
  $$select public.v1_set_worker_photo(
    '7c000000-0000-4000-8000-000000000001',
    'workers/7c000000-0000-4000-8000-000000000001/7d000000-0000-4000-8000-000000000001.jpg',
    1, '7c200000-0000-4000-8000-000000000008')$$,
  '22023', null,
  'A photo that was never stored cannot be attached'
);
reset role;

select is(
  (select current_status from public.v1_workforce_workers
   where id = '7c000000-0000-4000-8000-000000000001'),
  'active',
  'Refused commands left the worker unchanged'
);

-- Photo: stored object, then attach --------------------------------------------

insert into storage.objects (bucket_id, name, owner)
values (
  'yorks-worker-photos',
  'workers/7c000000-0000-4000-8000-000000000001/7d000000-0000-4000-8000-000000000002.jpg',
  '10000000-0000-4000-8000-000000000013'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);
select is(
  public.v1_set_worker_photo(
    '7c000000-0000-4000-8000-000000000001',
    'workers/7c000000-0000-4000-8000-000000000001/7d000000-0000-4000-8000-000000000002.jpg',
    1, '7c200000-0000-4000-8000-000000000009'
  ) ->> 'record_version',
  '2',
  'Attaching a stored photo advances the record version'
);
select throws_ok(
  $$select public.v1_set_worker_photo(
    '7c000000-0000-4000-8000-000000000001',
    'workers/7c000000-0000-4000-8000-000000000001/7d000000-0000-4000-8000-000000000002.jpg',
    1, '7c200000-0000-4000-8000-00000000000a')$$,
  '40001', null,
  'A stale version cannot replace the photo'
);
reset role;

-- View-only and ungranted actors -------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"worker_id":"7c000000-0000-4000-8000-000000000001","full_name":"Changed","designation":"Technician","employer_company":"Yorks Test Company LLC"}'::jsonb,
    2, '7c200000-0000-4000-8000-00000000000b')$$,
  '42501', null,
  'A view-only holder cannot save a record'
);
select throws_ok(
  $$select public.v1_set_worker_photo(
    '7c000000-0000-4000-8000-000000000001',
    'workers/7c000000-0000-4000-8000-000000000001/7d000000-0000-4000-8000-000000000002.jpg',
    2, '7c200000-0000-4000-8000-00000000000c')$$,
  '42501', null,
  'A view-only holder cannot set a photo'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"full_name":"Intruder","designation":"Helper","employer_company":"X","joining_date":"2026-11-01"}'::jsonb,
    null, '7c200000-0000-4000-8000-00000000000d')$$,
  '42501', null,
  'Project Engineer cannot create a worker record'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_save_worker_record(
    '{"full_name":"Intruder","designation":"Helper","employer_company":"X","joining_date":"2026-11-01"}'::jsonb,
    null, '7c200000-0000-4000-8000-00000000000e')$$,
  '42501', null,
  'Procurement cannot create a worker record'
);
reset role;

select is(
  (select count(*) from public.v1_worker_employment_record_revisions
   where worker_id = '7c000000-0000-4000-8000-000000000001'),
  2::bigint,
  'Exactly one revision per committed change (create, photo)'
);

select * from finish();
rollback;

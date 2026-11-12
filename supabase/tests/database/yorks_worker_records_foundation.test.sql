begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Catalogue and role templates -------------------------------------------------

select is(
  (select count(*) from public.v1_capability_catalog catalog
   where catalog.capability_key in (
     'worker_records.view', 'worker_records.manage'
   )
     and catalog.module_key = 'worker_records'
     and catalog.status = 'operational'
     and catalog.authorization_mode = 'enforced'
     and catalog.is_assignable
     and catalog.allowed_scope_kinds = array['organization']::text[]),
  2::bigint,
  'Both worker record capabilities are enforced, assignable and organization-wide'
);
select is(
  (select dependencies from public.v1_capability_catalog
   where capability_key = 'worker_records.view'),
  '{}'::text[],
  'Viewing worker records does not depend on Workforce access'
);
select is(
  (select count(*) from public.v1_capability_catalog catalog
   where public.v1_workforce_is_capability_key(catalog.capability_key)),
  12::bigint,
  'The Workforce capability family still has exactly twelve keys'
);
select is(
  (select array_agg(role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key = 'worker_records.view' and is_granted),
  array['accountant', 'admin', 'pr']::text[],
  'Only Admin, Accountant and PR hold worker record access by default'
);
select is(
  (select array_agg(role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key = 'worker_records.manage' and can_delegate),
  array['admin', 'pr']::text[],
  'Only Admin and PR may delegate worker record access'
);

-- Accountant boundary: only the two worker record keys are added -----------------

select ok(
  public.v1_accountant_may_hold_capability('worker_records.view')
  and public.v1_accountant_may_hold_capability('worker_records.manage')
  and public.v1_accountant_may_hold_capability('view_project_accounts')
  and not public.v1_accountant_may_hold_capability('projects.create')
  and not public.v1_accountant_may_hold_capability('boq.edit')
  and not public.v1_accountant_may_hold_capability('inventory.adjust')
  and not public.v1_accountant_may_hold_capability('users.view')
  and not public.v1_accountant_may_hold_capability('workforce.view'),
  'Accountant may hold Accounts keys and the two worker record keys only'
);
select ok(
  (public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000013', 'worker_records.manage', null
  ) ->> 'effective')::boolean,
  'The resolver grants Accountant worker record management'
);
select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000013', 'projects.create', null
  ) ->> 'source',
  'hard_invariant',
  'The resolver still refuses Accountant a technical capability'
);
select throws_ok(
  $$insert into public.v1_permission_assignments(
      id, auth_user_id, capability_key, effect, scope_kind, origin,
      effective_from, reason, changed_by_auth_user_id
    ) values (
      '7a200000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000013',
      'boq.edit', 'grant', 'organization', 'permission_management',
      '2026-08-01', 'Boundary test',
      '10000000-0000-4000-8000-000000000004'
    )$$,
  '42501', null,
  'An Accountant still cannot be granted a non-Accounts technical capability'
);
select lives_ok(
  $$insert into public.v1_permission_assignments(
      id, auth_user_id, capability_key, effect, scope_kind, origin,
      effective_from, reason, changed_by_auth_user_id
    ) values (
      '7a200000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000013',
      'worker_records.view', 'grant', 'organization', 'permission_management',
      '2026-08-01', 'Boundary test',
      '10000000-0000-4000-8000-000000000004'
    )$$,
  'An Accountant may be granted a worker record capability'
);

-- Protected relations -----------------------------------------------------------

select ok(
  not has_table_privilege(
    'authenticated', 'public.v1_worker_employment_records', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_worker_employment_records', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_worker_employment_records', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_worker_employment_record_revisions', 'select'
  )
  and not has_table_privilege(
    'anon', 'public.v1_worker_employment_records', 'select'
  ),
  'Salary and passport relations have no ordinary table access'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_list_worker_records(text,text,text,integer,integer)', 'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_get_worker_record(uuid)', 'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_list_worker_records(text,text,text,integer,integer)', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_worker_record_json(uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_worker_records_assert(text)', 'execute'
  ),
  'Only the two reviewed read RPCs are client-callable'
);

-- Fixtures ----------------------------------------------------------------------

insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
) values
  ('7a000000-0000-4000-8000-000000000001', 'WR-TEST-001',
   'Record Test Alpha', 'Technician', 'Yorks Test Company LLC',
   'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('7a000000-0000-4000-8000-000000000002', 'WR-TEST-002',
   'Record Test Beta', 'Helper', 'Other Test Company WLL',
   'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004');

insert into public.v1_worker_employment_records (
  worker_id, trade_license_no, passport_no, basic_salary, housing_allowance,
  other_allowance, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values (
  '7a000000-0000-4000-8000-000000000001', 'CN-TEST-1', 'ZZ1234567',
  950, 500, 150,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

select is(
  (select total_salary from public.v1_worker_employment_records
   where worker_id = '7a000000-0000-4000-8000-000000000001'),
  1600.00::numeric,
  'Total salary is basic + housing + others'
);
select throws_ok(
  $$insert into public.v1_worker_employment_records (
      worker_id, passport_no, created_by_auth_user_id,
      updated_by_auth_user_id, updated_by_role
    ) values (
      '7a000000-0000-4000-8000-000000000002', ' zz1234567 ',
      '10000000-0000-4000-8000-000000000004',
      '10000000-0000-4000-8000-000000000004', 'admin'
    )$$,
  '23505', null,
  'One passport number cannot belong to two workers'
);
select throws_ok(
  $$delete from public.v1_worker_employment_records
    where worker_id = '7a000000-0000-4000-8000-000000000001'$$,
  '55000', null,
  'A worker employment record cannot be hard-deleted'
);

-- Per-person grant models the audited User Access command for a PR officer.
insert into public.v1_permission_assignments(
  id, auth_user_id, capability_key, effect, scope_kind, origin,
  effective_from, reason, changed_by_auth_user_id
) values (
  '7a100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  'worker_records.view', 'grant', 'organization', 'permission_management',
  '2026-08-01', 'PR officer worker records test',
  '10000000-0000-4000-8000-000000000004'
);

-- Positive: Admin ---------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select is(
  public.v1_get_worker_record('7a000000-0000-4000-8000-000000000001')
    ->> 'total_salary',
  '1600.00',
  'Admin reads a worker record with decimal-text money'
);
select is(
  public.v1_get_worker_record('7a000000-0000-4000-8000-000000000002')
    -> 'basic_salary',
  'null'::jsonb,
  'A worker without a record reports salary as not entered, never zero'
);
select is(
  (public.v1_list_worker_records('record test', null, null, 50, 0)
    ->> 'total_count')::integer,
  2,
  'Search finds workers by name'
);
select is(
  (public.v1_list_worker_records('zz1234', null, null, 50, 0)
    ->> 'total_count')::integer,
  1,
  'Search finds a worker by passport number'
);
select is(
  public.v1_list_worker_records(
    'record test', 'yorks test company llc', null, 50, 0
  ) -> 'totals' ->> 'total_salary',
  '1600.00',
  'Company filter and totals apply to the filtered set'
);
select throws_ok(
  $$select public.v1_list_worker_records(null, null, 'retired', 50, 0)$$,
  '22023', null,
  'An unknown status filter is rejected'
);
select throws_ok(
  $$select public.v1_get_worker_record(
      '7a000000-0000-4000-8000-0000000000ff')$$,
  'P0002', null,
  'An unknown worker is reported as not found'
);
select throws_ok(
  $$select count(*) from public.v1_worker_employment_records$$,
  '42501', null,
  'Even Admin cannot read the protected relation directly'
);
reset role;

-- Positive: Accountant ----------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);
select is(
  public.v1_get_worker_record('7a000000-0000-4000-8000-000000000001')
    ->> 'passport_no',
  'ZZ1234567',
  'Accountant reads worker records'
);
select ok(
  public.v1_worker_photo_writable(
    'yorks-worker-photos',
    'workers/7a000000-0000-4000-8000-000000000001/7b000000-0000-4000-8000-000000000001.jpg'
  ),
  'Accountant may store a photo for an existing worker'
);
select ok(
  not public.v1_worker_photo_writable(
    'yorks-worker-photos',
    'workers/7a000000-0000-4000-8000-0000000000ff/7b000000-0000-4000-8000-000000000001.jpg'
  ),
  'A photo cannot be stored for a worker that does not exist'
);
select ok(
  not public.v1_worker_photo_writable(
    'yorks-worker-photos', 'workers/../other/file.jpg'
  )
  and not public.v1_worker_photo_readable(
    'yorks-chat-attachments',
    'workers/7a000000-0000-4000-8000-000000000001/7b000000-0000-4000-8000-000000000001.jpg'
  ),
  'Malformed paths and other buckets are refused'
);
reset role;

-- Positive: per-person grant (view only) ----------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_list_worker_records(null, null, null, 50, 0)$$,
  'A user granted view per person can list worker records'
);
select ok(
  public.v1_worker_photo_readable(
    'yorks-worker-photos',
    'workers/7a000000-0000-4000-8000-000000000001/7b000000-0000-4000-8000-000000000001.jpg'
  )
  and not public.v1_worker_photo_writable(
    'yorks-worker-photos',
    'workers/7a000000-0000-4000-8000-000000000001/7b000000-0000-4000-8000-000000000001.jpg'
  ),
  'A view-only holder can see photos but cannot store one'
);
reset role;

-- Negative: every role without the capability ----------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_list_worker_records(null, null, null, 50, 0)$$,
  '42501', null, 'Project Engineer cannot list worker records'
);
select throws_ok(
  $$select public.v1_get_worker_record(
      '7a000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'Project Engineer cannot open a worker record'
);
select throws_ok(
  $$select count(*) from public.v1_worker_employment_records$$,
  '42501', null, 'Project Engineer cannot query the relation'
);
select ok(
  not public.v1_worker_photo_readable(
    'yorks-worker-photos',
    'workers/7a000000-0000-4000-8000-000000000001/7b000000-0000-4000-8000-000000000001.jpg'
  ),
  'Project Engineer cannot read a worker photo by knowing its path'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_list_worker_records(null, null, null, 50, 0)$$,
  '42501', null, 'Procurement cannot list worker records'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_list_worker_records(null, null, null, 50, 0)$$,
  '42501', null,
  'Senior Mechanical Engineer manages users but not worker records'
);
reset role;

-- Workforce projections stay free of pay and passport data ----------------------

select ok(
  public.v1_workforce_worker_json(
    '7a000000-0000-4000-8000-000000000001', current_date
  )::text !~* 'salary|passport|allowance|trade_license',
  'The Workforce worker projection carries no pay or passport field'
);

select * from finish();
rollback;

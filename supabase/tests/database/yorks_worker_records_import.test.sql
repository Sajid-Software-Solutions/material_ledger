begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated', 'public.v1_preview_worker_records_import(jsonb)',
    'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_import_worker_records(jsonb,uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_worker_import_classify(jsonb)', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.v1_import_worker_records(jsonb,uuid)', 'execute'
  ),
  'Only preview and import are client-callable'
);

-- Existing state: one worker with a record, one without, two namesakes.
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
) values
  ('7e000000-0000-4000-8000-000000000001', 'WR-IMP-001', 'Import Known',
   'Technician', 'Import Test Co', 'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('7e000000-0000-4000-8000-000000000002', 'WR-IMP-002', 'Import No Record',
   'Helper', 'Import Test Co', 'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('7e000000-0000-4000-8000-000000000003', 'WR-IMP-003', 'Import Twin',
   'Helper', 'Import Test Co', 'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('7e000000-0000-4000-8000-000000000004', 'WR-IMP-004', 'Import  twin',
   'Helper', 'import test co', 'yorks_employee', '2026-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004');
insert into public.v1_worker_employment_records (
  worker_id, trade_license_no, passport_no, basic_salary, housing_allowance,
  other_allowance, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values (
  '7e000000-0000-4000-8000-000000000001', 'CN-IMP-1', 'IM1000001',
  700, 500, 0,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

create temporary table import_rows on commit drop as
select '[
  {"row_number":2,"full_name":"Import Known","employer_company":"Import Test Co","passport_no":"im1000001","basic_salary":"950","housing_allowance":"","other_allowance":"150"},
  {"row_number":3,"full_name":"IMPORT  NO RECORD","employer_company":"import test co","trade_license_no":"CN-IMP-2","passport_no":"IM1000002","basic_salary":"700","housing_allowance":"500","other_allowance":"0"},
  {"row_number":4,"full_name":"Import New Person","employer_company":"Import Test Co","passport_no":"IM1000003","basic_salary":"800","housing_allowance":"550","other_allowance":"0"},
  {"row_number":5,"full_name":"Import Known","employer_company":"Import Test Co","passport_no":"IM1000001","basic_salary":"950","housing_allowance":"500","other_allowance":"150"}
]'::jsonb as rows_ok;

grant select on import_rows to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

-- Preview: errors are reported per row and nothing is written.
select is(
  (select jsonb_agg(row ->> 'action' order by (row ->> 'index')::int)
   from jsonb_array_elements(
     public.v1_preview_worker_records_import((select rows_ok from import_rows))
       -> 'rows'
   ) row),
  '["update","update","create","error"]'::jsonb,
  'Passport match, name+company match, new person, and a repeated row'
);
select is(
  public.v1_preview_worker_records_import((select rows_ok from import_rows))
    -> 'rows' -> 3 -> 'errors',
  '["duplicate_in_file"]'::jsonb,
  'A person repeated in the file is a row error'
);
select is(
  public.v1_preview_worker_records_import((select rows_ok from import_rows))
    -> 'rows' -> 0 -> 'changed_fields',
  '["basic_salary","other_allowance"]'::jsonb,
  'A blank cell is not a change; only differing values are'
);
select is(
  (public.v1_preview_worker_records_import(
    '[{"row_number":2,"full_name":"Import Twin","employer_company":"Import Test Co"}]'::jsonb
  ) -> 'rows' -> 0 -> 'errors'),
  '["ambiguous_match"]'::jsonb,
  'Two existing workers with the same name and company are ambiguous'
);
select is(
  (public.v1_preview_worker_records_import(
    '[{"row_number":2,"full_name":"Someone Else","employer_company":"Import Test Co","passport_no":"IM1000001"}]'::jsonb
  ) -> 'rows' -> 0 -> 'errors'),
  '["passport_other_worker"]'::jsonb,
  'A passport already held by a differently named worker is refused'
);
select is(
  (public.v1_preview_worker_records_import(
    '[{"row_number":2,"full_name":"Import Known","employer_company":"Import Test Co","passport_no":"ZZ9999999"}]'::jsonb
  ) -> 'rows' -> 0 -> 'errors'),
  '["passport_differs"]'::jsonb,
  'A matched worker whose stored passport differs is refused'
);
select is(
  (public.v1_preview_worker_records_import(
    '[{"row_number":2,"full_name":"","employer_company":"Import Test Co","basic_salary":"7,00"}]'::jsonb
  ) -> 'rows' -> 0 -> 'errors'),
  '["name_required","amount_invalid"]'::jsonb,
  'Missing name and malformed amount are reported'
);
select throws_ok(
  $$select public.v1_preview_worker_records_import(
      '[{"row_number":2,"full_name":"X","employer_company":"Y","salary":"1"}]'::jsonb)$$,
  '22023', null,
  'An unknown column key is refused'
);
reset role;
select is(
  (select count(*) from public.v1_workforce_workers
   where full_name = 'Import New Person'),
  0::bigint,
  'Preview wrote nothing'
);

-- Import: refused while any row has an error.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);
select throws_ok(
  $$select public.v1_import_worker_records(
      jsonb_build_object(
        'rows', (select rows_ok from import_rows),
        'expected', public.v1_preview_worker_records_import(
          (select rows_ok from import_rows)) -> 'rows',
        'new_worker_designation', 'Technician',
        'new_worker_joining_date', '2026-11-01'),
      '7e100000-0000-4000-8000-000000000001')$$,
  '22023', null,
  'A file with any row error is refused as a whole'
);
reset role;

-- Drop the repeated row and import the remaining three.
update import_rows set rows_ok = rows_ok - 3;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);
select throws_ok(
  $$select public.v1_import_worker_records(
      jsonb_build_object(
        'rows', (select rows_ok from import_rows),
        'expected', public.v1_preview_worker_records_import(
          (select rows_ok from import_rows)) -> 'rows'),
      '7e100000-0000-4000-8000-000000000002')$$,
  '22023', null,
  'New workers need an explicit designation and joining date'
);
create temporary table import_payload (payload jsonb) on commit drop;
grant select, insert on import_payload to authenticated;
insert into import_payload
select jsonb_build_object(
  'rows', (select rows_ok from import_rows),
  'expected', public.v1_preview_worker_records_import(
    (select rows_ok from import_rows)) -> 'rows',
  'new_worker_designation', 'Technician',
  'new_worker_joining_date', '2026-11-01');
select is(
  public.v1_import_worker_records(
    (select payload from import_payload),
    '7e100000-0000-4000-8000-000000000003'
  ) - 'schema_version',
  '{"created_count":1,"updated_count":2,"unchanged_count":0}'::jsonb,
  'The import creates one worker and updates two'
);
select is(
  public.v1_import_worker_records(
    (select payload from import_payload),
    '7e100000-0000-4000-8000-000000000003'
  ) - 'schema_version',
  '{"created_count":1,"updated_count":2,"unchanged_count":0}'::jsonb,
  'A retry with the same key returns the same result'
);
select throws_ok(
  $$select public.v1_import_worker_records(
      (select payload from import_payload),
      '7e100000-0000-4000-8000-000000000004')$$,
  '40001', null,
  'Replaying an old preview after the data changed is a conflict'
);
reset role;

select is(
  (select count(*) from public.v1_workforce_workers
   where full_name = 'Import New Person'),
  1::bigint,
  'The retry did not create the new worker twice'
);
select is(
  (select (basic_salary, housing_allowance, other_allowance)::text
   from public.v1_worker_employment_records
   where worker_id = '7e000000-0000-4000-8000-000000000001'),
  '(950.00,500.00,150.00)',
  'A blank Housing cell kept the stored 500'
);
select is(
  (select designation || '|' || joining_date::text
   from public.v1_workforce_workers where full_name = 'Import New Person'),
  'Technician|2026-11-01',
  'The new worker uses the chosen designation and joining date'
);
select is(
  (select full_name from public.v1_workforce_workers
   where id = '7e000000-0000-4000-8000-000000000002'),
  'Import No Record',
  'An import never renames an existing worker'
);
select is(
  (select count(*) from public.v1_worker_employment_record_revisions
   where idempotency_key = '7e100000-0000-4000-8000-000000000003'
     and change_kind = 'imported'),
  3::bigint,
  'One imported revision per changed worker'
);
select ok(
  (select after_data::text from public.v1_audit_events
   where entity_type = 'worker_records_import'
     and entity_id = '7e100000-0000-4000-8000-000000000003')
    !~* 'IM10000|950|Import',
  'The import audit event holds counts only'
);
select ok(
  (select response_json::text from public.v1_idempotency_keys
   where idempotency_key = '7e100000-0000-4000-8000-000000000003')
    !~* 'IM10000|950|Import',
  'The idempotency ledger holds counts only'
);

-- View-only and ungranted actors ------------------------------------------------

insert into public.v1_permission_assignments(
  id, auth_user_id, capability_key, effect, scope_kind, origin,
  effective_from, reason, changed_by_auth_user_id
) values (
  '7e200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  'worker_records.view', 'grant', 'organization', 'permission_management',
  '2026-08-01', 'View-only import test',
  '10000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_preview_worker_records_import(
      '[{"row_number":2,"full_name":"X","employer_company":"Y"}]'::jsonb)$$,
  '42501', null,
  'A view-only holder cannot preview an import'
);
select throws_ok(
  $$select public.v1_import_worker_records(
      '{"rows":[{"row_number":2,"full_name":"X","employer_company":"Y"}],"expected":[{"action":"create"}]}'::jsonb,
      '7e100000-0000-4000-8000-000000000005')$$,
  '42501', null,
  'A view-only holder cannot import'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_import_worker_records(
      '{"rows":[{"row_number":2,"full_name":"X","employer_company":"Y"}],"expected":[{"action":"create"}]}'::jsonb,
      '7e100000-0000-4000-8000-000000000006')$$,
  '42501', null,
  'Procurement cannot import'
);
reset role;

select * from finish();
rollback;

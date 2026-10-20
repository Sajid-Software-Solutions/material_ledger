begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(36);

select ok(
  has_function_privilege(
    'authenticated', 'public.v1_get_rental_portfolio()', 'execute'
  ) and has_function_privilege(
    'authenticated', 'public.v1_save_rental_property(jsonb,integer,uuid)', 'execute'
  ),
  'Authenticated clients can reach rentals only through the trusted RPC boundary'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_get_rental_portfolio()$$,
  '42501', 'V1_RENTAL_ADMIN_REQUIRED',
  'Project Engineer cannot read the Admin rental portfolio'
);
select throws_ok(
  $$select public.v1_save_rental_property(
    '{"unit_code":"RU-DENIED","property_name":"Denied","property_type":"shop","location":"Abu Dhabi","occupied":false}'::jsonb,
    null,
    '84000000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'V1_RENTAL_ADMIN_REQUIRED',
  'Project Engineer cannot create a rental property'
);
select throws_ok(
  $$select public.v1_get_rental_export_data()$$,
  '42501', 'V1_RENTAL_ADMIN_REQUIRED',
  'Project Engineer cannot export the commercial rental registers'
);
select throws_ok(
  $$select public.v1_import_rental_workbook(
    '{"properties":[],"payments":[],"cheques":[]}'::jsonb,
    '84000000-0000-4000-8000-000000000002'
  )$$,
  '42501', 'V1_RENTAL_ADMIN_REQUIRED',
  'Project Engineer cannot import rental master or payment data'
);
select throws_ok(
  $$insert into public.v1_rental_properties (
    id, unit_code, property_name, property_type, location,
    created_by_auth_user_id, updated_by_auth_user_id
  ) values (
    '84000000-0000-4000-8000-000000000099', 'RU-FORGED', 'Forged',
    'shop', 'Abu Dhabi', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for table v1_rental_properties',
  'Direct writes remain denied even to authenticated users'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_save_rental_property(
    '{
      "property_id":"84000000-0000-4000-8000-000000000010",
      "lease_id":"84000000-0000-4000-8000-000000000011",
      "unit_code":"ru-004","property_name":"Mussafah Shop 04",
      "property_type":"shop","municipality_number":"M37-S04",
      "location":"Mussafah M-37","occupied":true,
      "tenant_name":"Gulf Air Ducts Co.","contract_number":"TC-RU-004-2026",
      "contract_type":"tenancy_contract","contract_status":"active",
      "lease_start":"2026-08-01","lease_end":"2026-10-31",
      "monthly_rent":"14000","security_deposit":"28000",
      "monthly_due_day":1,"grace_period_days":5,
      "default_payment_method":"bank_transfer",
      "contract_cheque_count":3,"annual_escalation_percent":"5",
      "renewal_notice_days":90
    }'::jsonb,
    null,
    '84000000-0000-4000-8000-000000000012'
  )$$,
  'Admin can atomically create an occupied property and lease'
);
select is(
  (public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
    -> 'property' ->> 'unit_code'),
  'RU-004',
  'The stable Unit Code is normalized without changing identity'
);
select is(
  jsonb_array_length(
    public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'periods'
  ),
  3,
  'The authoritative lease generates one monthly rent period per month'
);
select lives_ok(
  $$select public.v1_save_rental_property(
    '{
      "property_id":"84000000-0000-4000-8000-000000000010",
      "lease_id":"84000000-0000-4000-8000-000000000011",
      "unit_code":"ru-004","property_name":"Mussafah Shop 04",
      "property_type":"shop","municipality_number":"M37-S04",
      "location":"Mussafah M-37","occupied":true,
      "tenant_name":"Gulf Air Ducts Co.","contract_number":"TC-RU-004-2026",
      "contract_type":"tenancy_contract","contract_status":"active",
      "lease_start":"2026-08-01","lease_end":"2026-10-31",
      "monthly_rent":"14000","security_deposit":"28000",
      "monthly_due_day":1,"grace_period_days":5,
      "default_payment_method":"bank_transfer",
      "contract_cheque_count":3,"annual_escalation_percent":"5",
      "renewal_notice_days":90
    }'::jsonb,
    null,
    '84000000-0000-4000-8000-000000000012'
  )$$,
  'A lost-response property retry returns the committed result'
);
select is(
  jsonb_array_length(public.v1_get_rental_portfolio() -> 'properties'),
  1,
  'The property retry cannot duplicate a property'
);

select lives_ok(
  $$select public.v1_record_rent_payment(
    (public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'periods' -> 0 ->> 'id')::uuid,
    6000, '2026-08-05', 'bank_transfer', 'RENT-004-01', 'Part receipt',
    '84000000-0000-4000-8000-000000000020'
  )$$,
  'Admin can record a partial payment against one rent period'
);
select is(
  (public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
    -> 'periods' -> 0 ->> 'status'),
  case when public.v1_rental_business_date() > date '2026-08-06'
    then 'overdue' else 'partially_paid' end,
  'A partial receipt retains its balance and becomes Overdue after its grace period'
);
select lives_ok(
  $$select public.v1_record_rent_payment(
    (public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'periods' -> 0 ->> 'id')::uuid,
    6000, '2026-08-05', 'bank_transfer', 'RENT-004-01', 'Part receipt',
    '84000000-0000-4000-8000-000000000020'
  )$$,
  'A payment retry returns the original committed receipt'
);
select is(
  jsonb_array_length(
    public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'receipts'
  ),
  1,
  'The payment retry cannot duplicate a receipt'
);
select throws_ok(
  $$select public.v1_record_rent_payment(
    (public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'periods' -> 0 ->> 'id')::uuid,
    9000, '2026-08-06', 'cash', null, null,
    '84000000-0000-4000-8000-000000000021'
  )$$,
  '23514', 'V1_RENTAL_PAYMENT_EXCEEDS_BALANCE',
  'A receipt cannot overpay its rent period'
);

select lives_ok(
  $$select public.v1_save_rental_cheque(
    '{
      "cheque_id":"84000000-0000-4000-8000-000000000030",
      "property_id":"84000000-0000-4000-8000-000000000010",
      "lease_id":"84000000-0000-4000-8000-000000000011",
      "cheque_number":"PDC-004-01","cheque_type":"pdc",
      "bank_name":"Yorks Bank","cheque_date":"2026-09-01",
      "amount":"14000"
    }'::jsonb,
    null,
    '84000000-0000-4000-8000-000000000031'
  )$$,
  'Admin can schedule a PDC without marking rent paid'
);
select is(
  jsonb_array_length(
    public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'receipts'
  ),
  1,
  'Saving a cheque never fabricates a rent receipt'
);
select lives_ok(
  $$select public.v1_transition_rental_cheque(
    '84000000-0000-4000-8000-000000000030', 1, 'received', null,
    '84000000-0000-4000-8000-000000000032'
  )$$,
  'The cheque lifecycle accepts the next valid state'
);
select throws_ok(
  $$select public.v1_transition_rental_cheque(
    '84000000-0000-4000-8000-000000000030', 2, 'cleared', null,
    '84000000-0000-4000-8000-000000000033'
  )$$,
  '23514', 'V1_RENTAL_CHEQUE_TRANSITION_INVALID',
  'The cheque lifecycle rejects skipped states'
);
select is(
  (public.v1_get_rental_portfolio() -> 'summary' ->> 'monthly_rent_roll')::numeric,
  14000::numeric,
  'Portfolio rent roll is not multiplied by periods or cheques'
);
select throws_ok(
  $$select public.v1_archive_rental_property(
    '84000000-0000-4000-8000-000000000010', 1, 'Attempt with open lease',
    '84000000-0000-4000-8000-000000000040'
  )$$,
  '23514', 'V1_RENTAL_ARCHIVE_BLOCKED_BY_OPEN_OBLIGATION',
  'A property with an active lease, balance or cheque cannot be archived'
);
select ok(
  jsonb_array_length(
    public.v1_get_rental_property('84000000-0000-4000-8000-000000000010')
      -> 'activity'
  ) > 0,
  'Rental commands append actor-attributed audit history'
);

select is(
  jsonb_array_length(public.v1_get_rental_export_data() -> 'properties'),
  1,
  'Admin export returns the current property register without table access'
);
select lives_ok(
  $$select public.v1_import_rental_workbook(
    '{
      "file_name":"rental-import.xlsx",
      "properties":[{
        "source_row":2,"action":"create","unit_code":"RU-005",
        "property_name":"Mussafah Shop 05","property_type":"shop",
        "municipality_number":"M37-S05","location":"Mussafah M-37",
        "occupied":true,"tenant_name":"Yorks Test Tenant",
        "contract_number":"TC-RU-005-2026","contract_type":"tenancy_contract",
        "contract_status":"active","lease_start":"2026-08-01",
        "lease_end":"2026-09-30","monthly_rent":1000,
        "security_deposit":2000,"monthly_due_day":1,"grace_period_days":5,
        "default_payment_method":"bank_transfer","payment_frequency":"monthly",
        "contract_cheque_count":1,"annual_escalation_percent":5,
        "renewal_notice_days":90
      }],
      "payments":[{
        "source_row":2,"unit_code":"RU-005","rent_period":"2026-08-01",
        "amount_received":500,"payment_date":"2026-08-05",
        "payment_method":"bank_transfer","reference":"RENT-005-01",
        "note":"Opening partial receipt"
      }],
      "cheques":[{
        "source_row":2,"unit_code":"RU-005","cheque_type":"pdc",
        "cheque_number":"PDC-005-01","bank_name":"Yorks Bank",
        "rent_period":"2026-09-01","cheque_date":"2026-09-01",
        "amount":1000,"status":"scheduled"
      }]
    }'::jsonb,
    '84000000-0000-4000-8000-000000000050'
  )$$,
  'Admin can atomically import property, payment and cheque registers'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'properties') row_record
   where row_record ->> 'Unit Code' = 'RU-005'),
  1,
  'Import creates the exact property once'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'payments') row_record
   where row_record ->> 'Unit Code' = 'RU-005'),
  1,
  'Import connects the payment to the imported property and period'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'cheques') row_record
   where row_record ->> 'Unit Code' = 'RU-005'),
  1,
  'Import connects the cheque to the imported property and period'
);
select lives_ok(
  $$select public.v1_import_rental_workbook(
    '{
      "file_name":"rental-import.xlsx",
      "properties":[{
        "source_row":2,"action":"create","unit_code":"RU-005",
        "property_name":"Mussafah Shop 05","property_type":"shop",
        "municipality_number":"M37-S05","location":"Mussafah M-37",
        "occupied":true,"tenant_name":"Yorks Test Tenant",
        "contract_number":"TC-RU-005-2026","contract_type":"tenancy_contract",
        "contract_status":"active","lease_start":"2026-08-01",
        "lease_end":"2026-09-30","monthly_rent":1000,
        "security_deposit":2000,"monthly_due_day":1,"grace_period_days":5,
        "default_payment_method":"bank_transfer","payment_frequency":"monthly",
        "contract_cheque_count":1,"annual_escalation_percent":5,
        "renewal_notice_days":90
      }],
      "payments":[{
        "source_row":2,"unit_code":"RU-005","rent_period":"2026-08-01",
        "amount_received":500,"payment_date":"2026-08-05",
        "payment_method":"bank_transfer","reference":"RENT-005-01",
        "note":"Opening partial receipt"
      }],
      "cheques":[{
        "source_row":2,"unit_code":"RU-005","cheque_type":"pdc",
        "cheque_number":"PDC-005-01","bank_name":"Yorks Bank",
        "rent_period":"2026-09-01","cheque_date":"2026-09-01",
        "amount":1000,"status":"scheduled"
      }]
    }'::jsonb,
    '84000000-0000-4000-8000-000000000050'
  )$$,
  'A lost-response workbook retry replays the original result'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'payments') row_record
   where row_record ->> 'Unit Code' = 'RU-005'),
  1,
  'Workbook retry cannot duplicate a receipt'
);
select throws_ok(
  $$select public.v1_import_rental_workbook(
    '{"properties":[{
      "source_row":2,"action":"create","unit_code":"RU-005",
      "property_name":"Duplicate Shop","property_type":"shop",
      "location":"Mussafah","occupied":false
    }],"payments":[],"cheques":[]}'::jsonb,
    '84000000-0000-4000-8000-000000000051'
  )$$,
  '23505', 'V1_RENTAL_IMPORT_CREATE_UNIT_EXISTS_RU-005',
  'Create action cannot silently overwrite an existing Unit Code'
);
select throws_ok(
  $$select public.v1_import_rental_workbook(
    '{"properties":[{
      "source_row":2,"action":"update","unit_code":"RU-UNKNOWN",
      "property_name":"Unknown Shop","property_type":"shop",
      "location":"Mussafah","occupied":false
    }],"payments":[],"cheques":[]}'::jsonb,
    '84000000-0000-4000-8000-000000000052'
  )$$,
  'P0002', 'V1_RENTAL_IMPORT_UPDATE_UNIT_NOT_FOUND_RU-UNKNOWN',
  'Update action cannot silently create an unknown Unit Code'
);
select throws_ok(
  $$select public.v1_import_rental_workbook(
    '{
      "properties":[{
        "source_row":2,"action":"create","unit_code":"RU-006",
        "property_name":"Rollback Shop","property_type":"shop",
        "location":"Mussafah","occupied":false
      }],
      "payments":[
        {"source_row":2,"unit_code":"RU-004","rent_period":"2026-09-01",
         "amount_received":100,"payment_date":"2026-08-10",
         "payment_method":"bank_transfer"},
        {"source_row":3,"unit_code":"RU-004","rent_period":"2026-09-01",
         "amount_received":100,"payment_date":"2026-08-10",
         "payment_method":"bank_transfer"}
      ],"cheques":[]
    }'::jsonb,
    '84000000-0000-4000-8000-000000000053'
  )$$,
  '23505', 'V1_RENTAL_IMPORT_DUPLICATE_PAYMENT',
  'Duplicate receipt identity blocks the whole workbook before mutation'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'properties') row_record
   where row_record ->> 'Unit Code' = 'RU-006'),
  0,
  'A rejected payment workbook does not partially create its property'
);
select throws_ok(
  $$select public.v1_import_rental_workbook(
    '{
      "properties":[{
        "source_row":2,"action":"create","unit_code":"RU-007",
        "property_name":"Cheque Rollback Shop","property_type":"shop",
        "location":"Mussafah","occupied":false
      }],"payments":[],
      "cheques":[
        {"source_row":2,"unit_code":"RU-004","cheque_type":"pdc",
         "cheque_number":"PDC-DUPLICATE","bank_name":"Yorks Bank",
         "cheque_date":"2026-10-01","amount":100,"status":"scheduled"},
        {"source_row":3,"unit_code":"RU-004","cheque_type":"pdc",
         "cheque_number":"PDC-DUPLICATE","bank_name":"Yorks Bank",
         "cheque_date":"2026-10-01","amount":100,"status":"scheduled"}
      ]
    }'::jsonb,
    '84000000-0000-4000-8000-000000000054'
  )$$,
  '23505', 'V1_RENTAL_IMPORT_DUPLICATE_CHEQUE',
  'Duplicate cheque identity blocks the whole workbook before mutation'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.v1_get_rental_export_data() -> 'properties') row_record
   where row_record ->> 'Unit Code' = 'RU-007'),
  0,
  'A rejected cheque workbook does not partially create its property'
);

select * from finish();
rollback;

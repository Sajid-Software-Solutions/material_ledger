begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(47);
select ok(not has_function_privilege('authenticated','public.v1_rental_missing_fields_internal(uuid)','EXECUTE'), 'The unguarded completeness helper is not callable by application users');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);

select lives_ok($$select v1_import_rental_workbook('{
  "file_name":"owner-source.xlsx",
  "properties":[
    {"action":"create","unit_code":"SOURCE-STORE-1","property_name":"Source store","property_type":"store","occupancy_state":"occupied","occupied":true,"tenant_name":"Source tenant","payment_frequency":"annual","annual_rent":1200,"monthly_rent":null,"billing_start":null,"source_metadata":{"source_format":"lease_contracts_tracker","source_row":4,"source_unit_number":"1","source_unit_type":"Store","original_values":{"Rental / Year":1200,"Security Cheque":"SC-123"}}},
    {"action":"create","unit_code":"SOURCE-OFFICE-2","property_name":"Source office","property_type":"office_store","occupancy_state":"vacant","occupied":false,"tenant_name":"Used by Yorks","lease_start":"2010-01-01","lease_end":"2035-12-31","payment_frequency":"annual","annual_rent":2400,"monthly_rent":null,"billing_start":null,"source_metadata":{"source_row":5,"source_unit_number":"2","source_unit_type":"Office (Store)","original_values":{"Status":"Vacant","Security Cheque":"HISTORICAL-NOTE"}}},
    {"action":"create","unit_code":"SOURCE-6","property_name":"Incomplete source","property_type":"other","occupancy_state":"unknown","occupied":false,"payment_frequency":"annual","annual_rent":null,"monthly_rent":null,"billing_start":null,"source_metadata":{"source_row":6,"source_unit_number":null,"source_unit_type":null,"original_values":{"Status":null}}}
  ],"payments":[],"cheques":[]
}'::jsonb,'84200000-0000-4000-8000-000000000001')$$, 'Owner-approved incomplete annual/occupied/vacant/unknown source rows import atomically');
create temp table rental_source_ids as select item->>'unit_code' unit_code,(item->>'id')::uuid property_id,(item->>'lease_id')::uuid lease_id from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'unit_code' like 'SOURCE-%';
select is((select count(*)::integer from rental_source_ids),3,'Every accepted source row remains in the property register');
select is((select item->>'property_type' from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'unit_code'='SOURCE-STORE-1'),'store','Store is preserved without reinterpreting it as warehouse');
select is((select item->>'property_type' from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'unit_code'='SOURCE-OFFICE-2'),'office_store','Office (Store) has its own preserved property type');
select is((select item->>'occupancy_state' from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'unit_code'='SOURCE-6'),'unknown','An empty source status is unknown rather than a fabricated vacant state');
select is((select v1_get_rental_property(property_id)->'lease'->>'monthly_rent' from rental_source_ids where unit_code='SOURCE-STORE-1'),null::text,'Annual rent never fabricates a monthly amount');
select is((select (v1_get_rental_property(property_id)->'lease'->>'annual_rent')::numeric from rental_source_ids where unit_code='SOURCE-STORE-1'),1200::numeric,'Annual rent preserves the exact source value');
select is((select sum(jsonb_array_length(v1_get_rental_property(property_id)->'periods')) from rental_source_ids),0::bigint,'No imported row invents historical rent periods or arrears before billing setup');
select is(jsonb_array_length(v1_get_rental_portfolio()->'cheques'),0,'A source security cheque note is not converted into a transactional cheque');
select is((select v1_get_rental_property(property_id)->'property'->'source_metadata'->'original_values'->>'Security Cheque' from rental_source_ids where unit_code='SOURCE-STORE-1'),'SC-123','Raw security cheque evidence is retained in protected source metadata');
select ok((select v1_rental_missing_fields(property_id) @> array['location','contract_number','contact_number','lease_start','lease_end','billing_start'] from rental_source_ids where unit_code='SOURCE-STORE-1'),'Missing optional source facts are explicit completion warnings');
select ok((select v1_rental_missing_fields(property_id) @> array['source_unit_number','source_property_type','occupancy','rent_amount'] from rental_source_ids where unit_code='SOURCE-6'),'Missing source identity facts and unknown occupancy remain visible');
select is((select (item->>'billing_setup_pending')::boolean from jsonb_array_elements(v1_get_rental_portfolio()->'properties') item where item->>'unit_code'='SOURCE-OFFICE-2'),true,'An old lease date alone does not activate billing');
select is((v1_get_rental_portfolio()->'summary'->>'annual_rent_roll')::numeric,1200::numeric,'Annual rent roll uses occupied annual amounts without monthly conversion');
select is((v1_get_rental_portfolio()->'summary'->>'monthly_rent_roll')::numeric,0::numeric,'Annual rent stays out of the monthly rent-roll KPI');

-- Completion remains an ordinary version-checked property save. Billing begins
-- only at the explicit first tracking date, never the old source lease start.
select lives_ok($$select v1_save_rental_property(jsonb_build_object(
  'property_id',(select property_id from rental_source_ids where unit_code='SOURCE-STORE-1'),
  'lease_id',(select lease_id from rental_source_ids where unit_code='SOURCE-STORE-1'),
  'unit_code','SOURCE-STORE-1','property_name','Source store','property_type','store','occupancy_state','occupied',
  'location','Owner confirmed location','tenant_name','Source tenant','contract_number','SOURCE-CONTRACT-1','contact_number','12345',
  'lease_start','2010-01-01','lease_end',(date_trunc('month',v1_rental_business_date())+interval '18 months')::date,
  'annual_rent',1200,'monthly_rent',null,'payment_frequency','annual','billing_start',v1_rental_business_date()
),1,'84200000-0000-4000-8000-000000000002')$$,'An Admin can complete optional facts and explicitly activate annual billing');
select is((select jsonb_array_length(v1_get_rental_property(property_id)->'periods') from rental_source_ids where unit_code='SOURCE-STORE-1'),2,'An annual lease generates annual periods rather than monthly instalments');
select is((select (v1_get_rental_property(property_id)->'periods'->0->>'amount_due')::numeric from rental_source_ids where unit_code='SOURCE-STORE-1'),1200::numeric,'Each annual period uses the explicit annual amount');
select is((select (v1_get_rental_property(property_id)->'periods'->0->>'due_date')::date from rental_source_ids where unit_code='SOURCE-STORE-1'),v1_rental_business_date(),'Explicit billing setup does not backdate rent to the historical contract start');
select is((select (v1_get_rental_property(property_id)->'property'->>'billing_setup_pending')::boolean from rental_source_ids where unit_code='SOURCE-STORE-1'),false,'The completed billing state is reflected in detail projections');
select lives_ok($$select v1_save_rental_property(jsonb_build_object(
  'property_id',(select property_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'lease_id',(select lease_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'unit_code','SOURCE-OFFICE-2','property_name','Source office','property_type','office_store','occupancy_state','vacant',
  'tenant_name','Used by Yorks','lease_start','2010-01-01','lease_end','2035-12-31',
  'annual_rent',2400,'monthly_rent',null,'payment_frequency','annual','billing_start',null,'contact_number','12345'
),1,'84200000-0000-4000-8000-000000000003')$$,'Optional lease facts remain editable on a vacant property');
select is((select v1_get_rental_property(property_id)->'lease'->>'tenant_name' from rental_source_ids where unit_code='SOURCE-OFFICE-2'),'Used by Yorks','Vacant status never silently discards supplied tenant/use evidence');
select lives_ok($$select v1_archive_rental_property((select property_id from rental_source_ids where unit_code='SOURCE-6'),1,'Owner deferred incomplete record','84200000-0000-4000-8000-000000000004')$$,'An explicitly reasoned archive can preserve a pending source record without treating it as settled billing');
select ok((select v1_get_rental_property(property_id)->'property'->'source_metadata' ? 'original_values' from rental_source_ids where unit_code='SOURCE-6'),'Archiving an incomplete record preserves its raw source evidence');
select ok(v1_get_rental_export_data()->'properties'->0 ? 'Annual Rent AED','Exports include annual rent facts');
select ok(v1_get_rental_export_data()->'properties'->0 ? 'Source Metadata','Exports preserve source provenance');
select is(v1_get_rental_portfolio()->>'business_date',v1_rental_business_date()::text,'Portfolio and notification work share the UAE business date');
select throws_ok($$select v1_import_rental_workbook('{"properties":[{"action":"create","unit_code":"SOURCE-STORE-1","property_name":"Duplicate source","property_type":"store","occupied":false}],"payments":[],"cheques":[]}', '84200000-0000-4000-8000-000000000005')$$,'23505','V1_RENTAL_IMPORT_CREATE_UNIT_EXISTS_SOURCE-STORE-1','A fresh import command cannot duplicate the same source property');
select lives_ok($$select v1_save_rental_property(jsonb_build_object(
  'property_id',(select property_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'lease_id',(select lease_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'unit_code','SOURCE-OFFICE-2','property_name','Source office','property_type','other','occupancy_state','vacant',
  'tenant_name','Used by Yorks','lease_start','2010-01-01','lease_end','2035-12-31',
  'annual_rent',2400,'payment_frequency','annual','billing_start',null,'source_metadata',null
),2,'84200000-0000-4000-8000-000000000006')$$,'An intentional Other category and null optional metadata remain editable');
select ok((select not ('property_type'=any(v1_rental_missing_fields(property_id))) from rental_source_ids where unit_code='SOURCE-OFFICE-2'),'Known Other category is not permanently flagged as missing');
select throws_ok($$select v1_save_rental_property(jsonb_build_object(
  'property_id',(select property_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'lease_id',(select lease_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),
  'unit_code','SOURCE-OFFICE-2','property_name','Source office','property_type','office_store','occupancy_state','vacant',
  'source_metadata',jsonb_build_object('original_values',jsonb_build_object('Status','Rewritten'))
),3,'84200000-0000-4000-8000-000000000007')$$,'23514','V1_RENTAL_SOURCE_EVIDENCE_IMMUTABLE','Correcting live fields cannot rewrite original workbook evidence');
select throws_ok($$select v1_save_rental_property('{"unit_code":"SOURCE-NEGATIVE","property_name":"Negative rent","property_type":"store","occupancy_state":"occupied","payment_frequency":"annual","annual_rent":-1,"billing_start":null}',null,'84200000-0000-4000-8000-000000000008')$$,'23514',null,'Optional annual rent still rejects a supplied negative amount');
select throws_ok($$select v1_save_rental_property('{"unit_code":"SOURCE-REVERSED","property_name":"Reversed dates","property_type":"store","occupancy_state":"occupied","lease_start":"2026-12-01","lease_end":"2026-01-01","payment_frequency":"annual","billing_start":null}',null,'84200000-0000-4000-8000-000000000009')$$,'23514',null,'Optional lease dates still enforce chronological order when supplied');

select lives_ok($$select v1_import_rental_workbook('{"properties":[{"action":"create","unit_code":"SOURCE-99","property_name":"Identity completion fixture","property_type":"other","occupancy_state":"unknown","billing_start":null,"source_metadata":{"source_row":99,"source_unit_number":null,"source_unit_type":null,"original_values":{"Unit No":null,"Unit Type":null}}}],"payments":[],"cheques":[]}', '84200000-0000-4000-8000-000000000010')$$,'A separate pending identity fixture preserves blank source evidence');
select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',(select (x->>'id')::uuid from jsonb_array_elements(v1_get_rental_portfolio()->'properties') x where x->>'unit_code'='SOURCE-99'),'unit_code','OFFICE-CONFIRMED-99','property_name','Identity completion fixture','property_type','office','occupancy_state','unknown','billing_start',null),1,'84200000-0000-4000-8000-000000000011')$$,'Correcting current code and type does not require changing original source cells');
select ok((select not (v1_rental_missing_fields((x->>'id')::uuid) && array['property_type','source_unit_number','source_property_type']) from jsonb_array_elements(v1_get_rental_portfolio()->'properties') x where x->>'unit_code'='OFFICE-CONFIRMED-99'),'Corrected live identity clears both source recommendations');

select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',(select property_id from rental_source_ids where unit_code='SOURCE-OFFICE-2'),'property_name','Completed source office'),3,'84200000-0000-4000-8000-000000000012')$$,'Sparse source edits keep manually completed optional fields');
select is((select (v1_get_rental_property(property_id)->'lease'->>'annual_rent')::numeric from rental_source_ids where unit_code='SOURCE-OFFICE-2'),2400::numeric,'Sparse source edits retain annual rent rather than clearing it');

select is(v1_rental_period_status(v1_rental_business_date()-6,100,25,5),'overdue','A partial balance becomes overdue after grace expires');
select is(v1_rental_period_status(v1_rental_business_date()-5,100,25,5),'partially_paid','A partial balance remains partial on the final grace day');
select is(v1_rental_period_status(v1_rental_business_date()-6,100,100,5),'paid','A fully paid old period never becomes overdue');
select is(v1_rental_period_status((date_trunc('year',v1_rental_business_date())-interval '1 day')::date,100,25,0),'overdue','Partial arrears remain overdue across a year boundary');
select lives_ok($$select v1_save_rental_property('{"unit_code":"ANNUAL-LEAP-ANCHOR","property_name":"Annual leap anchor","property_type":"office","occupancy_state":"occupied","lease_start":"2024-02-29","lease_end":"2028-02-29","payment_frequency":"annual","annual_rent":100,"billing_start":"2024-02-29"}',null,'84200000-0000-4000-8000-000000000020')$$,'An annual leap-day anchor generates valid anniversary dates');
select is((select array_agg((period->>'due_date')::date order by period->>'due_date') from jsonb_array_elements(v1_get_rental_portfolio()->'properties') property cross join lateral jsonb_array_elements(v1_get_rental_property((property->>'id')::uuid)->'periods') period where property->>'unit_code'='ANNUAL-LEAP-ANCHOR'),array[date '2024-02-29',date '2025-02-28',date '2026-02-28',date '2027-02-28',date '2028-02-29'],'Annual due dates stay anchored to the original anniversary without leap-year drift');
select lives_ok($$select v1_save_rental_property('{"unit_code":"MONTH-END-ANCHOR","property_name":"Monthly end day","property_type":"office","occupancy_state":"occupied","lease_start":"2028-01-31","lease_end":"2028-03-31","payment_frequency":"monthly","monthly_rent":100,"monthly_due_day":31,"billing_start":"2028-01-31"}',null,'84200000-0000-4000-8000-000000000021')$$,'A monthly due-day31 schedule handles short leap-year months');
select is((select array_agg((period->>'due_date')::date order by period->>'due_date') from jsonb_array_elements(v1_get_rental_portfolio()->'properties') property cross join lateral jsonb_array_elements(v1_get_rental_property((property->>'id')::uuid)->'periods') period where property->>'unit_code'='MONTH-END-ANCHOR'),array[date '2028-01-31',date '2028-02-29',date '2028-03-31'],'Monthly day31 clamps per month without drifting the following month');

select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(37);

create function pg_temp.review_id(p_suffix integer) returns uuid language sql immutable as $$
  select ('84500000-0000-4000-8000-'||lpad(p_suffix::text,12,'0'))::uuid
$$;
create function pg_temp.review_payload(p_suffix integer) returns jsonb language sql stable as $$
  select jsonb_build_object('property_id',pg_temp.review_id(p_suffix),
    'lease_id',pg_temp.review_id(p_suffix+1),'unit_code','REVIEW-'||p_suffix,
    'property_name','Review fixture '||p_suffix,'property_type','office',
    'occupancy_state','occupied','lease_start',public.v1_rental_business_date(),
    'lease_end',(public.v1_rental_business_date()+interval '2 months')::date,
    'billing_start',public.v1_rental_business_date(),'monthly_rent',100)
$$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select lives_ok($$select v1_save_rental_property(pg_temp.review_payload(10),null,pg_temp.review_id(100))$$,'An Admin creates an ordinary monthly review fixture');
create temp table review_periods as
select (p->>'id')::uuid id,row_number() over(order by p->>'period_month') n
from jsonb_array_elements(v1_get_rental_property(pg_temp.review_id(10))->'periods') p;
select throws_ok($$select v1_record_rent_payment((select id from review_periods where n=1),0.005,v1_rental_business_date(),'cash',null,null,pg_temp.review_id(101))$$,'22023','V1_RENTAL_PAYMENT_INVALID','A sub-cent receipt cannot create a rounded balance different from the command outcome');
select throws_ok($$select v1_record_rent_payment((select id from review_periods where n=1),'NaN',v1_rental_business_date(),'cash',null,null,pg_temp.review_id(102))$$,'22023','V1_RENTAL_PAYMENT_INVALID','NaN is not an accepted receipt amount');
select throws_ok($$select v1_record_rent_payment((select id from review_periods where n=1),1,v1_rental_business_date(),null,null,null,pg_temp.review_id(103))$$,'22023','V1_RENTAL_PAYMENT_METHOD_INVALID','An omitted payment method fails the command validation');
select is((v1_record_rent_payment((select id from review_periods where n=1),0.01,v1_rental_business_date(),'cash',null,null,pg_temp.review_id(104))->>'amount_paid')::numeric,0.01::numeric,'An exact-cent receipt reports the actual stored amount');
select is((v1_record_rent_payment((select id from review_periods where n=1),0.01,v1_rental_business_date(),'cash',null,null,pg_temp.review_id(104))->>'balance')::numeric,99.99::numeric,'Same-key receipt replay returns the original exact balance');
select is(jsonb_array_length(v1_get_rental_property(pg_temp.review_id(10))->'receipts'),1,'An exact retry still creates one receipt');
select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',pg_temp.review_id(10),'contact_number','Completed after a receipt'),1,pg_temp.review_id(105))$$,'The consistent locks preserve ordinary paid metadata edits');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(10)||'{"monthly_rent":50}',2,pg_temp.review_id(106))$$,'23514','V1_RENTAL_PAID_SCHEDULE_CANNOT_BE_REBUILT','A financial edit still cannot change paid history');
select is((v1_get_rental_property(pg_temp.review_id(10))->'periods'->0->>'amount_due')::numeric,100::numeric,'Rejected financial edits retain the original charge');

create function pg_temp.review_cheque(p_amount text) returns jsonb language sql stable as $$
 select jsonb_build_object('cheque_id',pg_temp.review_id(20),'property_id',pg_temp.review_id(10),
  'lease_id',pg_temp.review_id(11),'period_id',(select id from review_periods where n=2),
  'cheque_number','REVIEW-CHEQUE-20','cheque_type','pdc','bank_name','Review bank',
  'cheque_date',public.v1_rental_business_date(),'amount',p_amount)
$$;
select throws_ok($$select v1_save_rental_cheque(pg_temp.review_cheque('NaN'),null,pg_temp.review_id(107))$$,'22023','V1_RENTAL_CHEQUE_REQUIRED_FIELDS','NaN is not an accepted cheque amount');
select throws_ok($$select v1_save_rental_cheque(pg_temp.review_cheque('0.005'),null,pg_temp.review_id(108))$$,'22023','V1_RENTAL_CHEQUE_REQUIRED_FIELDS','Sub-cent cheque amounts cannot be silently rounded');
select lives_ok($$select v1_save_rental_cheque(pg_temp.review_cheque('0.01'),null,pg_temp.review_id(109))$$,'An exact-cent cheque can still link to a real rent period');
select lives_ok($$select v1_save_rental_cheque(pg_temp.review_cheque('0.01')||'{"note":"Owner note"}',1,pg_temp.review_id(110))$$,'Editable cheque metadata retains the trusted linkage');

select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(30)||'{"monthly_rent":"NaN"}',null,pg_temp.review_id(111))$$,'23514',null,'A nonnegative numeric check alone cannot admit NaN monthly rent');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(30)||'{"payment_frequency":"annual","annual_rent":"NaN"}',null,pg_temp.review_id(112))$$,'23514',null,'NaN annual rent cannot poison the annual rent roll');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(30)||'{"security_deposit":"NaN"}',null,pg_temp.review_id(113))$$,'23514',null,'Security deposits must remain finite');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(30)||'{"annual_escalation_percent":"NaN"}',null,pg_temp.review_id(114))$$,'23514',null,'Escalation percentages must remain finite');
select throws_ok($$select v1_import_rental_workbook('{"properties":[{"action":"create","unit_code":"REVIEW-NAN-IMPORT","property_name":"Invalid annual fixture","property_type":"office","occupancy_state":"occupied","payment_frequency":"annual","annual_rent":"NaN","billing_start":null}],"payments":[],"cheques":[]}',pg_temp.review_id(115))$$,'23514',null,'The import path cannot bypass finite annual-rent validation');
select ok(not exists(select 1 from jsonb_array_elements(v1_get_rental_portfolio()->'properties') p where p->>'unit_code'='REVIEW-NAN-IMPORT'),'The rejected import leaves no partial property');

select lives_ok($$select v1_save_rental_property(pg_temp.review_payload(40)||'{"billing_start":null}',null,pg_temp.review_id(116))$$,'An incomplete pending fixture retains its lease without inferred charges');
select lives_ok($$select v1_archive_rental_property(pg_temp.review_id(40),1,'Deferred by owner',pg_temp.review_id(117))$$,'An obligation-free pending source record may still be archived with a reason');
select throws_ok($$select v1_save_rental_cheque(pg_temp.review_cheque('10')||jsonb_build_object('cheque_id',pg_temp.review_id(42),'property_id',pg_temp.review_id(40),'lease_id',pg_temp.review_id(41),'period_id',null),null,pg_temp.review_id(118))$$,'23514','V1_RENTAL_ARCHIVED_PROPERTY_READ_ONLY','Archived records cannot acquire a new open cheque obligation');
select lives_ok($$select v1_get_rental_property(pg_temp.review_id(40))$$,'Archived source and lease history remain readable');

reset role;
select throws_ok($$update v1_rental_periods set amount_due='NaN' where id=(select id from review_periods where n=1)$$,'23514',null,'The period constraint also rejects non-finite trusted writes');
select throws_ok($$update v1_rental_receipts set amount_received='NaN' where property_id=pg_temp.review_id(10)$$,'23514',null,'The receipt constraint protects all write paths');
select throws_ok($$update v1_rental_cheques set amount='NaN' where id=pg_temp.review_id(20)$$,'23514',null,'The cheque constraint protects all write paths');

-- The exact original tracker row cannot become a new property after the owner
-- corrects a missing/generated Unit Code. Optional fields/position are ignored.
reset role;
select ok(not has_function_privilege('authenticated','public.v1_rental_tracker_source_fingerprint(jsonb)','EXECUTE'),'The unguarded source fingerprint helper is not a public application API');
set local role authenticated;
create function pg_temp.review_source() returns jsonb language sql immutable as $$
 select jsonb_build_object('format','yorks_properties_tracker_v1','source_format','yorks_properties_tracker_v1',
  'source_row',17,'source_file','Original.xlsx','original_values',jsonb_build_object(
   'Unit No',null,'Unit Type','Store','Tenant / Company','Source tenant','Contract Start',null,
   'Contract End',null,'Annual Rent (AED)','100','Status','Active','Security Cheque (AED)',null,
   'Contact',null,'Days to Expiry',null,'Expiry Flag',null))
$$;
select lives_ok($$select v1_save_rental_property(pg_temp.review_payload(50)||jsonb_build_object('unit_code','SOURCE-17','billing_start',null,'source_metadata',pg_temp.review_source()),null,pg_temp.review_id(119))$$,'A tracker row with incomplete identity imports with immutable full source evidence');
select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',pg_temp.review_id(50),'unit_code','OWNER-CONFIRMED-50'),1,pg_temp.review_id(120))$$,'The owner may correct the current Unit Code without altering source evidence');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(60)||jsonb_build_object('unit_code','SOURCE-17','billing_start',null,'source_metadata',pg_temp.review_source()),null,pg_temp.review_id(121))$$,'23505','V1_RENTAL_SOURCE_ALREADY_IMPORTED_USE_CURRENT_CODE','Reimporting the original derived code cannot duplicate a corrected property');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(60)||jsonb_build_object('unit_code','SOURCE-99','billing_start',null,'source_metadata',pg_temp.review_source()||'{"source_row":99,"source_file":"Renamed.xlsx"}'),null,pg_temp.review_id(122))$$,'23505','V1_RENTAL_SOURCE_ALREADY_IMPORTED_USE_CURRENT_CODE','Reordering or renaming the workbook cannot evade exact source identity');
select throws_ok($$select v1_save_rental_property(pg_temp.review_payload(60)||jsonb_build_object('billing_start',null,'source_metadata',jsonb_set(pg_temp.review_source(),'{original_values,Site Location}','"Now supplied"')),null,pg_temp.review_id(123))$$,'23505','V1_RENTAL_SOURCE_ALREADY_IMPORTED_USE_CURRENT_CODE','Optional template completion columns cannot create a duplicate original tracker row');
select lives_ok($$select v1_save_rental_property(jsonb_build_object('property_id',pg_temp.review_id(50),'contact_number','Completed current contact','source_metadata',pg_temp.review_source()),2,pg_temp.review_id(124))$$,'The matching current property remains editable without source replacement');
select is((select p->>'unit_code' from jsonb_array_elements(v1_get_rental_portfolio()->'properties') p where p->>'id'=pg_temp.review_id(50)::text),'OWNER-CONFIRMED-50','A blocked replay preserves the owner-corrected visible identity');
select lives_ok($$select v1_save_rental_property(pg_temp.review_payload(70)||jsonb_build_object('billing_start',null,'source_metadata',pg_temp.review_source()||'{"format":"manual_notes","source_format":"manual_notes"}'),null,pg_temp.review_id(125))$$,'The fingerprint guard does not treat unrelated manually supplied notes as tracker identity');
select is((select count(*)::integer from jsonb_array_elements(v1_get_rental_portfolio()->'properties') p where p->>'id' in (pg_temp.review_id(50)::text,pg_temp.review_id(60)::text)),1,'The rejected exact source replays leave one original property');

select * from finish();
rollback;

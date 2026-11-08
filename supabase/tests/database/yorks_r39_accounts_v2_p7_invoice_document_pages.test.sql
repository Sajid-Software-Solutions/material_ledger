-- R39 Accounts Workspace V2 — P7 pgTAP: invoice document summary + per-building

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d18000-0000-4000-8000-000000000001','R39-V2P7-001','R39 V2 P7 invoice pages','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d18000-0000-4000-8000-000000000002','39d18000-0000-4000-8000-000000000001','building','b01','Building 01',false),
      ('39d18000-0000-4000-8000-000000000003','39d18000-0000-4000-8000-000000000001','building','b02','Building 02',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d18000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d18000-0000-4000-8000-000000000005','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d18000-0000-4000-8000-000000000006','39d18000-0000-4000-8000-000000000005',1,'r39/v2p7/p.pdf','p.pdf','application/pdf',128,repeat('e',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d18000-0000-4000-8000-000000000006' where id='39d18000-0000-4000-8000-000000000005';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d18000-0000-4000-8000-000000000007','39d18000-0000-4000-8000-000000000005','39d18000-0000-4000-8000-000000000001','project','39d18000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p7(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p7 to authenticated;

-- Admin: contract 1,000,000, two 50% buildings, Yorks standard stages.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d18000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id','39d18000-0000-4000-8000-000000000002','allocation_percent','50'),
      jsonb_build_object('building_scope_id','39d18000-0000-4000-8000-000000000003','allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f99000-0000-4000-8000-000000000081');
select public.v1_save_project_invoice_settings('39d18000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f99000-0000-4000-8000-000000000082');
reset role;
-- Design progress-entry ids for each building.
insert into v1_r39_p7 select 'pid_d_b01', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d18000-0000-4000-8000-000000000001' and stage_key='design' and project_scope_id='39d18000-0000-4000-8000-000000000002'));
insert into v1_r39_p7 select 'pid_d_b02', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d18000-0000-4000-8000-000000000001' and stage_key='design' and project_scope_id='39d18000-0000-4000-8000-000000000003'));

-- PE confirms Design 100% on both buildings, claims both, admin issues.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d18000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p7 where result_key='pid_d_b01'),1,'100.0000','d',array['39d18000-0000-4000-8000-000000000005'::uuid],'c','39f99000-0000-4000-8000-000000000083');
select public.v1_confirm_billing_progress('39d18000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p7 where result_key='pid_d_b02'),1,'100.0000','d',array['39d18000-0000-4000-8000-000000000005'::uuid],'c','39f99000-0000-4000-8000-000000000084');
insert into v1_r39_p7 select 'claim', public.v1_create_client_claim_draft('39d18000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(
    jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p7 where result_key='pid_d_b01'),'claimed_amount','50000.00','evidence_reference','V'),
    jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p7 where result_key='pid_d_b02'),'claimed_amount','50000.00','evidence_reference','V')),
  'a','39f99000-0000-4000-8000-000000000085');
select public.v1_submit_client_claim_to_accounts('39d18000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p7 where result_key='claim'),1,'r','39f99000-0000-4000-8000-000000000086');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p7 select 'issue', public.v1_issue_client_invoice('39d18000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p7 where result_key='claim'),2,null,date '2026-08-26',date '2026-08-26','39f99000-0000-4000-8000-000000000087');
insert into v1_r39_p7 select 'doc', public.v1_get_client_invoice_document('39d18000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p7 where result_key='issue'));
reset role;

-- Document carries the new schema version + contract value.
-- Schema 3 (8 Nov 2026) adds the bill-to party, references and VAT rows.
select is((select payload->'document'->>'schema_version' from v1_r39_p7 where result_key='doc'),'3','Document schema version is 3');
select is((select payload->'document'->>'contract_value' from v1_r39_p7 where result_key='doc'),'1000000.00','Contract value exposed on the document');

-- Summary matrix: Design claimed 100,000 this invoice; others zero; contract per stage correct.
select is((select payload->'document'->'summary'->>'this_total' from v1_r39_p7 where result_key='doc'),'100000.00','Summary this-total = both Design cells');
select is((select payload->'document'->'summary'->>'contract_total' from v1_r39_p7 where result_key='doc'),'1000000.00','Summary contract-total = contract value');
select is(
  (select s->>'this_amount' from jsonb_array_elements((select payload->'document'->'summary' from v1_r39_p7 where result_key='doc')->'stages') s where s->>'stage_key'='design'),
  '100000.00','Design stage this-amount aggregates both buildings');
select is(
  (select s->>'contract_amount' from jsonb_array_elements((select payload->'document'->'summary' from v1_r39_p7 where result_key='doc')->'stages') s where s->>'stage_key'='material_supply'),
  '500000.00','Material Supply contract-amount = 50% of contract');
select is(
  (select s->>'this_amount' from jsonb_array_elements((select payload->'document'->'summary' from v1_r39_p7 where result_key='doc')->'stages') s where s->>'stage_key'='material_supply'),
  '0.00','Unclaimed stage this-amount is zero');

-- Per-building: five stages each, Design this = 50,000, building value 500,000.
select is(
  (select jsonb_array_length((select payload->'document' from v1_r39_p7 where result_key='doc')->'buildings')),
  2,'Both buildings are on the document');
select is(
  (select b->>'building_value' from jsonb_array_elements((select payload->'document' from v1_r39_p7 where result_key='doc')->'buildings') b where b->>'name'='Building 01'),
  '500000.00','Building 01 value = contract x 50%');
select is(
  (select b->>'this_amount' from jsonb_array_elements((select payload->'document' from v1_r39_p7 where result_key='doc')->'buildings') b where b->>'name'='Building 01'),
  '50000.00','Building 01 this-amount = its Design cell');
select is(
  (select jsonb_array_length((select b from jsonb_array_elements((select payload->'document' from v1_r39_p7 where result_key='doc')->'buildings') b where b->>'name'='Building 01')->'stages')),
  5,'Building 01 lists all five stages');
select is(
  (select st->>'this_amount'
     from jsonb_array_elements((select b from jsonb_array_elements((select payload->'document' from v1_r39_p7 where result_key='doc')->'buildings') b where b->>'name'='Building 01')->'stages') st
     where st->>'stage_key'='design'),
  '50000.00','Building 01 Design stage this-amount = 50,000');

select finish();
rollback;

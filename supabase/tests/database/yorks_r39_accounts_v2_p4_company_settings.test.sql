-- R39 Accounts Workspace V2 — P4 part a pgTAP: company settings + invoice letterhead

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- The D9 company settings are seeded into the Configuration Centre.
select is((select published_value #>> '{}' from public.v1_configuration_settings where setting_key='company.phone'),'02-5509788','company.phone is seeded');
select is((select published_value #>> '{}' from public.v1_configuration_settings where setting_key='company.trn'),'100026741700003','company.trn is seeded');
select ok((select count(*) from public.v1_configuration_settings
  where setting_key in ('company.trn','company.address','company.phone','company.fax','company.email','company.bank_name','company.bank_iban','company.bank_account_name'))=8,
  'All eight D9 company keys exist');

-- Fixtures to issue an invoice and check the frozen company block.
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39c10000-0000-4000-8000-000000000001','R39-V2P4-001','R39 V2 P4 company','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39c10000-0000-4000-8000-000000000002','39c10000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39c10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39c10000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39c10000-0000-4000-8000-000000000004','39c10000-0000-4000-8000-000000000003',1,'r39/v2p4/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39c10000-0000-4000-8000-000000000004' where id='39c10000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39c10000-0000-4000-8000-000000000005','39c10000-0000-4000-8000-000000000003','39c10000-0000-4000-8000-000000000001','project','39c10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p4(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p4 to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39c10000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39c10000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000081');
select public.v1_save_project_invoice_settings('39c10000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f90000-0000-4000-8000-000000000082');
reset role;
insert into v1_r39_p4 select 'pid', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39c10000-0000-4000-8000-000000000001' and stage_key='design'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39c10000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p4 where result_key='pid'),1,'100.0000','d',array['39c10000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000083');
insert into v1_r39_p4 select 'claim', public.v1_create_client_claim_draft('39c10000-0000-4000-8000-000000000001','CLM-P4',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p4 where result_key='pid'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f90000-0000-4000-8000-000000000084');
select public.v1_submit_client_claim_to_accounts('39c10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p4 where result_key='claim'),1,'r','39f90000-0000-4000-8000-000000000085');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p4 select 'issue', public.v1_issue_client_invoice('39c10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p4 where result_key='claim'),2,null,date '2026-08-26',date '2026-08-26','39f90000-0000-4000-8000-000000000086');
insert into v1_r39_p4 select 'doc', public.v1_get_client_invoice_document('39c10000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p4 where result_key='issue'));
reset role;

select is((select payload->'document'->'company'->>'phone' from v1_r39_p4 where result_key='doc'),'02-5509788','The frozen invoice document carries the company phone');
select is((select payload->'document'->'company'->>'trn' from v1_r39_p4 where result_key='doc'),'100026741700003','The frozen invoice document carries the company TRN');

select finish();
rollback;

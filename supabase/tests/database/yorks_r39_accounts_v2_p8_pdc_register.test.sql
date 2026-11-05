-- R39 Accounts Workspace V2 — P8 pgTAP: project-wide cheque (PDC) register read

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d17000-0000-4000-8000-000000000001','R39-V2P8-001','R39 V2 P8 PDC register','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d17000-0000-4000-8000-000000000002','39d17000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d17000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
      ('39d17000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d17000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d17000-0000-4000-8000-000000000004','39d17000-0000-4000-8000-000000000003',1,'r39/v2p8/p.pdf','p.pdf','application/pdf',128,repeat('d',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d17000-0000-4000-8000-000000000004' where id='39d17000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d17000-0000-4000-8000-000000000005','39d17000-0000-4000-8000-000000000003','39d17000-0000-4000-8000-000000000001','project','39d17000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p8(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p8 to authenticated;

-- Admin sets up the baseline + invoice numbering, confirms one stage, prepares and
-- submits a claim, issues the invoice, certifies it, then records one PDC.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d17000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39d17000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f98000-0000-4000-8000-000000000071');
select public.v1_save_project_invoice_settings('39d17000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f98000-0000-4000-8000-000000000072');
reset role;
insert into v1_r39_p8 select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d17000-0000-4000-8000-000000000001' and stage_key='design'));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d17000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p8 where result_key='pid_design'),1,'100.0000','d',array['39d17000-0000-4000-8000-000000000003'::uuid],'c','39f98000-0000-4000-8000-000000000073');
insert into v1_r39_p8 select 'claimA', public.v1_create_client_claim_draft('39d17000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p8 where result_key='pid_design'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f98000-0000-4000-8000-000000000074');
select public.v1_submit_client_claim_to_accounts('39d17000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p8 where result_key='claimA'),1,'r','39f98000-0000-4000-8000-000000000075');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p8 select 'issue', public.v1_issue_client_invoice('39d17000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p8 where result_key='claimA'),2,null,date '2026-08-26',date '2026-08-26','39f98000-0000-4000-8000-000000000076');
-- Certify the full claimed amount (no difference), so the invoice becomes PDC-eligible.
-- Issue drafts then submits the invoice, leaving it at record_version 2;
-- certification advances it to 3.
select public.v1_record_client_certification('39d17000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p8 where result_key='issue'),
  2,'CERT-1',date '2026-08-27','50000.00',null,'39f98000-0000-4000-8000-000000000077');
-- Record a PDC for the full certified-incl-VAT amount (52,500.00); invoice is now at
-- record_version 3.
insert into v1_r39_p8 select 'pdc', public.v1_create_client_pdc('39d17000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p8 where result_key='issue'),
  3,'CHQ-001',date '2026-09-15','52500.00','Test Bank','39f98000-0000-4000-8000-000000000078');
-- Register read as admin (full commercial values).
insert into v1_r39_p8 select 'reg_admin', public.v1_list_project_client_pdcs('39d17000-0000-4000-8000-000000000001');
reset role;

-- Admin register: the one cheque, joined to the invoice reference, as decimal strings.
select is((select payload->>'schema_version' from v1_r39_p8 where result_key='reg_admin'),'1','Register read reports schema version 1');
select is(
  (select jsonb_array_length((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs')),
  1,'One cheque is listed for the project');
select is(
  (select p->>'cheque_number' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  'CHQ-001','Cheque number carried through');
select is(
  (select p->>'invoice_reference' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  'YRA32201','Cheque is joined to its invoice reference');
select is(
  (select p->>'amount' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  '52500.00','Cheque amount is a decimal string');
select is(
  (select p->>'bank_name' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  'Test Bank','Bank name carried through');
select is(
  (select p->>'status' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  'expected','A freshly recorded cheque is in hand (expected)');
select is(
  (select p->>'record_version' from jsonb_array_elements((select payload from v1_r39_p8 where result_key='reg_admin')->'pdcs') p),
  '1','Cheque record version is exposed for optimistic-concurrency transitions');

-- Site engineer: accounts member but no commercial values -> the register is denied
-- outright (cheques are commercial; omitting them would leak their existence).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select throws_ok(
  $$select public.v1_list_project_client_pdcs('39d17000-0000-4000-8000-000000000001')$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED','Site engineer without commercial values is denied the cheque register');
reset role;

select finish();
rollback;

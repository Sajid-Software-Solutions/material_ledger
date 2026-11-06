-- R39 Accounts Workspace V2 — P6 part f pgTAP: retention hold-back on payable

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d18000-0000-4000-8000-000000000001','R39-V2P6R-001','R39 V2 retention','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d18000-0000-4000-8000-000000000002','39d18000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d18000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d18000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d18000-0000-4000-8000-000000000004','39d18000-0000-4000-8000-000000000003',1,'r39/v2p6r/p.pdf','p.pdf','application/pdf',128,repeat('e',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d18000-0000-4000-8000-000000000004' where id='39d18000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d18000-0000-4000-8000-000000000005','39d18000-0000-4000-8000-000000000003','39d18000-0000-4000-8000-000000000001','project','39d18000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p6r(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p6r to authenticated;

-- Admin: baseline + invoice numbering + retention 10%.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d18000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39d18000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f99000-0000-4000-8000-000000000071');
select public.v1_save_project_invoice_settings('39d18000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f99000-0000-4000-8000-000000000072');
-- Retention 10% on the profile (reuses the contract-references write).
select public.v1_save_accounts_contract_references('39d18000-0000-4000-8000-000000000001',null,null,null,null,10.0,null,'39f99000-0000-4000-8000-000000000073');
reset role;
insert into v1_r39_p6r select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d18000-0000-4000-8000-000000000001' and stage_key='design'));

-- PE: confirm design 100%, claim 50,000, submit.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d18000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p6r where result_key='pid_design'),1,'100.0000','d',array['39d18000-0000-4000-8000-000000000003'::uuid],'c','39f99000-0000-4000-8000-000000000074');
insert into v1_r39_p6r select 'claimA', public.v1_create_client_claim_draft('39d18000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p6r where result_key='pid_design'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f99000-0000-4000-8000-000000000075');
select public.v1_submit_client_claim_to_accounts('39d18000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p6r where result_key='claimA'),1,'r','39f99000-0000-4000-8000-000000000076');
reset role;

-- Admin: issue (freezes retention), certify the full 50,000 ex-VAT.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p6r select 'issue', public.v1_issue_client_invoice('39d18000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p6r where result_key='claimA'),2,null,date '2026-08-26',date '2026-08-26','39f99000-0000-4000-8000-000000000077');
select public.v1_record_client_certification('39d18000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p6r where result_key='issue'),
  2,'CERT-1',date '2026-08-27','50000.00',null,'39f99000-0000-4000-8000-000000000078');
insert into v1_r39_p6r select 'list', public.v1_list_client_invoices('39d18000-0000-4000-8000-000000000001',null,null,null,null,50);
-- Section 28 R-5: the Accountant-office overview and the register export net
-- retention too. Read them BEFORE the payment, while still due = 47,500.
insert into v1_r39_p6r select 'overview', public.v1_get_project_accounts_overview('39d18000-0000-4000-8000-000000000001');
insert into v1_r39_p6r select 'export', public.v1_get_accounts_export('project_summary','39d18000-0000-4000-8000-000000000001','39f99000-0000-4000-8000-00000000007b');
-- Pay exactly the retention-reduced due (52,500 - 5,000 = 47,500) at version 3.
insert into v1_r39_p6r select 'pay', public.v1_record_client_payment('39d18000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p6r where result_key='issue'),
  3,date '2026-08-28','bank_transfer','PAY-1','47500.00',null,'39f99000-0000-4000-8000-000000000079');
-- A further 1.00 would exceed the retention-reduced cap.
select throws_ok(
  $$select public.v1_record_client_payment('39d18000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p6r where result_key='issue'),4,date '2026-08-29','bank_transfer','PAY-2','1.00',null,'39f99000-0000-4000-8000-00000000007a')$$,
  '23514','R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED','Payment cap uses the retention-reduced due');
reset role;

select is((select v->>'retention_snapshot' from jsonb_array_elements((select payload from v1_r39_p6r where result_key='list')->'invoices') v),'5000.00','Issued invoice freezes retention = 10% of the 50,000 gross');
select is((select v->>'still_due' from jsonb_array_elements((select payload from v1_r39_p6r where result_key='list')->'invoices') v),'47500.00','Still due = certified 52,500 − retention 5,000 (unpaid)');
select is((select payload->>'still_due' from v1_r39_p6r where result_key='pay'),'0.00','Paying the retention-reduced due clears the balance');
select is((select payload->'receivables'->>'still_due' from v1_r39_p6r where result_key='overview'),'47500.00','Project overview outstanding nets retention');
select is((select (payload->'rows'->0->>10) from v1_r39_p6r where result_key='export'),'47500.00','project_summary export Still Due nets retention');

select finish();
rollback;

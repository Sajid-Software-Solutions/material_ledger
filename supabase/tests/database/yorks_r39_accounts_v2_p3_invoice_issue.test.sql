-- R39 Accounts Workspace V2 — P3 part 2a pgTAP: invoice numbering, issue, document

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39ff0000-0000-4000-8000-000000000001','R39-V2P3I-001','R39 V2 P3 invoice','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39ff0000-0000-4000-8000-000000000002','39ff0000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39ff0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P3 invoice authority','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39ff0000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39ff0000-0000-4000-8000-000000000004','39ff0000-0000-4000-8000-000000000003',1,'r39/v2p3i/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39ff0000-0000-4000-8000-000000000004' where id='39ff0000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39ff0000-0000-4000-8000-000000000005','39ff0000-0000-4000-8000-000000000003','39ff0000-0000-4000-8000-000000000001','project','39ff0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p3i(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p3i to authenticated;

-- Admin sets up the baseline and the invoice numbering prefix.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39ff0000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39ff0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000051');
select public.v1_save_project_invoice_settings('39ff0000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f90000-0000-4000-8000-000000000052');
reset role;
insert into v1_r39_p3i select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39ff0000-0000-4000-8000-000000000001' and stage_key='design'));
insert into v1_r39_p3i select 'pid_install', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39ff0000-0000-4000-8000-000000000001' and stage_key='installation'));
insert into v1_r39_p3i select 'pid_comm', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39ff0000-0000-4000-8000-000000000001' and stage_key='commissioning_handover'));

-- PE confirms three stages and prepares three claims.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39ff0000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_design'),1,'100.0000','d',array['39ff0000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000053');
select public.v1_confirm_billing_progress('39ff0000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_install'),1,'100.0000','i',array['39ff0000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000054');
select public.v1_confirm_billing_progress('39ff0000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_comm'),1,'100.0000','m',array['39ff0000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000055');
insert into v1_r39_p3i select 'claimA', public.v1_create_client_claim_draft('39ff0000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_design'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f90000-0000-4000-8000-000000000056');
select public.v1_submit_client_claim_to_accounts('39ff0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3i where result_key='claimA'),1,'r','39f90000-0000-4000-8000-000000000057');
insert into v1_r39_p3i select 'claimB', public.v1_create_client_claim_draft('39ff0000-0000-4000-8000-000000000001','CLM-B',date '2026-09-01',date '2026-09-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_install'),'claimed_amount','30000.00','evidence_reference','V')),'b','39f90000-0000-4000-8000-000000000058');
select public.v1_submit_client_claim_to_accounts('39ff0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3i where result_key='claimB'),1,'r','39f90000-0000-4000-8000-000000000059');
insert into v1_r39_p3i select 'claimC', public.v1_create_client_claim_draft('39ff0000-0000-4000-8000-000000000001','CLM-C',date '2026-10-01',date '2026-10-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3i where result_key='pid_comm'),'claimed_amount','10000.00','evidence_reference','V')),'c','39f90000-0000-4000-8000-00000000005a');

-- Admin issues the first two invoices (numbering increments); previews claim C.
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p3i select 'issue1', public.v1_issue_client_invoice('39ff0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3i where result_key='claimA'),2,null,date '2026-08-26',date '2026-08-26','39f90000-0000-4000-8000-00000000005b');
insert into v1_r39_p3i select 'issue2', public.v1_issue_client_invoice('39ff0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3i where result_key='claimB'),2,null,date '2026-09-26',date '2026-09-26','39f90000-0000-4000-8000-00000000005c');
insert into v1_r39_p3i select 'doc1', public.v1_get_client_invoice_document('39ff0000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p3i where result_key='issue1'));
insert into v1_r39_p3i select 'preview', public.v1_preview_client_invoice_document('39ff0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3i where result_key='claimC'));
reset role;

select is((select payload->>'invoice_reference' from v1_r39_p3i where result_key='issue1'),'YRA32201','First issued invoice is numbered YRA32201');
select is((select payload->>'status' from v1_r39_p3i where result_key='issue1'),'submitted','Issued invoice is submitted');
select ok((select payload->>'document_snapshot_sha256' from v1_r39_p3i where result_key='issue1') ~ '^[0-9a-f]{64}$','Issue freezes a sha256 document snapshot');
select is((select payload->>'invoice_reference' from v1_r39_p3i where result_key='issue2'),'YRA32202','The per-project sequence increments to YRA32202');
select is((select payload->'document'->'amounts'->>'ex_vat' from v1_r39_p3i where result_key='doc1'),'50000.00','Frozen document ex-VAT = 50,000.00');
select is((select payload->'document'->'amounts'->>'vat' from v1_r39_p3i where result_key='doc1'),'2500.00','Frozen document VAT (5%) = 2,500.00');
select is((select payload->'document'->'amounts'->>'total_incl_vat' from v1_r39_p3i where result_key='doc1'),'52500.00','Frozen document total = 52,500.00');
select is(
  (select l->>'amount' from jsonb_array_elements((select payload->'document' from v1_r39_p3i where result_key='doc1')->'lines') l where l->>'stage_key'='design'),
  '50000.00','Frozen document has the Design building x stage line at 50,000.00');
select is((select payload->'document'->'amounts'->>'ex_vat' from v1_r39_p3i where result_key='preview'),'10000.00','Preview of the draft claim shows ex-VAT 10,000.00');

select finish();
rollback;

-- R39 Accounts Workspace V2 — what needs attention, and supplier delivery options

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d19000-0000-4000-8000-000000000001','R39-V2P4A-001','R39 V2 attention','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d19000-0000-4000-8000-000000000002','39d19000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d19000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d19000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d19000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d19000-0000-4000-8000-000000000004','39d19000-0000-4000-8000-000000000003',1,'r39/v2p4a/p.pdf','p.pdf','application/pdf',128,repeat('f',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d19000-0000-4000-8000-000000000004' where id='39d19000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d19000-0000-4000-8000-000000000005','39d19000-0000-4000-8000-000000000003','39d19000-0000-4000-8000-000000000001','project','39d19000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p4a(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p4a to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d19000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39d19000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f99000-0000-4000-8000-000000000081');
reset role;
insert into v1_r39_p4a select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d19000-0000-4000-8000-000000000001' and stage_key='design'));

-- No claim yet.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p4a select 'pe_none', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',true);
insert into v1_r39_p4a select 'acc_none', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');

select ok((select payload->'attention' @> '[{"kind":"no_claim"}]' from v1_r39_p4a where result_key='pe_none'),
  'someone who can start a claim is told none is in progress');
select ok(not (select payload->'attention' @> '[{"kind":"no_claim"}]' from v1_r39_p4a where result_key='acc_none'),
  'an Accountant, who cannot start a claim, is not told to');

-- A draft with an amount is waiting to be checked, not ready to invoice.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d19000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p4a where result_key='pid_design'),1,'100.0000','d',array['39d19000-0000-4000-8000-000000000003'::uuid],'c','39f99000-0000-4000-8000-000000000082');
insert into v1_r39_p4a select 'claim', public.v1_create_client_claim_draft('39d19000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p4a where result_key='pid_design'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f99000-0000-4000-8000-000000000083');
insert into v1_r39_p4a select 'pe_draft', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');
select ok((select payload->'attention' @> '[{"kind":"claim_draft"}]' from v1_r39_p4a where result_key='pe_draft'), 'an unchecked draft waits to be checked');
select ok(not (select payload->'attention' @> '[{"kind":"claim_ready"}]' from v1_r39_p4a where result_key='pe_draft'), 'an unchecked draft is not ready to invoice');
select is((select payload#>>'{badges,claims_draft}' from v1_r39_p4a where result_key='pe_draft'), 'true', 'the claims tab shows a draft');

-- Checked: ready to invoice, and never "no claim in progress".
select public.v1_submit_client_claim_to_accounts('39d19000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p4a where result_key='claim'),1,'r','39f99000-0000-4000-8000-000000000084');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',true);
insert into v1_r39_p4a select 'acc_ready', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');
select ok((select payload->'attention' @> '[{"kind":"claim_ready","action_key":"open_claim"}]' from v1_r39_p4a where result_key='acc_ready'), 'a checked claim is ready to invoice');
select ok(not (select payload->'attention' @> '[{"kind":"no_claim"}]' from v1_r39_p4a where result_key='acc_ready'), 'a checked claim is not "no claim in progress"');
select is((select payload#>>'{badges,claims_draft}' from v1_r39_p4a where result_key='acc_ready'), 'false', 'a checked claim is no longer a draft');
select is((select payload#>>'{steps,1,detail,claim_reference}' from v1_r39_p4a where result_key='acc_ready'), 'CLM-A', 'the progress step still names the claim');

-- Upload targets: only records this person may attach a file to.
insert into v1_r39_p4a select 'acc_docs', public.v1_get_accounts_documents('39d19000-0000-4000-8000-000000000001',null,null,false);
select ok((select payload->'upload_targets' @> '[{"entity_type":"accounts_baseline_revision"}]' from v1_r39_p4a where result_key='acc_docs'),
  'an Accountant, who can now edit the contract, is offered it');
select ok((select payload->'upload_targets' @> '[{"entity_type":"accounts_client_claim"}]' from v1_r39_p4a where result_key='acc_docs'),
  'an Accountant is offered the claim they can attach to');

-- Delivery options: empty list for those who may write a bill.
select is((public.v1_list_supplier_bill_delivery_options('39d19000-0000-4000-8000-000000000001'))->'deliveries', '[]'::jsonb, 'Accountant sees the (empty) delivery options');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select lives_ok($$select public.v1_list_supplier_bill_delivery_options('39d19000-0000-4000-8000-000000000001')$$, 'Admin may list delivery options');
insert into v1_r39_p4a select 'adm_docs', public.v1_get_accounts_documents('39d19000-0000-4000-8000-000000000001',null,null,false);
select ok((select payload->'upload_targets' @> '[{"entity_type":"accounts_baseline_revision"}]' from v1_r39_p4a where result_key='adm_docs'),
  'Admin, who can configure the contract, is offered it');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',true);
select lives_ok($$select public.v1_list_supplier_bill_delivery_options('39d19000-0000-4000-8000-000000000001')$$, 'Procurement may list delivery options');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select lives_ok($$select public.v1_list_supplier_bill_delivery_options('39d19000-0000-4000-8000-000000000001')$$, 'Project Engineer member may list delivery options (11 November 2026)');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select throws_ok($$select public.v1_list_supplier_bill_delivery_options('39d19000-0000-4000-8000-000000000001')$$, '42501', null, 'Site Engineer may not list delivery options');
reset role;

-- A site suggestion: visible on the workbench without money, and flagged only to
-- those who can confirm it.
insert into v1_r39_p4a select 'pid_mat', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d19000-0000-4000-8000-000000000001' and stage_key='material_supply'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select public.v1_suggest_billing_progress('39d19000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p4a where result_key='pid_mat'),1,'40.0000','On site',array['39d19000-0000-4000-8000-000000000003'::uuid],'s','39f99000-0000-4000-8000-000000000085');
insert into v1_r39_p4a select 'se_wb', public.v1_get_claim_workbench('39d19000-0000-4000-8000-000000000001',null);
select is((select c->>'suggested_percent' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='se_wb' and c->>'stage_key'='material_supply'), '40.0000', 'the Site Engineer sees their suggestion');
select is((select c->>'suggested_by' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='se_wb' and c->>'stage_key'='material_supply'), 'Local Site Engineer', 'the suggestion names who made it');
select ok((select c->'suggested_evidence_document_ids' ? '39d19000-0000-4000-8000-000000000003' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='se_wb' and c->>'stage_key'='material_supply'), 'the suggestion carries its evidence');
select ok(not (select c ? 'stage_value' or c ? 'eligible' or c ? 'claimed' or c ? 'available' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='se_wb' and c->>'stage_key'='material_supply'), 'a suggestion adds no commercial value for a Site Engineer');
select ok(not (select c ? 'suggested_percent' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='se_wb' and c->>'stage_key'='design'), 'a stage with no suggestion carries none');

select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p4a select 'pe_sug', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');
select ok((select payload->'attention' @> '[{"kind":"progress_suggested"}]' from v1_r39_p4a where result_key='pe_sug'), 'the Project Engineer is told a suggestion is waiting');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',true);
insert into v1_r39_p4a select 'acc_sug', public.v1_get_project_accounts_workspace('39d19000-0000-4000-8000-000000000001');
select ok(not (select payload->'attention' @> '[{"kind":"progress_suggested"}]' from v1_r39_p4a where result_key='acc_sug'), 'an Accountant, who cannot confirm it, is not');

-- Once confirmed, the suggestion is done.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d19000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p4a where result_key='pid_mat'),2,'40.0000','On site',array['39d19000-0000-4000-8000-000000000003'::uuid],'c','39f99000-0000-4000-8000-000000000086');
insert into v1_r39_p4a select 'pe_done', public.v1_get_claim_workbench('39d19000-0000-4000-8000-000000000001',null);
select ok(not (select c ? 'suggested_percent' from v1_r39_p4a, jsonb_array_elements(payload->'cells') c where result_key='pe_done' and c->>'stage_key'='material_supply'), 'a confirmed suggestion is no longer shown');
reset role;

select * from finish();
rollback;

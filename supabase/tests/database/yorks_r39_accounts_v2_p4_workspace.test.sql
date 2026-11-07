-- R39 Accounts Workspace V2 — P4 part b pgTAP: Summary workspace projection

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d10000-0000-4000-8000-000000000001','R39-V2P4W-001','R39 V2 P4 workspace','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d10000-0000-4000-8000-000000000002','39d10000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d10000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d10000-0000-4000-8000-000000000004','39d10000-0000-4000-8000-000000000003',1,'r39/v2p4w/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d10000-0000-4000-8000-000000000004' where id='39d10000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d10000-0000-4000-8000-000000000005','39d10000-0000-4000-8000-000000000003','39d10000-0000-4000-8000-000000000001','project','39d10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p4w(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p4w to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d10000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39d10000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000091');
select public.v1_save_project_invoice_settings('39d10000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f90000-0000-4000-8000-000000000092');
reset role;
insert into v1_r39_p4w select 'pid', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d10000-0000-4000-8000-000000000001' and stage_key='design'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39d10000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p4w where result_key='pid'),1,'100.0000','d',array['39d10000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000093');
insert into v1_r39_p4w select 'claim', public.v1_create_client_claim_draft('39d10000-0000-4000-8000-000000000001','CLM-P4W',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p4w where result_key='pid'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f90000-0000-4000-8000-000000000094');
select public.v1_submit_client_claim_to_accounts('39d10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p4w where result_key='claim'),1,'r','39f90000-0000-4000-8000-000000000095');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_issue_client_invoice('39d10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p4w where result_key='claim'),2,null,date '2026-08-26',date '2026-08-26','39f90000-0000-4000-8000-000000000096');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p4w select 'ws', public.v1_get_project_accounts_workspace('39d10000-0000-4000-8000-000000000001');
reset role;

select is((select payload->>'has_baseline' from v1_r39_p4w where result_key='ws'),'true','Workspace reports a baseline exists');
select is((select payload->'steps'->0->>'state' from v1_r39_p4w where result_key='ws'),'done','Step 1 (set up contract) is done');
select is((select payload->'steps'->2->>'state' from v1_r39_p4w where result_key='ws'),'done','Step 3 (issue invoice) is done');
select is((select payload->'kpis'->>'contract_value' from v1_r39_p4w where result_key='ws'),'1000000.00','KPI contract value = 1,000,000.00');
select is((select payload->'kpis'->>'invoiced' from v1_r39_p4w where result_key='ws'),'50000.00','KPI invoiced to date = 50,000.00');
select is((select payload->'money_flow'->>'invoiced_waiting' from v1_r39_p4w where result_key='ws'),'50000.00','Money-flow invoiced-waiting = 50,000.00');
select is((select payload->'money_flow'->>'remaining' from v1_r39_p4w where result_key='ws'),'950000.00','Money-flow remaining = contract 1,000,000 - 50,000');
select is(
  (select c->>'invoiced_percent' from jsonb_array_elements((select payload from v1_r39_p4w where result_key='ws')->'heatmap') c where c->>'stage_key'='design'),
  '50.0','Heatmap Design cell is 50% invoiced (50,000 of a 100,000 stage)');
select ok(
  (select count(*) from jsonb_array_elements((select payload from v1_r39_p4w where result_key='ws')->'attention') a where a->>'kind'='awaiting_certification') >= 1,
  'Attention flags the submitted invoice awaiting certification');

-- P4 part c: enriched step detail + badges (commercial actor).
select is((select payload->'steps'->0->'detail'->>'contract_value' from v1_r39_p4w where result_key='ws'),'1000000.00','Setup step detail carries the contract value');
select is((select payload->'steps'->0->'detail'->>'building_count' from v1_r39_p4w where result_key='ws'),'1','Setup step detail counts 1 building');
select is((select payload->'steps'->0->'detail'->>'stage_count' from v1_r39_p4w where result_key='ws'),'5','Setup step detail counts 5 stages');
select is((select payload->'steps'->2->'detail'->>'issued_count' from v1_r39_p4w where result_key='ws'),'1','Invoice step detail counts 1 issued invoice');
select ok((select payload ? 'badges' from v1_r39_p4w where result_key='ws'),'Workspace returns a badges object');
select is((select payload->'badges'->>'claims_draft' from v1_r39_p4w where result_key='ws'),'false','No open draft claim after the claim is invoiced');

select finish();
rollback;

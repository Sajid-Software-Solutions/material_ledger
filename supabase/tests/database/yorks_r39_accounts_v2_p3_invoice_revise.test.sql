-- R39 Accounts Workspace V2 — P3 part 2b-i pgTAP: invoice revision (R.n) + superseded

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39a10000-0000-4000-8000-000000000001','R39-V2P3R-001','R39 V2 P3 revise','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39a10000-0000-4000-8000-000000000002','39a10000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39a10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P3 revise authority','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39a10000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39a10000-0000-4000-8000-000000000004','39a10000-0000-4000-8000-000000000003',1,'r39/v2p3r/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39a10000-0000-4000-8000-000000000004' where id='39a10000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39a10000-0000-4000-8000-000000000005','39a10000-0000-4000-8000-000000000003','39a10000-0000-4000-8000-000000000001','project','39a10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p3r(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p3r to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39a10000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39a10000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000061');
select public.v1_save_project_invoice_settings('39a10000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f90000-0000-4000-8000-000000000062');
reset role;
insert into v1_r39_p3r select 'pid', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39a10000-0000-4000-8000-000000000001' and stage_key='design'));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39a10000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_r39_p3r where result_key='pid'),1,'100.0000','d',array['39a10000-0000-4000-8000-000000000003'::uuid],'c','39f90000-0000-4000-8000-000000000063');
insert into v1_r39_p3r select 'claim', public.v1_create_client_claim_draft('39a10000-0000-4000-8000-000000000001','CLM-R',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3r where result_key='pid'),'claimed_amount','50000.00','evidence_reference','V')),'a','39f90000-0000-4000-8000-000000000064');
select public.v1_submit_client_claim_to_accounts('39a10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3r where result_key='claim'),1,'r','39f90000-0000-4000-8000-000000000065');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p3r select 'issue1', public.v1_issue_client_invoice('39a10000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_p3r where result_key='claim'),2,null,date '2026-08-26',date '2026-08-26','39f90000-0000-4000-8000-000000000066');

-- Revise with a stale version is rejected.
select throws_ok(
  $$select public.v1_revise_client_invoice('39a10000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1'),999,'x','39f90000-0000-4000-8000-000000000067')$$,
  '40001','R39_ACCOUNTS_VERSION_CONFLICT','Revise rejects a stale invoice version');

-- Revise the submitted invoice -> successor draft claim.
insert into v1_r39_p3r select 'revise', public.v1_revise_client_invoice('39a10000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1'),2,'Client removed a line','39f90000-0000-4000-8000-000000000068');
reset role;
select is((select payload->>'status' from v1_r39_p3r where result_key='revise'),'draft','Revise creates a successor draft claim');

-- Regression: a workbench save must not delete the in-flight revise successor draft.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_save_claim_workbench('39a10000-0000-4000-8000-000000000001','CLM-WB-REG',date '2026-09-05',date '2026-09-25','[]'::jsonb,array[]::uuid[],'Workbench during revision','39f90000-0000-4000-8000-00000000006c');
reset role;
select ok(exists(select 1 from public.v1_accounts_client_claims
  where id=(select (payload->>'successor_claim_id')::uuid from v1_r39_p3r where result_key='revise')),
  'A workbench save does not delete the in-flight revise successor draft');

-- Submit and issue the successor -> R.1, predecessor superseded. The successor
-- claim was created by the admin reviser, so admin submits and issues it.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_submit_client_claim_to_accounts('39a10000-0000-4000-8000-000000000001',(select (payload->>'successor_claim_id')::uuid from v1_r39_p3r where result_key='revise'),1,'r','39f90000-0000-4000-8000-000000000069');
insert into v1_r39_p3r select 'issue2', public.v1_issue_client_invoice('39a10000-0000-4000-8000-000000000001',(select (payload->>'successor_claim_id')::uuid from v1_r39_p3r where result_key='revise'),2,null,date '2026-09-01',date '2026-09-01','39f90000-0000-4000-8000-00000000006a');
reset role;

select is((select payload->>'invoice_reference' from v1_r39_p3r where result_key='issue2'),'YRA32201R.1','Issuing the successor numbers it YRA32201R.1');
select is((select payload->>'revision_number' from v1_r39_p3r where result_key='issue2'),'1','The successor invoice is revision 1');
select is(
  (select status from public.v1_accounts_client_invoices where id=(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1')),
  'cancelled','The predecessor invoice is retired (cancelled) on supersession');
select ok(
  (select cancellation_reason from public.v1_accounts_client_invoices where id=(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1')) like 'Superseded by %',
  'The predecessor invoice carries a "Superseded by ..." reason');
select is(
  (select supersedes_invoice_id from public.v1_accounts_client_invoices where id=(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue2')),
  (select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1'),
  'The successor invoice links to the predecessor via supersedes_invoice_id');
select is(
  (select status from public.v1_accounts_client_claims where id=(select (payload->>'claim_id')::uuid from v1_r39_p3r where result_key='claim')),
  'cancelled','The predecessor claim is retired (cancelled), releasing its capacity');

-- Revising the now-retired predecessor is rejected.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select throws_ok(
  $$select public.v1_revise_client_invoice('39a10000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_p3r where result_key='issue1'),3,'x','39f90000-0000-4000-8000-00000000006b')$$,
  '55000','R39_ACCOUNTS_INVOICE_NOT_REVISABLE','A superseded invoice cannot be revised again');
reset role;

select finish();
rollback;

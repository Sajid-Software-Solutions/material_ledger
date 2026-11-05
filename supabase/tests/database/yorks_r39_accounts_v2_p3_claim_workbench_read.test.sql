-- R39 Accounts Workspace V2 — P3 part 1 pgTAP: claim workbench read + reopen

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39fe0000-0000-4000-8000-000000000001','R39-V2P3-001','R39 V2 P3 workbench','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39fe0000-0000-4000-8000-000000000002','39fe0000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39fe0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P3 authority','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39fe0000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39fe0000-0000-4000-8000-000000000004','39fe0000-0000-4000-8000-000000000003',1,'r39/v2p3/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39fe0000-0000-4000-8000-000000000004' where id='39fe0000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39fe0000-0000-4000-8000-000000000005','39fe0000-0000-4000-8000-000000000003','39fe0000-0000-4000-8000-000000000001','project','39fe0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p3(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p3 to authenticated;

-- Admin sets up the baseline (contract 1,000,000; Design 10% -> eligible 100,000 at 100%).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39fe0000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fe0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000041');
reset role;
insert into v1_r39_p3 select 'design_pid', jsonb_build_object('id',
  (select id from public.v1_accounts_billing_progress where project_id='39fe0000-0000-4000-8000-000000000001' and stage_key='design'));

-- PE confirms Design 100%, claims 50,000, submits to accounts.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('39fe0000-0000-4000-8000-000000000001',
  (select (payload->>'id')::uuid from v1_r39_p3 where result_key='design_pid'),
  1,'100.0000','Design complete', array['39fe0000-0000-4000-8000-000000000003'::uuid],'Confirm','39f90000-0000-4000-8000-000000000042');
insert into v1_r39_p3 select 'claim', public.v1_create_client_claim_draft('39fe0000-0000-4000-8000-000000000001','CLM-P3-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3 where result_key='design_pid'),'claimed_amount','50000.00','evidence_reference','VAL-P3')),
  'Claim','39f90000-0000-4000-8000-000000000043');
select public.v1_submit_client_claim_to_accounts('39fe0000-0000-4000-8000-000000000001',
  (select (payload->>'claim_id')::uuid from v1_r39_p3 where result_key='claim'),1,'Ready','39f90000-0000-4000-8000-000000000044');

-- Workbench read (PE).
insert into v1_r39_p3 select 'wb1', public.v1_get_claim_workbench('39fe0000-0000-4000-8000-000000000001', null);
reset role;

select is((select payload->'claim'->>'status' from v1_r39_p3 where result_key='wb1'),'ready_for_accounts','Workbench returns the open claim as ready_for_accounts');
select is(
  (select c->>'confirmed_percent' from jsonb_array_elements((select payload from v1_r39_p3 where result_key='wb1')->'cells') c where c->>'stage_key'='design'),
  '100.0000','Design cell is 100% confirmed');
select is(
  (select c->>'eligible' from jsonb_array_elements((select payload from v1_r39_p3 where result_key='wb1')->'cells') c where c->>'stage_key'='design'),
  '100000.00','Design cell eligible = 100,000.00 (visible to PE)');
select is(
  (select c->>'available' from jsonb_array_elements((select payload from v1_r39_p3 where result_key='wb1')->'cells') c where c->>'stage_key'='design'),
  '50000.00','Design cell available = eligible 100,000 minus claimed 50,000');

-- Reopen: stale version is rejected, correct version returns to draft.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select throws_ok(
  $$select public.v1_reopen_client_claim('39fe0000-0000-4000-8000-000000000001',
    (select (payload->>'claim_id')::uuid from v1_r39_p3 where result_key='claim'),999,'x','39f90000-0000-4000-8000-000000000045')$$,
  '40001','R39_ACCOUNTS_VERSION_CONFLICT','Reopen rejects a stale expected version');
insert into v1_r39_p3 select 'reopen', public.v1_reopen_client_claim('39fe0000-0000-4000-8000-000000000001',
  (select (payload->>'claim_id')::uuid from v1_r39_p3 where result_key='claim'),2,'Back to draft','39f90000-0000-4000-8000-000000000046');
insert into v1_r39_p3 select 'wb2', public.v1_get_claim_workbench('39fe0000-0000-4000-8000-000000000001', null);
reset role;

select is((select payload->>'status' from v1_r39_p3 where result_key='reopen'),'draft','Reopen returns the claim to draft');
select is((select payload->'claim'->>'status' from v1_r39_p3 where result_key='wb2'),'draft','Workbench reflects the reopened draft claim');

select finish();
rollback;

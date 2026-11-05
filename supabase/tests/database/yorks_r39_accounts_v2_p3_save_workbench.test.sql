-- R39 Accounts Workspace V2 — P3 part 2c pgTAP: save claim workbench

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39b10000-0000-4000-8000-000000000001','R39-V2P3W-001','R39 V2 P3 workbench save','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39b10000-0000-4000-8000-000000000002','39b10000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39b10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P3 workbench authority','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39b10000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39b10000-0000-4000-8000-000000000004','39b10000-0000-4000-8000-000000000003',1,'r39/v2p3w/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39b10000-0000-4000-8000-000000000004' where id='39b10000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39b10000-0000-4000-8000-000000000005','39b10000-0000-4000-8000-000000000003','39b10000-0000-4000-8000-000000000001','project','39b10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p3w(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p3w to authenticated;

-- Admin baseline: Design 10% (percent), Material Supply 50% (items: A 30% qty10, B 20% qty5).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39b10000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39b10000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','a','item_label','Item A','display_order',1,'quantity','10','unit_code','Nos','weight_percent_of_contract','30'),
          jsonb_build_object('item_key','b','item_label','Item B','display_order',2,'quantity','5','unit_code','Nos','weight_percent_of_contract','20'))),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f90000-0000-4000-8000-000000000071');
reset role;
insert into v1_r39_p3w select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39b10000-0000-4000-8000-000000000001' and stage_key='design'));
insert into v1_r39_p3w select 'item_a', jsonb_build_object('id',(select id from public.v1_accounts_baseline_stage_items where project_id='39b10000-0000-4000-8000-000000000001' and stage_key='material_supply' and item_key='a'));
insert into v1_r39_p3w select 'item_b', jsonb_build_object('id',(select id from public.v1_accounts_baseline_stage_items where project_id='39b10000-0000-4000-8000-000000000001' and stage_key='material_supply' and item_key='b'));

-- PE: confirm Design 100% and both item quantities, and build the draft claim in one call.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p3w select 'save1', public.v1_save_claim_workbench(
  '39b10000-0000-4000-8000-000000000001','CLM-WB-1',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(
    jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_r39_p3w where result_key='pid_design'),'confirmed_percent_to_date','100.0000'),
    jsonb_build_object('stage_item_id',(select (payload->>'id')::uuid from v1_r39_p3w where result_key='item_a'),'confirmed_qty_to_date','10'),
    jsonb_build_object('stage_item_id',(select (payload->>'id')::uuid from v1_r39_p3w where result_key='item_b'),'confirmed_qty_to_date','5')),
  array['39b10000-0000-4000-8000-000000000003'::uuid],'Monthly claim','39f90000-0000-4000-8000-000000000072');
reset role;

select is((select payload->>'confirmed_rows' from v1_r39_p3w where result_key='save1'),'3','One percent row and two item quantities are confirmed');
select is((select payload->'claim'->>'status' from v1_r39_p3w where result_key='save1'),'draft','The workbench builds a draft claim');
select is(
  (select sum(l.claimed_amount)::numeric(20,2)::text from public.v1_accounts_client_claim_lines l
   join public.v1_accounts_client_claims c on c.id=l.claim_id
   where c.project_id='39b10000-0000-4000-8000-000000000001' and c.status='draft'),
  '600000.00','Draft claim totals Design 100,000 + Material items 500,000 = 600,000');

-- Second save (no new entries) rebuilds the single draft.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p3w select 'save2', public.v1_save_claim_workbench(
  '39b10000-0000-4000-8000-000000000001','CLM-WB-1',date '2026-08-01',date '2026-08-25',
  '[]'::jsonb, array[]::uuid[],'Rebuild','39f90000-0000-4000-8000-000000000073');
reset role;

select is(
  (select count(*)::text from public.v1_accounts_client_claims where project_id='39b10000-0000-4000-8000-000000000001' and status='draft'),
  '1','A second save rebuilds the single open draft (no duplicate drafts)');
select is(
  (select sum(l.claimed_amount)::numeric(20,2)::text from public.v1_accounts_client_claim_lines l
   join public.v1_accounts_client_claims c on c.id=l.claim_id
   where c.project_id='39b10000-0000-4000-8000-000000000001' and c.status='draft'),
  '600000.00','The rebuilt draft keeps the same 600,000 total');

-- Role negative: an Accountant (no prepare_client_claim) cannot save the workbench.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',true);
select throws_ok(
  $$select public.v1_save_claim_workbench('39b10000-0000-4000-8000-000000000001','CLM-X',date '2026-08-01',date '2026-08-25','[]'::jsonb,array[]::uuid[],'x','39f90000-0000-4000-8000-000000000074')$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED','An Accountant without prepare_client_claim cannot save the workbench');
reset role;

select finish();
rollback;

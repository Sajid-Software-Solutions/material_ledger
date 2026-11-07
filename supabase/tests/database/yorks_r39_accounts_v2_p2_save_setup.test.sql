-- R39 Accounts Workspace V2 — P2 part 2 pgTAP: save-setup with carry-forward
--
-- Proves v1_save_project_commercial_setup: a contract revision carries confirmed
-- progress forward (Design stays 100%), a non-configure actor is denied, and an
-- item quantity reduced below the confirmed quantity is capped and flagged
-- needs_review (never silently dropped).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- ===== Fixtures: two projects, one building each, PE member, evidence doc. =====
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39fb0000-0000-4000-8000-000000000001','R39-V2P2B-001','R39 V2 P2 carry-forward','active','project_engineer','10000000-0000-4000-8000-000000000004','admin'),
      ('39fc0000-0000-4000-8000-000000000001','R39-V2P2C-001','R39 V2 P2 items carry-forward','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39fb0000-0000-4000-8000-000000000002','39fb0000-0000-4000-8000-000000000001','building','b01','Building 01',false),
      ('39fc0000-0000-4000-8000-000000000002','39fc0000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39fb0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P2 authority','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39fb0000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39fb0000-0000-4000-8000-000000000004','39fb0000-0000-4000-8000-000000000003',1,'r39/v2p2/progress.pdf','progress.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39fb0000-0000-4000-8000-000000000004' where id='39fb0000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39fb0000-0000-4000-8000-000000000005','39fb0000-0000-4000-8000-000000000003','39fb0000-0000-4000-8000-000000000001','project','39fb0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p2b(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p2b to authenticated;

-- Default percent stages (sum 100).
create temporary table v1_r39_stage_tpl(stages jsonb);
insert into v1_r39_stage_tpl values (jsonb_build_array(
  jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
  jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
  jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
  jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
  jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent')));
grant select on v1_r39_stage_tpl to authenticated;

-- ===== Test A: percent carry-forward keeps Design 100% across a revision. =====
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p2b select 'init', public.v1_save_project_commercial_setup(
  '39fb0000-0000-4000-8000-000000000001', null,
  jsonb_build_object(
    'contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fb0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', (select stages from v1_r39_stage_tpl)),
  'Initial setup','39f90000-0000-4000-8000-000000000021');
select is((select payload->>'baseline_revision_number' from v1_r39_p2b where result_key='init'),'1','save-setup initializes revision 1');

-- Capture the Design progress id as superuser (authenticated cannot read the table).
reset role;
insert into v1_r39_p2b select 'design_pid', jsonb_build_object('id',
  (select id from public.v1_accounts_billing_progress where project_id='39fb0000-0000-4000-8000-000000000001' and stage_key='design'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress(
  '39fb0000-0000-4000-8000-000000000001',
  (select (payload->>'id')::uuid from v1_r39_p2b where result_key='design_pid'),
  1,'100.0000','Design complete', array['39fb0000-0000-4000-8000-000000000003'::uuid],
  'Confirm design','39f90000-0000-4000-8000-000000000022');

-- Admin revises the contract value via save-setup.
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p2b select 'revise', public.v1_save_project_commercial_setup(
  '39fb0000-0000-4000-8000-000000000001', 1,
  jsonb_build_object(
    'contract_value','1200000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fb0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', (select stages from v1_r39_stage_tpl)),
  'Contract value increased','39f90000-0000-4000-8000-000000000023');

reset role;
select is((select payload->>'baseline_revision_number' from v1_r39_p2b where result_key='revise'),'2','save-setup revises to revision 2');
select is((select payload->>'carried_forward_progress_rows' from v1_r39_p2b where result_key='revise'),'1','One confirmed row is carried forward');
select is(
  (select confirmed_percent::text from public.v1_accounts_billing_progress
   where project_id='39fb0000-0000-4000-8000-000000000001' and stage_key='design'
     and baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fb0000-0000-4000-8000-000000000001')),
  '100.0000',
  'Design stays 100% confirmed on the new revision (carry-forward, not wiped to 0)');
select is(
  (select contract_value::text from public.v1_accounts_baseline_revisions
   where id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fb0000-0000-4000-8000-000000000001')),
  '1200000.00','The revision carries the new contract value');
-- A carried_forward progress revision is recorded.
select ok(exists(
  select 1 from public.v1_accounts_billing_progress_revisions r
  join public.v1_accounts_billing_progress bp on bp.id=r.progress_entry_id
  where bp.project_id='39fb0000-0000-4000-8000-000000000001' and r.action='carried_forward'),
  'A carried_forward progress revision is appended');

-- ===== Test B: a non-configure actor is denied. =====
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select throws_ok(
  $$select public.v1_save_project_commercial_setup(
    '39fb0000-0000-4000-8000-000000000001', 2,
    jsonb_build_object('contract_value','1300000.00','currency_code','AED','vat_rate_percent','5.0000',
      'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fb0000-0000-4000-8000-000000000002','allocation_percent','100')),
      'stages', (select stages from v1_r39_stage_tpl)),
    'SE cannot configure','39f90000-0000-4000-8000-000000000024')$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED',
  'A Site Engineer without configure_project_commercials cannot save the contract');

-- ===== Test C: item carry-forward caps a reduced quantity and flags needs_review. =====
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p2b select 'c_init', public.v1_save_project_commercial_setup(
  '39fc0000-0000-4000-8000-000000000001', null,
  jsonb_build_object(
    'contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fc0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','50','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','a','item_label','Item A','display_order',1,'quantity','10','unit_code','Nos','weight_percent_of_contract','30'),
          jsonb_build_object('item_key','b','item_label','Item B','display_order',2,'quantity','5','unit_code','Nos','weight_percent_of_contract','20'))))),
  'Items setup','39f90000-0000-4000-8000-000000000031');
reset role;
select is((select payload->>'baseline_revision_number' from v1_r39_p2b where result_key='c_init'),'1','Items setup initializes revision 1');

-- Simulate confirmed item quantities on revision 1 (Item A 10/10, Item B 5/5).
insert into public.v1_accounts_billing_item_progress(project_id,baseline_revision_id,progress_entry_id,stage_item_id,project_scope_id,stage_key,item_key,confirmed_qty)
select '39fc0000-0000-4000-8000-000000000001',
  (select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fc0000-0000-4000-8000-000000000001'),
  (select id from public.v1_accounts_billing_progress where project_id='39fc0000-0000-4000-8000-000000000001' and stage_key='material_supply'),
  si.id,'39fc0000-0000-4000-8000-000000000002','material_supply',si.item_key,
  case si.item_key when 'a' then 10 when 'b' then 5 end
from public.v1_accounts_baseline_stage_items si
where si.project_scope_id='39fc0000-0000-4000-8000-000000000002' and si.stage_key='material_supply'
  and si.baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fc0000-0000-4000-8000-000000000001');

-- Revise reducing Item B from 5 to 3 (weight still 20 so items sum to 50%).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p2b select 'c_revise', public.v1_save_project_commercial_setup(
  '39fc0000-0000-4000-8000-000000000001', 1,
  jsonb_build_object(
    'contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39fc0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','50','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','a','item_label','Item A','display_order',1,'quantity','10','unit_code','Nos','weight_percent_of_contract','30'),
          jsonb_build_object('item_key','b','item_label','Item B','display_order',2,'quantity','3','unit_code','Nos','weight_percent_of_contract','20'))))),
  'Reduce Item B quantity','39f90000-0000-4000-8000-000000000032');
reset role;

select is((select payload->>'items_needs_review' from v1_r39_p2b where result_key='c_revise'),'1','One item is flagged needs_review after the reduction');
select is(
  (select ip.confirmed_qty::text from public.v1_accounts_billing_item_progress ip
   join public.v1_accounts_baseline_stage_items si on si.id=ip.stage_item_id
   where ip.baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fc0000-0000-4000-8000-000000000001')
     and si.item_key='b'),
  '3.0000',
  'Item B confirmed quantity is capped to the new quantity (3), not left at 5');
select is(
  (select ip.confirmed_qty::text from public.v1_accounts_billing_item_progress ip
   join public.v1_accounts_baseline_stage_items si on si.id=ip.stage_item_id
   where ip.baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39fc0000-0000-4000-8000-000000000001')
     and si.item_key='a'),
  '10.0000',
  'Item A confirmed quantity (10) carries forward unchanged');

select finish();
rollback;

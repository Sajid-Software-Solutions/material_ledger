-- R39 Accounts Workspace V2 — P6 part a pgTAP: commercial-setup read

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d16000-0000-4000-8000-000000000001','R39-V2P6S-001','R39 V2 P6 setup read','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d16000-0000-4000-8000-000000000002','39d16000-0000-4000-8000-000000000001','building','b01','Building 01',false),
      ('39d16000-0000-4000-8000-000000000003','39d16000-0000-4000-8000-000000000001','building','b02','Building 02',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d16000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
      ('39d16000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p6s(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p6s to authenticated;

-- Admin sets up the contract (2 x 50% buildings, Yorks standard stages) and the
-- invoice numbering prefix.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('39d16000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id','39d16000-0000-4000-8000-000000000002','allocation_percent','50'),
      jsonb_build_object('building_scope_id','39d16000-0000-4000-8000-000000000003','allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39f96000-0000-4000-8000-000000000091');
select public.v1_save_project_invoice_settings('39d16000-0000-4000-8000-000000000001','YRA322',null,null,null,null,'39f96000-0000-4000-8000-000000000092');
reset role;

-- Flip Material Supply to items mode and register one item on Building 01.
-- Weight 25% = building 50% x stage 50%, so the single item's value equals the
-- building x stage cell value (250,000) via v1_accounts_stage_item_value.
update public.v1_accounts_baseline_stage_allocations
set measurement_mode = 'items'
where project_id = '39d16000-0000-4000-8000-000000000001' and stage_key = 'material_supply';
insert into public.v1_accounts_baseline_stage_items
  (baseline_revision_id,project_id,project_scope_id,stage_key,item_key,item_label,display_order,quantity,unit_code,weight_percent_of_contract)
select p.current_baseline_revision_id,'39d16000-0000-4000-8000-000000000001','39d16000-0000-4000-8000-000000000002',
       'material_supply','ahu','AHU units',1,'4','Nos','25'
from public.v1_accounts_project_commercial_profiles p
where p.project_id = '39d16000-0000-4000-8000-000000000001';

-- Read as admin (full) and as the site engineer (no commercial values).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p6s select 'admin', public.v1_get_project_commercial_setup('39d16000-0000-4000-8000-000000000001');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
insert into v1_r39_p6s select 'se', public.v1_get_project_commercial_setup('39d16000-0000-4000-8000-000000000001');
reset role;

-- Admin: full commercial setup.
select is((select payload->>'has_baseline' from v1_r39_p6s where result_key='admin'),'true','Setup read reports a baseline exists');
select is((select payload->>'can_configure' from v1_r39_p6s where result_key='admin'),'true','Admin can configure commercials');
select is((select payload->>'contract_value' from v1_r39_p6s where result_key='admin'),'1000000.00','Contract value = 1,000,000.00');
select is((select payload->>'currency_code' from v1_r39_p6s where result_key='admin'),'AED','Currency is AED');
select is((select payload->'invoice_settings'->>'invoice_prefix' from v1_r39_p6s where result_key='admin'),'YRA322','Invoice prefix carried through');
select is(
  (select jsonb_array_length((select payload from v1_r39_p6s where result_key='admin')->'buildings')),
  2,'Both buildings are returned');
select is(
  (select b->>'value' from jsonb_array_elements((select payload from v1_r39_p6s where result_key='admin')->'buildings') b where b->>'name'='Building 01'),
  '500000.00','Building 01 value = contract x 50%');
select is(
  (select s->>'value' from jsonb_array_elements((select payload from v1_r39_p6s where result_key='admin')->'stages') s where s->>'stage_key'='design'),
  '100000.00','Design stage value = contract x 10%');
select is(
  (select s->>'measurement_mode' from jsonb_array_elements((select payload from v1_r39_p6s where result_key='admin')->'stages') s where s->>'stage_key'='material_supply'),
  'items','Material Supply is items-mode');
select is(
  (select it->>'value' from jsonb_array_elements((select payload from v1_r39_p6s where result_key='admin')->'items') it where it->>'item_key'='ahu'),
  '250000.00','Single AHU item value = its building x stage cell value');
select is(
  (select it->>'quantity' from jsonb_array_elements((select payload from v1_r39_p6s where result_key='admin')->'items') it where it->>'item_key'='ahu'),
  '4.0000','AHU item quantity carried through');

-- Site engineer: accounts access but no commercial values -> amounts omitted.
select is((select payload->'capabilities'->>'view_project_commercial_values' from v1_r39_p6s where result_key='se'),'false','Site engineer has no commercial-value access');
select is((select payload->>'has_baseline' from v1_r39_p6s where result_key='se'),'true','Site engineer still learns a baseline exists');
select ok((select not ((payload) ? 'contract_value') from v1_r39_p6s where result_key='se'),'Contract value omitted (not zeroed) for the site engineer');
select ok((select not ((payload) ? 'buildings') from v1_r39_p6s where result_key='se'),'Building split omitted for the site engineer');

select finish();
rollback;

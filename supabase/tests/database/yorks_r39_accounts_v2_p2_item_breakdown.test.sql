-- R39 Accounts Workspace V2 — P2 part 1 pgTAP: item-quantity billing foundation
--
-- Reproduces the YRA-322 DF3W Material Supply fixture from the integration plan
-- (section 12): contract 17,192,000.00, DF3W building 25%, Material stage 50%
-- -> stage value 2,149,000.00. The 15 Material items carry the prototype's
-- weights (% of total contract) and the INVOICE#02 confirmed quantities.
--
-- Proves: item values sum to the stage value to the fil; AC Units (4.5%) =
-- 773,640.00; the items-mode eligible reproduces 1,549,624.36; and percent-mode
-- eligible is unchanged.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Fixtures: project + two building scopes (DF3W 25%, REST 75%).
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39f10000-0000-4000-8000-000000000011','R39-V2P2-001','R39 V2 P2 item breakdown','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39f20000-0000-4000-8000-000000000011','39f10000-0000-4000-8000-000000000011','building','df3w','DF3W',false),
      ('39f20000-0000-4000-8000-000000000012','39f10000-0000-4000-8000-000000000011','building','rest','REST',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39f10000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P2 authority','10000000-0000-4000-8000-000000000004','admin');

-- Admin initializes the baseline (default 10/50/30/5/5 stages).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_initialize_project_commercial_baseline(
  '39f10000-0000-4000-8000-000000000011','17192000.00','AED','5.0000',null,null,
  jsonb_build_array(
    jsonb_build_object('building_scope_id','39f20000-0000-4000-8000-000000000011','allocation_percent','25.0000'),
    jsonb_build_object('building_scope_id','39f20000-0000-4000-8000-000000000012','allocation_percent','75.0000')),
  null,'{}'::jsonb,'V2 P2 baseline','39f90000-0000-4000-8000-000000000011');
reset role;

-- Set the Material stage to items mode (the P2 part-2 setup command will do this
-- in product; here it is a fixture).
update public.v1_accounts_baseline_stage_allocations
set measurement_mode='items'
where stage_key='material_supply'
  and baseline_revision_id=(select current_baseline_revision_id
    from public.v1_accounts_project_commercial_profiles
    where project_id='39f10000-0000-4000-8000-000000000011');

-- The 15 Material items for DF3W (weights % of total contract; sum = 12.5%).
insert into public.v1_accounts_baseline_stage_items(
  id,baseline_revision_id,project_id,project_scope_id,stage_key,item_key,item_label,display_order,quantity,unit_code,weight_percent_of_contract)
select ('39fa0000-0000-4000-8000-'||lpad(v.ord::text,12,'0'))::uuid,
  (select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39f10000-0000-4000-8000-000000000011'),
  '39f10000-0000-4000-8000-000000000011','39f20000-0000-4000-8000-000000000011','material_supply',
  v.item_key,v.label,v.ord,v.qty,v.unit,v.weight
from (values
  ('m1','AC Units (Package Unit)',1,6,'Nos',4.5),
  ('m2','Ventilation Fans',2,30,'Nos',1.0),
  ('m3','BMS Control Panel and Controls',3,5,'Nos',1.0),
  ('m4','Motorized Fire Dampers',4,55,'Nos',1.0),
  ('m5','Electrical Duct Heater',5,2,'Nos',0.5),
  ('m6','Sound Attenuators',6,4,'Nos',0.5),
  ('m7','Air Outlets Inlets and Dampers',7,1,'Lot',0.5),
  ('m8','Power and Control Cables Trays and Trunking',8,1,'Lot',0.5),
  ('m9','CU FCU Fire Pump Room',9,1,'Lot',0.5),
  ('m10','Ducting Basement Floor',10,1,'Lot',0.5),
  ('m11','Ducting Ground Floor',11,1,'Lot',0.5),
  ('m12','Ducting First Floor',12,1,'Lot',0.5),
  ('m13','Ducting Roof',13,1,'Lot',0.4),
  ('m14','Ducting Stairs 1 to 5',14,1,'Lot',0.3),
  ('m15','Ref Pipes and Accessories',15,1,'Lot',0.3)
) as v(item_key,label,ord,qty,unit,weight);

-- INVOICE#02 confirmed quantities for DF3W Material.
insert into public.v1_accounts_billing_item_progress(
  id,project_id,baseline_revision_id,progress_entry_id,stage_item_id,project_scope_id,stage_key,item_key,confirmed_qty)
select gen_random_uuid(),'39f10000-0000-4000-8000-000000000011',
  (select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39f10000-0000-4000-8000-000000000011'),
  (select id from public.v1_accounts_billing_progress where project_id='39f10000-0000-4000-8000-000000000011' and project_scope_id='39f20000-0000-4000-8000-000000000011' and stage_key='material_supply'),
  si.id,'39f20000-0000-4000-8000-000000000011','material_supply',si.item_key,c.confirmed_qty::numeric
from public.v1_accounts_baseline_stage_items si
join (values ('m1',6),('m3',5),('m4',20),('m6',4),('m7',0.5),('m8',0.8),('m9',1),('m10',1),('m11',1),('m12',1))
  as c(item_key,confirmed_qty) on c.item_key=si.item_key
where si.project_scope_id='39f20000-0000-4000-8000-000000000011' and si.stage_key='material_supply'
  and si.baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39f10000-0000-4000-8000-000000000011');

-- The DF3W Material cell's stage value is 2,149,000.00.
select is(
  public.v1_accounts_stage_value(
    (select id from public.v1_accounts_billing_progress where project_id='39f10000-0000-4000-8000-000000000011' and project_scope_id='39f20000-0000-4000-8000-000000000011' and stage_key='material_supply'))::numeric(20,2)::text,
  '2149000.00',
  'DF3W Material stage value = 2,149,000.00'
);

-- AC Units item value (4.5% of contract) = 773,640.00.
select is(
  public.v1_accounts_stage_item_value('39fa0000-0000-4000-8000-000000000001')::text,
  '773640.00',
  'AC Units item value (4.5%) = 773,640.00'
);

-- Item values sum to the stage value to the fil.
select is(
  (select sum(public.v1_accounts_stage_item_value(si.id))::numeric(20,2)::text
   from public.v1_accounts_baseline_stage_items si
   where si.project_scope_id='39f20000-0000-4000-8000-000000000011' and si.stage_key='material_supply'
     and si.baseline_revision_id=(select current_baseline_revision_id from public.v1_accounts_project_commercial_profiles where project_id='39f10000-0000-4000-8000-000000000011')),
  '2149000.00',
  'Item values sum exactly to the DF3W Material stage value'
);

-- Items-mode eligible at the confirmed quantities reproduces 1,549,624.36.
select is(
  public.v1_accounts_progress_eligible_amount(
    (select id from public.v1_accounts_billing_progress where project_id='39f10000-0000-4000-8000-000000000011' and project_scope_id='39f20000-0000-4000-8000-000000000011' and stage_key='material_supply'))::text,
  '1549624.36',
  'DF3W Material items-mode eligible reproduces the INVOICE#02 figure 1,549,624.36'
);

-- Percent-mode eligible is unchanged: the design stage (percent, unconfirmed)
-- goes through the percent branch and equals the inline formula.
select is(
  public.v1_accounts_progress_eligible_amount(
    (select id from public.v1_accounts_billing_progress where project_id='39f10000-0000-4000-8000-000000000011' and project_scope_id='39f20000-0000-4000-8000-000000000011' and stage_key='design')),
  round(public.v1_accounts_stage_value(
    (select id from public.v1_accounts_billing_progress where project_id='39f10000-0000-4000-8000-000000000011' and project_scope_id='39f20000-0000-4000-8000-000000000011' and stage_key='design')) * 0 / 100, 2),
  'Percent-mode eligible stays byte-identical to the inline formula'
);

select finish();
rollback;

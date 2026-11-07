-- R39 Accounts Workspace V2 — Material Supply items linked to BOQ folders
--
-- Who may link, which folders can be linked (a physical building's own, never
-- Common, Workshop Materials or an archived folder), and what the delivered
-- quantities come to: good quantity received less confirmed returns, added up
-- when the units agree and as a share of the BOQ rows when they do not.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.act(p_who text) returns void language plpgsql as $$
declare v_id text; v_role text;
begin
  select id, role into v_id, v_role from (values
    ('pe','10000000-0000-4000-8000-000000000001','project_engineer'),
    ('se','10000000-0000-4000-8000-000000000002','site_engineer'),
    ('procurement','10000000-0000-4000-8000-000000000003','procurement'),
    ('admin','10000000-0000-4000-8000-000000000004','admin'),
    ('accountant','10000000-0000-4000-8000-000000000013','accountant')
  ) as actor(who, id, role) where who = p_who;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_id, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', v_role, 'app_user_id', 'usr-local-' || p_who)
  )::text, true);
end;
$$;

create sequence pg_temp.key_seq;
create function pg_temp.key() returns uuid language sql as $$
  select ('39fa0000-0000-4000-8000-' || lpad(nextval('pg_temp.key_seq')::text, 12, '0'))::uuid;
$$;

-- Ids: project ...01; buildings ...02 (B1) ...03 (B2); Common ...04.
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39fa1000-0000-4000-8000-000000000001','R39-ML-001','R39 material links','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable) values
('39fa1000-0000-4000-8000-000000000002','39fa1000-0000-4000-8000-000000000001','building','b1','Building 1',false),
('39fa1000-0000-4000-8000-000000000003','39fa1000-0000-4000-8000-000000000001','building','b2','Building 2',false),
('39fa1000-0000-4000-8000-000000000004','39fa1000-0000-4000-8000-000000000001','common','common','Common / All Buildings',true);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role) values
('39fa1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
('39fa1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');

-- A contract whose Material Supply is measured by two items in each building.
create function pg_temp.setup() returns jsonb language sql as $$
  select jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id','39fa1000-0000-4000-8000-000000000002','allocation_percent','50'),
      jsonb_build_object('building_scope_id','39fa1000-0000-4000-8000-000000000003','allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','50','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','ac','item_label','AC Units','display_order',1,'quantity','6','unit_code','Nos','weight_percent_of_contract','12.5'),
          jsonb_build_object('item_key','duct','item_label','Ducting','display_order',2,'quantity','1','unit_code','Lot','weight_percent_of_contract','12.5')))));
$$;
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39fa1000-0000-4000-8000-000000000001',null,pg_temp.setup(),'Contract',pg_temp.key())$$,'The contract is set up');

-- BOQ and deliveries, entered directly: this file tests the reading of them,
-- not the Material Request workflow that normally creates them.
reset role;
set local session_replication_role = replica;
-- New scopes are seeded with Workshop Materials; replace them with this file's own folders.
delete from public.v1_boq_groups where project_id='39fa1000-0000-4000-8000-000000000001';
insert into public.v1_boq_groups(id,project_id,scope_id,template_id,name,display_order,worksheet_title,created_by_auth_user_id,is_archived,archived_at,archived_by_auth_user_id,is_custom) values
('39fa1000-0000-4000-8000-000000000011','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002',(select id from public.v1_boq_group_templates where template_key='ac_units'),'AC Units',1,'AC Units','10000000-0000-4000-8000-000000000001',false,null,null,false),
('39fa1000-0000-4000-8000-000000000012','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002',(select id from public.v1_boq_group_templates where template_key='gi_ductwork'),'GI Ductwork',2,'GI Ductwork','10000000-0000-4000-8000-000000000001',false,null,null,false),
('39fa1000-0000-4000-8000-000000000013','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002',(select id from public.v1_boq_group_templates where template_key='workshop_materials'),'Workshop Materials',3,'Workshop Materials','10000000-0000-4000-8000-000000000001',false,null,null,false),
('39fa1000-0000-4000-8000-000000000014','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000004',(select id from public.v1_boq_group_templates where template_key='ac_units'),'AC Units',1,'AC Units','10000000-0000-4000-8000-000000000001',false,null,null,false),
('39fa1000-0000-4000-8000-000000000015','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000003',(select id from public.v1_boq_group_templates where template_key='ac_units'),'AC Units',1,'AC Units','10000000-0000-4000-8000-000000000001',false,null,null,false),
('39fa1000-0000-4000-8000-000000000016','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002',null,'Old folder',4,'Old folder','10000000-0000-4000-8000-000000000001',true,clock_timestamp(),'10000000-0000-4000-8000-000000000001',true);
insert into public.v1_boq_rows(id,group_id,display_order,canonical_values,created_by_auth_user_id) values
('39fa1000-0000-4000-8000-000000000021','39fa1000-0000-4000-8000-000000000011',1,'{"description":"Package unit 10TR","quantity":"4","unit":"Nos"}','10000000-0000-4000-8000-000000000001'),
('39fa1000-0000-4000-8000-000000000022','39fa1000-0000-4000-8000-000000000011',2,'{"description":"Package unit 5TR","quantity":"2","unit":"nos"}','10000000-0000-4000-8000-000000000001'),
('39fa1000-0000-4000-8000-000000000023','39fa1000-0000-4000-8000-000000000012',1,'{"description":"GI duct 0.8mm","quantity":"100","unit":"m2"}','10000000-0000-4000-8000-000000000001'),
('39fa1000-0000-4000-8000-000000000024','39fa1000-0000-4000-8000-000000000012',2,'{"description":"GI duct 1.0mm","quantity":"50","unit":"sqm"}','10000000-0000-4000-8000-000000000001');
insert into public.v1_material_requests(id,project_id,scope_id,created_by_auth_user_id) values
('39fa1000-0000-4000-8000-000000000031','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001');
insert into public.v1_material_request_lines(id,request_id,display_order,source_kind,source_boq_group_id,source_boq_row_id,item_description,requested_qty,unit,requested_item_description,requested_technical_attributes) values
('39fa1000-0000-4000-8000-000000000041','39fa1000-0000-4000-8000-000000000031',1,'boq','39fa1000-0000-4000-8000-000000000011','39fa1000-0000-4000-8000-000000000021','Package unit 10TR',4,'Nos','Package unit 10TR','{}'),
('39fa1000-0000-4000-8000-000000000042','39fa1000-0000-4000-8000-000000000031',2,'boq','39fa1000-0000-4000-8000-000000000011','39fa1000-0000-4000-8000-000000000022','Package unit 5TR',2,'Nos','Package unit 5TR','{}'),
('39fa1000-0000-4000-8000-000000000043','39fa1000-0000-4000-8000-000000000031',3,'boq','39fa1000-0000-4000-8000-000000000012','39fa1000-0000-4000-8000-000000000023','GI duct 0.8mm',100,'m2','GI duct 0.8mm','{}'),
('39fa1000-0000-4000-8000-000000000044','39fa1000-0000-4000-8000-000000000031',4,'boq','39fa1000-0000-4000-8000-000000000012','39fa1000-0000-4000-8000-000000000024','GI duct 1.0mm',50,'sqm','GI duct 1.0mm','{}');
insert into public.v1_material_dispatches(id,request_id,project_id,dispatch_number,dispatch_date,dispatched_by_auth_user_id,dispatched_by_role,delivery_reference) values
('39fa1000-0000-4000-8000-000000000051','39fa1000-0000-4000-8000-000000000031','39fa1000-0000-4000-8000-000000000001','DSP-1',date '2026-10-01','10000000-0000-4000-8000-000000000003','procurement','DO-001'),
('39fa1000-0000-4000-8000-000000000052','39fa1000-0000-4000-8000-000000000031','39fa1000-0000-4000-8000-000000000001','DSP-2',date '2026-10-05','10000000-0000-4000-8000-000000000003','procurement','DO-002');
insert into public.v1_material_dispatch_lines(id,dispatch_id,request_line_id,arrangement_line_id,source_kind,external_supplier,item_description,unit,approved_qty_snapshot,dispatched_qty) values
('39fa1000-0000-4000-8000-000000000061','39fa1000-0000-4000-8000-000000000051','39fa1000-0000-4000-8000-000000000041',gen_random_uuid(),'external_supplier','Supplier','Package unit 10TR','Nos',3,3),
('39fa1000-0000-4000-8000-000000000062','39fa1000-0000-4000-8000-000000000051','39fa1000-0000-4000-8000-000000000043',gen_random_uuid(),'external_supplier','Supplier','GI duct 0.8mm','m2',50,50),
('39fa1000-0000-4000-8000-000000000063','39fa1000-0000-4000-8000-000000000052','39fa1000-0000-4000-8000-000000000042',gen_random_uuid(),'external_supplier','Supplier','Package unit 5TR','Nos',2,2),
('39fa1000-0000-4000-8000-000000000064','39fa1000-0000-4000-8000-000000000051','39fa1000-0000-4000-8000-000000000044',gen_random_uuid(),'external_supplier','Supplier','GI duct 1.0mm','sqm',25,25);
insert into public.v1_receipt_reviews(id,dispatch_id,request_id,reviewed_by_auth_user_id,reviewed_by_role) values
('39fa1000-0000-4000-8000-000000000071','39fa1000-0000-4000-8000-000000000051','39fa1000-0000-4000-8000-000000000031','10000000-0000-4000-8000-000000000001','project_engineer'),
('39fa1000-0000-4000-8000-000000000072','39fa1000-0000-4000-8000-000000000052','39fa1000-0000-4000-8000-000000000031','10000000-0000-4000-8000-000000000001','project_engineer');
insert into public.v1_receipt_review_lines(id,receipt_review_id,dispatch_line_id,outcome,dispatched_qty_snapshot,good_qty,exception_qty) values
('39fa1000-0000-4000-8000-000000000081','39fa1000-0000-4000-8000-000000000071','39fa1000-0000-4000-8000-000000000061','received',3,3,0),
('39fa1000-0000-4000-8000-000000000082','39fa1000-0000-4000-8000-000000000071','39fa1000-0000-4000-8000-000000000062','received',50,50,0),
('39fa1000-0000-4000-8000-000000000083','39fa1000-0000-4000-8000-000000000072','39fa1000-0000-4000-8000-000000000063','received',2,2,0),
('39fa1000-0000-4000-8000-000000000084','39fa1000-0000-4000-8000-000000000071','39fa1000-0000-4000-8000-000000000064','received',25,25,0);
-- One 10TR unit went back, confirmed; a second return was only drafted.
insert into public.v1_material_returns(id,project_id,scope_id,state,drafted_by_auth_user_id,drafted_by_role) values
('39fa1000-0000-4000-8000-000000000091','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002','confirmed','10000000-0000-4000-8000-000000000001','project_engineer'),
('39fa1000-0000-4000-8000-000000000092','39fa1000-0000-4000-8000-000000000001','39fa1000-0000-4000-8000-000000000002','draft','10000000-0000-4000-8000-000000000001','project_engineer');
insert into public.v1_material_return_lines(id,material_return_id,receipt_review_line_id,dispatch_line_id,request_line_id,source_kind,item_description,unit,good_quantity_snapshot,eligible_quantity_at_submit,return_quantity,received_good_quantity,display_order,origin_kind) values
('39fa1000-0000-4000-8000-0000000000a1','39fa1000-0000-4000-8000-000000000091','39fa1000-0000-4000-8000-000000000081','39fa1000-0000-4000-8000-000000000061','39fa1000-0000-4000-8000-000000000041','external_supplier','Package unit 10TR','Nos',3,3,1,1,1,'delivered'),
('39fa1000-0000-4000-8000-0000000000a2','39fa1000-0000-4000-8000-000000000092','39fa1000-0000-4000-8000-000000000081','39fa1000-0000-4000-8000-000000000061','39fa1000-0000-4000-8000-000000000041','external_supplier','Package unit 10TR','Nos',3,2,2,2,1,'delivered');
set local session_replication_role = origin;

create function pg_temp.link(p_scope text, p_item text, p_group text) returns jsonb language sql as $$
  select jsonb_build_object('project_scope_id','39fa1000-0000-4000-8000-0000000000'||p_scope,
    'stage_key','material_supply','item_key',p_item,'boq_group_id','39fa1000-0000-4000-8000-0000000000'||p_group);
$$;
create function pg_temp.save(p_links jsonb, p_reason text default 'Link BOQ') returns jsonb language sql as $$
  select public.v1_save_accounts_material_boq_links('39fa1000-0000-4000-8000-000000000001',p_links,p_reason,pg_temp.key());
$$;
create function pg_temp.sources() returns jsonb language sql as $$
  select public.v1_get_accounts_material_sources('39fa1000-0000-4000-8000-000000000001');
$$;
create function pg_temp.delivered(p_scope text, p_item text) returns jsonb language sql as $$
  select d from jsonb_array_elements(pg_temp.sources()->'delivered') d
  where d->>'project_scope_id' = '39fa1000-0000-4000-8000-0000000000'||p_scope and d->>'item_key' = p_item;
$$;

-- ═══ Who may link ═══════════════════════════════════════════════════════════
select pg_temp.act('se');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11')))$$,'42501',null,'A Site Engineer cannot link');
select pg_temp.act('procurement');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11')))$$,'42501',null,'Procurement cannot link');
select pg_temp.act('pe');
select lives_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11'),pg_temp.link('02','duct','12'),pg_temp.link('03','ac','15')))$$,'The Project Engineer links items to folders');
select is((select count(*)::integer from public.v1_accounts_material_boq_links where project_id='39fa1000-0000-4000-8000-000000000001'),3,'Three links are stored');
select pg_temp.act('accountant');
select lives_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11'),pg_temp.link('02','duct','12'),pg_temp.link('03','ac','15')))$$,'An Accountant who edits contracts can link too');

-- ═══ Which folders ══════════════════════════════════════════════════════════
select pg_temp.act('pe');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','13')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','Workshop Materials cannot be linked');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('04','ac','14')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A Common folder cannot be linked');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','14')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A building cannot link a Common folder');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','15')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A building cannot link another building''s folder');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','16')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','An archived folder cannot be linked');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11')),' ')$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Linking needs a reason');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','ac','11'),pg_temp.link('02','duct','11')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A folder cannot stand for two items');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.link('02','pipes','12')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','An item the contract does not have cannot be linked');
select throws_ok($$select pg_temp.save(jsonb_build_array(jsonb_build_object('project_scope_id','x','stage_key','material_supply','item_key','ac','boq_group_id','y')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A malformed link is refused');
select is((select count(*)::integer from public.v1_accounts_material_boq_links where project_id='39fa1000-0000-4000-8000-000000000001'),3,'A refused save leaves the links as they were');

select is((select jsonb_agg(f->>'name' order by f->>'name') from jsonb_array_elements(pg_temp.sources()->'folders') f
  where f->>'project_scope_id'='39fa1000-0000-4000-8000-000000000002'),'["AC Units", "GI Ductwork"]'::jsonb,
  'A building offers its own folders, without Workshop Materials or archived ones');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.sources()->'folders') f
  where f->>'project_scope_id'='39fa1000-0000-4000-8000-000000000004'),0,'Common offers no folders');
select is((select f->>'quantity' from jsonb_array_elements(pg_temp.sources()->'folders') f
  where f->>'boq_group_id'='39fa1000-0000-4000-8000-000000000011'),'6','A folder in one unit totals its quantity');
select is((select (select array_agg(k order by k) from jsonb_object_keys(f) k) from jsonb_array_elements(pg_temp.sources()->'folders') f limit 1),
  array['boq_group_id','name','project_scope_id','quantity','row_count','template_key','unit'],'A folder carries nothing commercial');

-- ═══ What was delivered ═════════════════════════════════════════════════════
select is(pg_temp.delivered('02','ac')->>'delivered_qty','4.0000','AC units: 3 + 2 received, less the 1 confirmed returned');
select is(pg_temp.delivered('02','ac')->>'basis','quantity','Units that agree add up');
select is(pg_temp.delivered('02','ac')->>'last_delivery_reference','DO-002','The latest delivery is named');
select is((pg_temp.delivered('02','ac')->>'deliveries')::integer,2,'Two deliveries brought them');
select is(pg_temp.delivered('02','duct')->>'delivered_qty','0.5000','Ducting in m2 against a 1 Lot item: 75 of 150 m2 is half of it');
select is((pg_temp.delivered('02','duct')->>'deliveries')::integer,1,'One delivery that brought two rows counts once');
select is(pg_temp.delivered('02','duct')->>'basis','share','Units that differ give a share');
select is(pg_temp.delivered('03','ac'),null,'Nothing delivered to Building 2 shows nothing');
select pg_temp.act('se');
select is(pg_temp.delivered('02','ac')->>'delivered_qty','4.0000','A Site Engineer sees the deliveries too');
select ok(not (pg_temp.sources()->>'can_link')::boolean,'A Site Engineer is told they cannot link');
select pg_temp.act('procurement');
select throws_ok($$select pg_temp.sources()$$,'42501',null,'Procurement cannot read Accounts');

-- ═══ Replays, revisions, audit, grants ══════════════════════════════════════
select pg_temp.act('pe');
select is((public.v1_save_accounts_material_boq_links('39fa1000-0000-4000-8000-000000000001',
  jsonb_build_array(pg_temp.link('02','ac','11')),'Retry','39fa0000-0000-4000-8000-00000000ffff')->>'link_count')::integer,1,'A save replaces the links');
select ok((public.v1_save_accounts_material_boq_links('39fa1000-0000-4000-8000-000000000001',
  jsonb_build_array(pg_temp.link('02','ac','11')),'Retry','39fa0000-0000-4000-8000-00000000ffff')->>'replayed')::boolean,'The same save again is a replay');
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39fa1000-0000-4000-8000-000000000001',
  (select max(revision_number) from public.v1_accounts_baseline_revisions where project_id='39fa1000-0000-4000-8000-000000000001'),
  pg_temp.setup() || jsonb_build_object('contract_value','1200000.00'),'Revised',pg_temp.key())$$,'The contract is revised');
select is(pg_temp.delivered('02','ac')->>'delivered_qty','4.0000','Links and deliveries carry across a contract revision');
select ok(exists(select 1 from public.v1_audit_events where event_type='accounts.material_links.saved'
  and project_id='39fa1000-0000-4000-8000-000000000001'),'Linking is audited');
select ok(not has_table_privilege('authenticated','public.v1_accounts_material_boq_links','select'),'The link table is not readable directly');
select ok(not has_function_privilege('authenticated','public.v1_accounts_boq_number(text)','execute'),'The number helper is internal');
select ok(not has_function_privilege('anon','public.v1_get_accounts_material_sources(uuid)','execute'),'Anonymous users cannot read deliveries');

select finish();
rollback;

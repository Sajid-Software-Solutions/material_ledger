-- Contract materials (PRODUCT_DECISIONS.md section 61)
--
-- BOQ rows tied to contract lines; Accounts › Materials and the BOQ line
-- status, read by every role: who sees quantities, who sees prices, and that
-- nobody else gets a money field at all. What reached site counts once, by a
-- tied row or by a linked folder, never both.

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
    ('sme','10000000-0000-4000-8000-000000000009','senior_mechanical_engineer'),
    ('pm','10000000-0000-4000-8000-000000000010','project_manager'),
    ('accountant','10000000-0000-4000-8000-000000000013','accountant'),
    ('pr','10000000-0000-4000-8000-000000000014','pr')
  ) as actor(who, id, role) where who = p_who;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_id, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', v_role, 'app_user_id', 'usr-local-' || p_who)
  )::text, true);
end;
$$;

create sequence pg_temp.key_seq;
create function pg_temp.key() returns uuid language sql as $$
  select ('3a0c0000-0000-4000-8000-' || lpad(nextval('pg_temp.key_seq')::text, 12, '0'))::uuid;
$$;
create function pg_temp.id(p_suffix text) returns uuid language sql as $$
  select ('3a0c1000-0000-4000-8000-0000000000' || p_suffix)::uuid;
$$;

-- Project ...01 (B1 ...02, B2 ...03, Common ...04) with a Project Engineer and
-- a Site Engineer as members; project ...11 has nobody on it.
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role) values
(pg_temp.id('01'),'CM-001','Contract materials','active','project_engineer','10000000-0000-4000-8000-000000000004','admin'),
(pg_temp.id('11'),'CM-002','Nobody on it','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable) values
(pg_temp.id('02'),pg_temp.id('01'),'building','a-b1','Building 1',false),
(pg_temp.id('03'),pg_temp.id('01'),'building','b-b2','Building 2',false),
(pg_temp.id('04'),pg_temp.id('01'),'common','common','Common / All Buildings',true);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role) values
(pg_temp.id('01'),'10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
(pg_temp.id('01'),'10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role) values
(pg_temp.id('21'),'operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role) values
(pg_temp.id('22'),pg_temp.id('21'),1,'cm/delivery-note.pdf','Delivery note.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id=pg_temp.id('22') where id=pg_temp.id('21');
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role) values
(pg_temp.id('23'),pg_temp.id('21'),pg_temp.id('01'),'project',pg_temp.id('01'),'10000000-0000-4000-8000-000000000004','admin');

-- AED 1,000,000; two 50% buildings; Design 10% by percent; Material Supply
-- 60% and Installation 30% by the same two lines in each building.
create function pg_temp.setup(p_value text) returns jsonb language sql as $$
  select jsonb_build_object('contract_value',p_value,'currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id',pg_temp.id('02'),'allocation_percent','50'),
      jsonb_build_object('building_scope_id',pg_temp.id('03'),'allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','60','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','1','item_label','AC Units (Package Unit)','display_order',1,'quantity','6','unit_code','Nos','weight_percent_of_contract','20'),
          jsonb_build_object('item_key','10-1','item_label','Ducting — Basement Floor','display_order',2,'quantity','1','unit_code','Lot','weight_percent_of_contract','10'))),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','1','item_label','AC Units (Package Unit)','display_order',1,'quantity','6','unit_code','Nos','weight_percent_of_contract','10'),
          jsonb_build_object('item_key','10-1','item_label','Ducting — Basement Floor','display_order',2,'quantity','1','unit_code','Lot','weight_percent_of_contract','5')))));
$$;
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup(pg_temp.id('01'),null,pg_temp.setup('1000000.00'),'Contract',pg_temp.key())$$,'The contract is set up');
select lives_ok($$select public.v1_save_project_invoice_settings(pg_temp.id('01'),'CM',null,null,null,null,pg_temp.key())$$,'Invoice settings are set');

-- BOQ and deliveries, entered directly: this file tests the reading of them,
-- not the Material Request workflow that normally creates them.
reset role;
set local session_replication_role = replica;
delete from public.v1_boq_groups where project_id = pg_temp.id('01');
insert into public.v1_boq_groups(id,project_id,scope_id,template_id,name,display_order,worksheet_title,created_by_auth_user_id,is_archived,archived_at,archived_by_auth_user_id,is_custom) values
(pg_temp.id('31'),pg_temp.id('01'),pg_temp.id('02'),null,'Contract Materials',1,'Contract Materials','10000000-0000-4000-8000-000000000001',false,null,null,true),
(pg_temp.id('32'),pg_temp.id('01'),pg_temp.id('02'),null,'VCD',2,'VCD','10000000-0000-4000-8000-000000000001',false,null,null,true),
(pg_temp.id('33'),pg_temp.id('01'),pg_temp.id('02'),(select id from public.v1_boq_group_templates where template_key='workshop_materials'),'Workshop Materials',3,'Workshop Materials','10000000-0000-4000-8000-000000000001',false,null,null,false),
(pg_temp.id('34'),pg_temp.id('01'),pg_temp.id('03'),null,'Contract Materials',1,'Contract Materials','10000000-0000-4000-8000-000000000001',false,null,null,true),
(pg_temp.id('35'),pg_temp.id('01'),pg_temp.id('04'),null,'Contract Materials',1,'Contract Materials','10000000-0000-4000-8000-000000000001',false,null,null,true),
(pg_temp.id('36'),pg_temp.id('01'),pg_temp.id('02'),null,'Old sheet',4,'Old sheet','10000000-0000-4000-8000-000000000001',true,clock_timestamp(),'10000000-0000-4000-8000-000000000001',true);
insert into public.v1_boq_rows(id,group_id,display_order,canonical_values,created_by_auth_user_id,is_archived,archived_at,archived_by_auth_user_id) values
(pg_temp.id('41'),pg_temp.id('31'),1,'{"description":"AC Units (Package Unit)","quantity":"6","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('42'),pg_temp.id('31'),2,'{"description":"Ducting — Basement Floor","quantity":"1","unit":"Lot"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('43'),pg_temp.id('32'),1,'{"description":"VCD 300 x 300","quantity":"10","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('44'),pg_temp.id('33'),1,'{"description":"Rivets","quantity":"100","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('45'),pg_temp.id('34'),1,'{"description":"AC Units (Package Unit)","quantity":"6","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('46'),pg_temp.id('35'),1,'{"description":"AC Units","quantity":"6","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('47'),pg_temp.id('31'),3,'{"description":"Old line","quantity":"1","unit":"Nos"}','10000000-0000-4000-8000-000000000001',true,clock_timestamp(),'10000000-0000-4000-8000-000000000001'),
(pg_temp.id('48'),pg_temp.id('36'),1,'{"description":"In an archived sheet","quantity":"1","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null),
(pg_temp.id('49'),pg_temp.id('31'),4,'{"description":"Spare","quantity":"2","unit":"Nos"}','10000000-0000-4000-8000-000000000001',false,null,null);

-- Requests from the tied AC row: one submitted (4), one draft (2), one
-- cancelled (1). A VCD request (10) from the VCD folder.
insert into public.v1_material_requests(id,project_id,scope_id,created_by_auth_user_id,state,request_number,submitted_at,cancelled_at,cancelled_by_auth_user_id,cancellation_reason) values
(pg_temp.id('51'),pg_temp.id('01'),pg_temp.id('02'),'10000000-0000-4000-8000-000000000001','dispatched','CM-MR001',clock_timestamp(),null,null,null),
(pg_temp.id('52'),pg_temp.id('01'),pg_temp.id('02'),'10000000-0000-4000-8000-000000000001','draft',null,null,null,null,null),
(pg_temp.id('53'),pg_temp.id('01'),pg_temp.id('02'),'10000000-0000-4000-8000-000000000001','cancelled','CM-MR003',clock_timestamp(),clock_timestamp(),'10000000-0000-4000-8000-000000000001','Not needed');
insert into public.v1_material_request_lines(id,request_id,display_order,source_kind,source_boq_group_id,source_boq_row_id,item_description,requested_qty,unit,requested_item_description,requested_technical_attributes) values
(pg_temp.id('61'),pg_temp.id('51'),1,'boq',pg_temp.id('31'),pg_temp.id('41'),'AC Units (Package Unit)',4,'Nos','AC Units (Package Unit)','{}'),
(pg_temp.id('62'),pg_temp.id('51'),2,'boq',pg_temp.id('32'),pg_temp.id('43'),'VCD 300 x 300',10,'Nos','VCD 300 x 300','{}'),
(pg_temp.id('63'),pg_temp.id('52'),1,'boq',pg_temp.id('31'),pg_temp.id('41'),'AC Units (Package Unit)',2,'Nos','AC Units (Package Unit)','{}'),
(pg_temp.id('64'),pg_temp.id('53'),1,'boq',pg_temp.id('31'),pg_temp.id('41'),'AC Units (Package Unit)',1,'Nos','AC Units (Package Unit)','{}');
-- DO-101 brought 3 AC units and 5 VCDs (one damaged); DO-102 brought one more
-- AC unit that site has not reviewed yet.
insert into public.v1_material_dispatches(id,request_id,project_id,dispatch_number,dispatch_date,dispatched_by_auth_user_id,dispatched_by_role,delivery_reference) values
(pg_temp.id('71'),pg_temp.id('51'),pg_temp.id('01'),'CM-DSP-1',date '2026-10-01','10000000-0000-4000-8000-000000000003','procurement','DO-101'),
(pg_temp.id('72'),pg_temp.id('51'),pg_temp.id('01'),'CM-DSP-2',date '2026-10-03','10000000-0000-4000-8000-000000000003','procurement','DO-102');
insert into public.v1_material_dispatch_lines(id,dispatch_id,request_line_id,arrangement_line_id,source_kind,external_supplier,item_description,unit,approved_qty_snapshot,dispatched_qty) values
(pg_temp.id('81'),pg_temp.id('71'),pg_temp.id('61'),gen_random_uuid(),'external_supplier','Supplier','AC Units (Package Unit)','Nos',3,3),
(pg_temp.id('82'),pg_temp.id('71'),pg_temp.id('62'),gen_random_uuid(),'external_supplier','Supplier','VCD 300 x 300','Nos',5,5),
(pg_temp.id('83'),pg_temp.id('72'),pg_temp.id('61'),gen_random_uuid(),'external_supplier','Supplier','AC Units (Package Unit)','Nos',1,1);
insert into public.v1_receipt_reviews(id,dispatch_id,request_id,reviewed_by_auth_user_id,reviewed_by_role) values
(pg_temp.id('91'),pg_temp.id('71'),pg_temp.id('51'),'10000000-0000-4000-8000-000000000001','project_engineer');
insert into public.v1_receipt_review_lines(id,receipt_review_id,dispatch_line_id,outcome,dispatched_qty_snapshot,good_qty,damaged_qty,exception_qty,note) values
(pg_temp.id('a1'),pg_temp.id('91'),pg_temp.id('81'),'received',3,3,0,0,null),
(pg_temp.id('a2'),pg_temp.id('91'),pg_temp.id('82'),'damaged',5,4,1,1,'One VCD bent');
-- One AC unit went back, confirmed by Procurement.
insert into public.v1_material_returns(id,project_id,scope_id,state,drafted_by_auth_user_id,drafted_by_role) values
(pg_temp.id('b1'),pg_temp.id('01'),pg_temp.id('02'),'confirmed','10000000-0000-4000-8000-000000000001','project_engineer');
insert into public.v1_material_return_lines(id,material_return_id,receipt_review_line_id,dispatch_line_id,request_line_id,source_kind,item_description,unit,good_quantity_snapshot,eligible_quantity_at_submit,return_quantity,received_good_quantity,display_order,origin_kind,basis_kind) values
(pg_temp.id('c1'),pg_temp.id('b1'),pg_temp.id('a1'),pg_temp.id('81'),pg_temp.id('61'),'external_supplier','AC Units (Package Unit)','Nos',3,3,1,1,1,'delivered','received');
set local session_replication_role = origin;

create function pg_temp.tie(p_scope text, p_item text, p_row text) returns jsonb language sql as $$
  select jsonb_build_object('project_scope_id',pg_temp.id(p_scope),'item_key',p_item,'boq_row_id',pg_temp.id(p_row));
$$;
create function pg_temp.save_ties(p_ties jsonb, p_reason text default 'Contract Materials sheet') returns jsonb language sql as $$
  select public.v1_save_accounts_material_row_links(pg_temp.id('01'),p_ties,p_reason,pg_temp.key());
$$;
create function pg_temp.the_ties() returns jsonb language sql as $$
  select jsonb_build_array(pg_temp.tie('02','1','41'),pg_temp.tie('02','10-1','42'),pg_temp.tie('03','1','45'));
$$;
create function pg_temp.ties_count() returns integer language sql as $$
  select count(*)::integer from public.v1_accounts_material_boq_row_links where project_id = pg_temp.id('01');
$$;
create function pg_temp.folder_link(p_scope text, p_item text, p_group text) returns jsonb language sql as $$
  select jsonb_build_object('project_scope_id',pg_temp.id(p_scope),'stage_key','material_supply','item_key',p_item,'boq_group_id',pg_temp.id(p_group));
$$;

-- ═══ Who may tie rows ═══════════════════════════════════════════════════════
select pg_temp.act('se');
select throws_ok($$select pg_temp.save_ties(pg_temp.the_ties())$$,'42501',null,'A Site Engineer cannot tie rows');
select pg_temp.act('procurement');
select throws_ok($$select pg_temp.save_ties(pg_temp.the_ties())$$,'42501',null,'Procurement cannot tie rows');
select pg_temp.act('pr');
select throws_ok($$select pg_temp.save_ties(pg_temp.the_ties())$$,'42501',null,'HR/PRO cannot tie rows');
select pg_temp.act('pe');
select throws_ok($$select public.v1_save_accounts_material_row_links(pg_temp.id('11'),'[]'::jsonb,'x',pg_temp.key())$$,'42501',null,
  'A Project Engineer cannot tie rows on a project they are not on');

-- The VCD folder stands for the ducting line as a whole (decision 5's shape).
select lives_ok($$select public.v1_save_accounts_material_boq_links(pg_temp.id('01'),jsonb_build_array(pg_temp.folder_link('02','10-1','32')),'VCD folder',pg_temp.key())$$,
  'The VCD folder is linked to the ducting line');
select lives_ok($$select pg_temp.save_ties(pg_temp.the_ties())$$,'The Project Engineer ties the Contract Materials rows');
select is(pg_temp.ties_count(),3,'Three ties are stored');
select pg_temp.act('accountant');
select lives_ok($$select pg_temp.save_ties(pg_temp.the_ties())$$,'An Accountant who edits contracts can tie rows too');

-- ═══ Which rows ═════════════════════════════════════════════════════════════
select pg_temp.act('pe');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','44')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A Workshop Materials row cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('04','1','46')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A Common row cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','45')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A building cannot tie another building''s row');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','47')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','An archived row cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','48')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A row of an archived sheet cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','pipes','41')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A line the contract does not have cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','43')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A row of a folder linked as a whole cannot be tied');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','41'),pg_temp.tie('02','10-1','41')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A row stands for one line');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(pg_temp.tie('02','1','41'),pg_temp.tie('02','1','49')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A line has one row in a building');
select throws_ok($$select pg_temp.save_ties(jsonb_build_array(jsonb_build_object('project_scope_id','x','item_key','1','boq_row_id','y')))$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A malformed tie is refused');
select throws_ok($$select pg_temp.save_ties(pg_temp.the_ties(),' ')$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Tying needs a reason');
select throws_ok($$select public.v1_save_accounts_material_row_links(pg_temp.id('01'),'{}'::jsonb,'x',pg_temp.key())$$,'22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','The ties must be a list');
select is(pg_temp.ties_count(),3,'A refused save leaves the ties as they were');
select throws_ok($$select public.v1_save_accounts_material_boq_links(pg_temp.id('01'),jsonb_build_array(pg_temp.folder_link('02','1','31')),'Whole sheet',pg_temp.key())$$,
  '22023','R39_ACCOUNTS_INVALID_MATERIAL_LINK','A folder holding a tied row cannot be linked as a whole');

-- ═══ Progress, a claim and an invoice ═══════════════════════════════════════
create function pg_temp.items(p_entries jsonb) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('stage_item_id', si.id, 'confirmed_qty_to_date', e ->> 'qty'))
  from jsonb_array_elements(p_entries) e
  join public.v1_accounts_baseline_stage_items si
    on si.project_scope_id = pg_temp.id(e ->> 'scope') and si.stage_key = e ->> 'stage' and si.item_key = e ->> 'item'
  join public.v1_accounts_project_commercial_profiles cp on cp.current_baseline_revision_id = si.baseline_revision_id;
$$;
create function pg_temp.claim(p_ref text) returns uuid language sql as $$
  select id from public.v1_accounts_client_claims where project_id = pg_temp.id('01') and claim_reference = p_ref;
$$;
select lives_ok($$select public.v1_save_claim_workbench(pg_temp.id('01'),'CLM-01',date '2026-10-01',date '2026-10-05',
  pg_temp.items('[{"scope":"02","stage":"material_supply","item":"1","qty":"2"},{"scope":"02","stage":"installation","item":"1","qty":"1"}]'),
  array[pg_temp.id('21')],'Two AC units delivered, one installed',pg_temp.key())$$,'The Project Engineer confirms and claims');
select lives_ok($$select public.v1_submit_client_claim_to_accounts(pg_temp.id('01'),pg_temp.claim('CLM-01'),1,'Checked',pg_temp.key())$$,'The claim is checked');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice(pg_temp.id('01'),pg_temp.claim('CLM-01'),2,'CM01',date '2026-10-06',date '2026-10-06',pg_temp.key())$$,'Invoice CM01 is issued');
select pg_temp.act('pe');
select lives_ok($$select public.v1_save_claim_workbench(pg_temp.id('01'),'CLM-02',date '2026-10-06',date '2026-10-20',
  pg_temp.items('[{"scope":"02","stage":"material_supply","item":"1","qty":"6"}]'),
  array[pg_temp.id('21')],'All six delivered',pg_temp.key())$$,'All six are confirmed and a second claim is drafted');

-- ═══ Accounts › Materials, with prices ══════════════════════════════════════
create function pg_temp.register() returns jsonb language sql as $$
  select public.v1_get_accounts_material_register(pg_temp.id('01'));
$$;
create function pg_temp.building(p_reg jsonb, p_scope text) returns jsonb language sql as $$
  select b from jsonb_array_elements(p_reg -> 'buildings') b where b ->> 'project_scope_id' = pg_temp.id(p_scope)::text;
$$;
create function pg_temp.line(p_reg jsonb, p_scope text, p_item text) returns jsonb language sql as $$
  select l from jsonb_array_elements(pg_temp.building(p_reg, p_scope) -> 'lines') l where l ->> 'item_key' = p_item;
$$;
create function pg_temp.line_stage(p_line jsonb, p_stage text) returns jsonb language sql as $$
  select s from jsonb_array_elements(p_line -> 'stages') s where s ->> 'stage_key' = p_stage;
$$;
create function pg_temp.cell(p_reg jsonb, p_scope text, p_stage text) returns jsonb language sql as $$
  select s from jsonb_array_elements(pg_temp.building(p_reg, p_scope) -> 'stages') s where s ->> 'stage_key' = p_stage;
$$;

create temporary table reg_pe as select pg_temp.register() as r;
select is((select r -> 'stages' from reg_pe),
  '[{"stage_key": "material_supply", "stage_label": "Material Supply", "display_order": 2}, {"stage_key": "installation", "stage_label": "Installation", "display_order": 3}]'::jsonb,
  'The register offers the item-measured stages, in contract order');
select is((select jsonb_agg(b ->> 'scope_code') from reg_pe, jsonb_array_elements(r -> 'buildings') b),'["a-b1", "b-b2"]'::jsonb,
  'Physical buildings only, in building order; Common has no contract lines');
select is((select jsonb_agg(l ->> 'item_key') from reg_pe, jsonb_array_elements(pg_temp.building(r,'02') -> 'lines') l),'["1", "10-1"]'::jsonb,
  'A building''s lines in contract order');
select is((select r ->> 'contract_value' from reg_pe),'1000000.00','The contract value is shown to those who may see it');
select is((select pg_temp.line_stage(pg_temp.line(r,'02','1'),'material_supply') - 'stage_item_id' - 'last_invoice' from reg_pe),
  jsonb_build_object('stage_key','material_supply','quantity','6.0000','unit_code','Nos','confirmed_qty','6.0000','needs_review',false,
    'weight_percent','20.000000','amount','200000.00','rate','33333.33','done_amount','200000.00','invoiced_qty','2.0000'),
  'B1 AC units, supply: 6 of 6 delivered, 2 invoiced, AED 200,000.00 at 33,333.33 each');
select is((select pg_temp.line_stage(pg_temp.line(r,'02','1'),'material_supply') -> 'last_invoice' ->> 'invoice_reference' from reg_pe),'CM01',
  'The line names the invoice that last billed it');
select is((select pg_temp.line_stage(pg_temp.line(r,'02','1'),'installation') ->> 'done_amount' from reg_pe),'16666.67',
  'B1 AC units, installation: 1 of 6 installed is AED 16,666.67');
select is((select pg_temp.line_stage(pg_temp.line(r,'03','1'),'material_supply') ->> 'invoiced_qty' from reg_pe),'0',
  'A line nothing was invoiced on shows zero invoiced');
select is((select pg_temp.line_stage(pg_temp.line(r,'03','1'),'material_supply') -> 'last_invoice' from reg_pe),'null'::jsonb,
  'and no invoice');
select is((select pg_temp.cell(r,'02','material_supply') - 'stage_key' - 'stage_label' - 'display_order' from reg_pe),
  jsonb_build_object('stage_value','300000.00','done_amount','200000.00','invoiced_amount','66666.67','in_claim_amount','133333.33',
    'not_invoiced_amount','133333.33','over_invoiced',false),
  'B1 supply in money: done, invoiced, in the open claim and not yet invoiced');
select is((select pg_temp.line(r,'02','1') ->> 'boq_row_id' from reg_pe),pg_temp.id('41')::text,'The line names its tied BOQ row');
select is((select (pg_temp.line(r,'02','1') -> 'site') - 'last_delivery_date' from reg_pe),
  '{"basis": "quantity", "deliveries": 1, "delivered_qty": "2.0000", "last_delivery_reference": "DO-101"}'::jsonb,
  'On site: 3 received less 1 returned; the unreviewed delivery does not count');
select is((select pg_temp.line(r,'02','10-1') -> 'site' ->> 'delivered_qty' from reg_pe),'0.2000',
  'Ducting: the tied row and the VCD folder count together as a share, once each');
select is((select pg_temp.line(r,'02','10-1') -> 'site' ->> 'basis' from reg_pe),'share','Mixed units give a share');
select is((select pg_temp.line(r,'03','10-1') ->> 'boq_row_id' from reg_pe),null,'An untied line has no row');

-- ═══ The same register for each role ═══════════════════════════════════════
create function pg_temp.money_keys(p_reg jsonb) returns text[] language sql as $$
  select array(select distinct k from (
    select jsonb_object_keys(p_reg) k
    union all select jsonb_object_keys(b) from jsonb_array_elements(p_reg -> 'buildings') b
    union all select jsonb_object_keys(s) from jsonb_array_elements(p_reg -> 'buildings') b, jsonb_array_elements(b -> 'stages') s
    union all select jsonb_object_keys(st) from jsonb_array_elements(p_reg -> 'buildings') b, jsonb_array_elements(b -> 'lines') l, jsonb_array_elements(l -> 'stages') st
  ) keys where k in ('contract_value','currency_code','stage_value','done_amount','invoiced_amount','in_claim_amount',
    'not_invoiced_amount','over_invoiced','weight_percent','amount','rate','invoiced_qty','last_invoice') order by 1);
$$;
select pg_temp.act('se');
create temporary table reg_se as select pg_temp.register() as r;
select is((select pg_temp.money_keys(r) from reg_se),'{}'::text[],'A Site Engineer gets no money, weight or invoice field at all');
select is((select pg_temp.line_stage(pg_temp.line(r,'02','1'),'material_supply') ->> 'confirmed_qty' from reg_se),'6.0000','A Site Engineer sees what is delivered');
select is((select pg_temp.line(r,'02','1') -> 'site' ->> 'delivered_qty' from reg_se),'2.0000','and what reached site');
select ok(not (select (r ->> 'can_view_values')::boolean from reg_se),'A Site Engineer is told prices are not shown');
select pg_temp.act('procurement');
select throws_ok($$select pg_temp.register()$$,'42501',null,'Procurement cannot read the register');
select pg_temp.act('pe');
select throws_ok($$select public.v1_get_accounts_material_register(pg_temp.id('11'))$$,'42501',null,'A Project Engineer cannot read a project they are not on');
select pg_temp.act('accountant');
select is((select pg_temp.line_stage(pg_temp.line(pg_temp.register(),'02','1'),'material_supply') ->> 'amount'),'200000.00','The Accountant sees prices');
select pg_temp.act('pm');
select is((select pg_temp.line_stage(pg_temp.line(pg_temp.register(),'02','1'),'material_supply') ->> 'amount'),'200000.00','A Project Manager sees prices without membership');
select pg_temp.act('sme');
select is((select pg_temp.line_stage(pg_temp.line(pg_temp.register(),'02','1'),'material_supply') ->> 'rate'),'33333.33','A Senior Mechanical Engineer sees prices');
select pg_temp.act('pr');
select is((select pg_temp.line_stage(pg_temp.line(pg_temp.register(),'02','1'),'material_supply') ->> 'amount'),'200000.00',
  'HR/PRO reads Accounts with values (section 37), so the register too');
select pg_temp.act('admin');
select is((select jsonb_array_length(pg_temp.register() -> 'buildings')),2,'Admin reads the register');

-- ═══ BOQ › Contract Materials status ════════════════════════════════════════
create function pg_temp.status(p_group text) returns jsonb language sql as $$
  select public.v1_get_boq_contract_status(pg_temp.id(p_group));
$$;
create function pg_temp.status_row(p_status jsonb, p_row text) returns jsonb language sql as $$
  select r from jsonb_array_elements(p_status -> 'rows') r where r ->> 'boq_row_id' = pg_temp.id(p_row)::text;
$$;
select pg_temp.act('pe');
create temporary table st_pe as select pg_temp.status('31') as s;
select is((select jsonb_agg(r ->> 'boq_row_id') from st_pe, jsonb_array_elements(s -> 'rows') r),
  jsonb_build_array(pg_temp.id('41')::text, pg_temp.id('42')::text),'Only the tied, live rows, in sheet order');
select is((select pg_temp.status_row(s,'41') - 'stages' - 'last_delivery_date' - 'boq_row_id' - 'project_scope_id' from st_pe),
  '{"item_key": "1", "deliveries": 1, "received_qty": "2.0000", "requested_qty": "4.0000", "last_delivery_reference": "DO-101"}'::jsonb,
  'Requested counts the submitted request only; received is good quantity less the return');
select is((select pg_temp.status_row(s,'41') -> 'stages' -> 0 from st_pe),
  '{"rate": "33333.33", "amount": "200000.00", "quantity": "6.0000", "stage_key": "material_supply", "unit_code": "Nos", "stage_label": "Material Supply", "confirmed_qty": "6.0000"}'::jsonb,
  'With values: the line''s delivery and its price');
select is((select pg_temp.status_row(s,'41') -> 'stages' -> 1 ->> 'confirmed_qty' from st_pe),'1.0000','and its installation');
select is((select s ->> 'currency_code' from st_pe),'AED','The currency comes with prices');
select is((select pg_temp.status_row(s,'42') ->> 'requested_qty' from st_pe),'0','A row nobody requested from shows zero');

select pg_temp.act('se');
create temporary table st_se as select pg_temp.status('31') as s;
select is((select pg_temp.status_row(s,'41') -> 'stages' -> 0 from st_se),
  '{"quantity": "6.0000", "stage_key": "material_supply", "unit_code": "Nos", "stage_label": "Material Supply", "confirmed_qty": "6.0000"}'::jsonb,
  'A Site Engineer sees delivery and installation without prices');
select ok(not (select s ? 'currency_code' from st_se),'and no currency');

select pg_temp.act('procurement');
create temporary table st_proc as select pg_temp.status('31') as s;
select is((select pg_temp.status_row(s,'41') ->> 'requested_qty' from st_proc),'4.0000','Procurement sees what was requested and received');
select ok(not (select pg_temp.status_row(s,'41') ? 'stages' from st_proc),'but nothing from Accounts');
select ok(not (select (s ->> 'can_view_progress')::boolean from st_proc),'and is told so');

select pg_temp.act('pr');
select ok((select pg_temp.status_row(pg_temp.status('31'),'41') -> 'stages' -> 0 ? 'amount'),'HR/PRO reads the prices it may read in Accounts');
select pg_temp.act('accountant');
select throws_ok($$select pg_temp.status('31')$$,'42501','V1_BOQ_GROUP_NOT_READABLE','The Accountant has no BOQ, so no status');
select pg_temp.act('pe');
select is((select jsonb_array_length(pg_temp.status('32') -> 'rows')),0,'A folder with no tied rows has no status rows');
select throws_ok($$select public.v1_get_boq_contract_status('3a0c1000-0000-4000-8000-0000000000ff')$$,'42501','V1_BOQ_GROUP_NOT_READABLE','An unknown folder is refused');

-- ═══ Site deliveries in the existing read ═══════════════════════════════════
create temporary table src as select public.v1_get_accounts_material_sources(pg_temp.id('01')) as s;
select is((select jsonb_agg(f ->> 'name' order by f ->> 'name') from src, jsonb_array_elements(s -> 'folders') f),'["VCD"]'::jsonb,
  'Sheets holding tied rows are not offered for a folder link');
select is((select jsonb_array_length(s -> 'row_links') from src),3,'The ties are listed');
select is((select d ->> 'delivered_qty' from src, jsonb_array_elements(s -> 'delivered') d
  where d ->> 'project_scope_id' = pg_temp.id('02')::text and d ->> 'item_key' = '1' and d ->> 'stage_key' = 'material_supply'),'2.0000',
  'The claim workbench sees AC units on site through the tied row');
select is((select count(*)::integer from src, jsonb_array_elements(s -> 'delivered') d where d ->> 'stage_key' = 'installation'),0,
  'A tie never says anything about installation');

-- ═══ Replays, revisions, audit, grants ══════════════════════════════════════
select is((public.v1_save_accounts_material_row_links(pg_temp.id('01'),pg_temp.the_ties(),'Retry','3a0c0000-0000-4000-8000-00000000ffff') ->> 'link_count')::integer,3,
  'A save replaces the ties');
select ok((public.v1_save_accounts_material_row_links(pg_temp.id('01'),pg_temp.the_ties(),'Retry','3a0c0000-0000-4000-8000-00000000ffff') ->> 'replayed')::boolean,
  'The same save again is a replay');
select ok(exists(select 1 from public.v1_audit_events where event_type = 'accounts.material_row_links.saved' and project_id = pg_temp.id('01')),'Tying is audited');
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup(pg_temp.id('01'),
  (select record_version from public.v1_accounts_project_commercial_profiles where project_id = pg_temp.id('01')),
  pg_temp.setup('1200000.00'),'Revised',pg_temp.key())$$,'The contract is revised');
select is(pg_temp.line(pg_temp.register(),'02','1') ->> 'boq_row_id',pg_temp.id('41')::text,'Ties carry across a contract revision');
select is(pg_temp.line_stage(pg_temp.line(pg_temp.register(),'02','1'),'material_supply') ->> 'amount','240000.00','and the price follows the new contract');
select ok(not has_table_privilege('authenticated','public.v1_accounts_material_boq_row_links','select'),'The tie table is not readable directly');
select ok(not has_function_privilege('authenticated','public.v1_accounts_contract_line_facts(uuid)','execute'),'The line helper is internal');
select ok(not has_function_privilege('authenticated','public.v1_accounts_material_delivered(uuid)','execute'),'The delivery helper is internal');
select ok(has_function_privilege('authenticated','public.v1_get_accounts_material_register(uuid)','execute'),'Signed-in people may call the register');
select ok(has_function_privilege('authenticated','public.v1_get_boq_contract_status(uuid)','execute'),'and the BOQ status');
select ok(not has_function_privilege('anon','public.v1_get_accounts_material_register(uuid)','execute'),'Anonymous users cannot read the register');
select ok(not has_function_privilege('anon','public.v1_get_boq_contract_status(uuid)','execute'),'or the BOQ status');
select ok(not has_function_privilege('anon','public.v1_save_accounts_material_row_links(uuid,jsonb,text,uuid)','execute'),'or tie rows');
select ok(not has_function_privilege('anon','public.v1_get_accounts_material_sources(uuid)','execute'),'or read deliveries');

select finish();
rollback;

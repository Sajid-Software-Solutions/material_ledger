-- R39 Accounts Workspace V2 — project engineer review of YRA-322, 9 Nov 2026.
--
-- 1. Claim rights: Admin and the organization-wide engineering roles (Senior
--    Mechanical Engineer, Project Manager, Workshop In-Charge, Document
--    Controller) may record progress and prepare a claim without project
--    membership. Site Engineer, Procurement and a Project Engineer who is not
--    on the project may not.
-- 2. The invoice's per-building item rows (the workbook's Material and
--    Installation sheets): quantity, % of contract and amount till previous,
--    this month and to date; an invoice issued before the rows were stored
--    gets them when read, without its snapshot changing; after a contract
--    correction the billed difference is an adjustment so each stage still
--    adds up.

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
    ('accountant','10000000-0000-4000-8000-000000000013','accountant')
  ) as actor(who, id, role) where who = p_who;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_id, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', v_role, 'app_user_id', 'usr-local-' || p_who)
  )::text, true);
end;
$$;

-- The seeded Project Manager, given another organization-wide role.
create function pg_temp.act_as_role(p_role text) returns void language plpgsql as $$
begin
  update auth.users set raw_app_meta_data = jsonb_set(raw_app_meta_data, '{role}', to_jsonb(p_role))
  where id = '10000000-0000-4000-8000-000000000010';
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', '10000000-0000-4000-8000-000000000010', 'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', p_role, 'app_user_id', 'usr-local-pm')
  )::text, true);
end;
$$;

create sequence pg_temp.key_seq;
create function pg_temp.key() returns uuid language sql as $$
  select ('39fc0000-0000-4000-8000-' || lpad(nextval('pg_temp.key_seq')::text, 12, '0'))::uuid;
$$;

-- Project ...01 (B1 ...02, B2 ...03), with a Project Engineer and a Site
-- Engineer as members. A second project ...11 has no members at all.
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role,job_contract_reference) values
('39fc1000-0000-4000-8000-000000000001','R39-IB-001','R39 item breakdown','active','project_engineer','10000000-0000-4000-8000-000000000004','admin','N-0002'),
('39fc1000-0000-4000-8000-000000000011','R39-IB-002','R39 nobody on it','active','project_engineer','10000000-0000-4000-8000-000000000004','admin','N-0003');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable) values
('39fc1000-0000-4000-8000-000000000002','39fc1000-0000-4000-8000-000000000001','building','b1','B1',false),
('39fc1000-0000-4000-8000-000000000003','39fc1000-0000-4000-8000-000000000001','building','b2','B2',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role) values
('39fc1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
('39fc1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_parties(id,project_id,party_kind,party_order,party_name,address) values
('39fc1000-0000-4000-8000-000000000006','39fc1000-0000-4000-8000-000000000001','main_contractor',0,'Main Contractor LLC','P.O. Box 1');

insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role) values
('39fc1000-0000-4000-8000-000000000021','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role) values
('39fc1000-0000-4000-8000-000000000022','39fc1000-0000-4000-8000-000000000021',1,'ib/site-report.pdf','Site report.pdf','application/pdf',128,repeat('d',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39fc1000-0000-4000-8000-000000000022' where id='39fc1000-0000-4000-8000-000000000021';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role) values
('39fc1000-0000-4000-8000-000000000023','39fc1000-0000-4000-8000-000000000021','39fc1000-0000-4000-8000-000000000001','project','39fc1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

-- ═══ 1. Who may record progress and prepare a claim ═════════════════════════
create function pg_temp.can_claim(p_project uuid) returns boolean language sql as $$
  select public.v1_current_user_has_capability('confirm_billing_progress', p_project)
    and public.v1_current_user_has_capability('prepare_client_claim', p_project)
    and public.v1_current_user_has_capability('view_project_commercial_values', p_project);
$$;

select pg_temp.act('pe');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000001'), 'Project Engineer on the project may claim');
select ok(not pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Project Engineer not on a project may not');
select pg_temp.act('admin');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Admin may claim on any project');
select pg_temp.act('sme');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Senior Mechanical Engineer may claim without membership');
select pg_temp.act('pm');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Project Manager may claim without membership');
select pg_temp.act_as_role('workshop_in_charge');
select is(public.v1_permission_exact_role('10000000-0000-4000-8000-000000000010'), 'workshop_in_charge', 'The test user is now Workshop In-Charge');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Workshop In-Charge may claim without membership');
select pg_temp.act_as_role('document_controller');
select is(public.v1_permission_exact_role('10000000-0000-4000-8000-000000000010'), 'document_controller', 'The test user is now Document Controller');
select ok(pg_temp.can_claim('39fc1000-0000-4000-8000-000000000011'), 'Document Controller may claim without membership');
select ok(not public.v1_current_user_has_capability('manage_client_invoices', '39fc1000-0000-4000-8000-000000000011'),
  'Document Controller does not gain invoicing');
select pg_temp.act_as_role('project_manager');
select pg_temp.act('se');
select ok(not pg_temp.can_claim('39fc1000-0000-4000-8000-000000000001'), 'Site Engineer on the project may not claim');
select ok(not public.v1_current_user_has_capability('view_project_commercial_values', '39fc1000-0000-4000-8000-000000000001'),
  'Site Engineer still sees no commercial values');
select pg_temp.act('procurement');
select ok(not pg_temp.can_claim('39fc1000-0000-4000-8000-000000000001'), 'Procurement may not claim');
select pg_temp.act('accountant');
select ok(not public.v1_current_user_has_capability('confirm_billing_progress', '39fc1000-0000-4000-8000-000000000001'),
  'Accountant still does not record progress');

-- ═══ 2. The invoice's item rows ═════════════════════════════════════════════
-- 17,192,000 over two buildings; Design 10% by percent; Material Supply 90% by
-- items: dampers (55 Nos, 1%) and AC units (6 Nos, 44%) in each building.
create function pg_temp.setup(p_value text) returns jsonb language sql as $$
  select jsonb_build_object('contract_value',p_value,'currency_code','AED','vat_rate_percent','5.0000',
    'payment_terms_days', 45,
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id','39fc1000-0000-4000-8000-000000000002','allocation_percent','50'),
      jsonb_build_object('building_scope_id','39fc1000-0000-4000-8000-000000000003','allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Cooling Load Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','90','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','damper','item_label','Motorized Fire Dampers','display_order',1,'quantity','55','unit_code','Nos','weight_percent_of_contract','1'),
          jsonb_build_object('item_key','ac','item_label','AC Units','display_order',2,'quantity','6','unit_code','Nos','weight_percent_of_contract','44')))));
$$;
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39fc1000-0000-4000-8000-000000000001',null,pg_temp.setup('17192000.00'),'Contract',pg_temp.key())$$,'The contract is set up');
select lives_ok($$select public.v1_save_project_invoice_settings('39fc1000-0000-4000-8000-000000000001','IB',null,null,null,null,pg_temp.key())$$,'Invoice settings are set');

create function pg_temp.items(p_damper text, p_ac text, p_scope uuid default null) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('stage_item_id', si.id,
    'confirmed_qty_to_date', case si.item_key when 'damper' then p_damper else p_ac end))
  from public.v1_accounts_baseline_stage_items si
  join public.v1_accounts_project_commercial_profiles cp on cp.current_baseline_revision_id = si.baseline_revision_id
  where si.project_id = '39fc1000-0000-4000-8000-000000000001' and si.stage_key = 'material_supply'
    and (p_scope is null or si.project_scope_id = p_scope);
$$;
create function pg_temp.claim(p_ref text) returns uuid language sql as $$
  select id from public.v1_accounts_client_claims where project_id = '39fc1000-0000-4000-8000-000000000001' and claim_reference = p_ref;
$$;
create function pg_temp.invoice(p_ref text) returns uuid language sql as $$
  select id from public.v1_accounts_client_invoices where project_id = '39fc1000-0000-4000-8000-000000000001' and invoice_reference = p_ref;
$$;
-- One building's item stage of an invoice document, as read.
create function pg_temp.stage(p_ref text, p_scope text) returns jsonb language sql as $$
  select s from jsonb_array_elements(
      public.v1_get_client_invoice_document('39fc1000-0000-4000-8000-000000000001', pg_temp.invoice(p_ref)) -> 'document' -> 'buildings') b,
    jsonb_array_elements(b -> 'item_stages') s
  where b ->> 'building_scope_id' = p_scope and s ->> 'stage_key' = 'material_supply';
$$;
create function pg_temp.item(p_stage jsonb, p_key text) returns jsonb language sql as $$
  select i from jsonb_array_elements(p_stage -> 'items') i where i ->> 'item_key' = p_key;
$$;

-- Claim #01 prepared by Admin (the new right): 20 of 55 dampers in each building.
select lives_ok($$select public.v1_save_claim_workbench('39fc1000-0000-4000-8000-000000000001','CLM-01',date '2026-01-01',date '2026-01-19',pg_temp.items('20','0'),array['39fc1000-0000-4000-8000-000000000021']::uuid[],'Dampers delivered',pg_temp.key())$$,
  'Admin prepares a claim');
select lives_ok($$select public.v1_submit_client_claim_to_accounts('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-01'),1,'Checked',pg_temp.key())$$,'Admin sends it to Accounts');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-01'),2,'IB01',date '2026-01-19',date '2026-01-19',pg_temp.key())$$,'Invoice IB01 is issued');

select is(pg_temp.item(pg_temp.stage('IB01','39fc1000-0000-4000-8000-000000000002'),'damper') - 'item_key' - 'item_label' - 'display_order',
  jsonb_build_object('quantity','55.0000','unit_code','Nos','weight_percent','1.000000','contract_amount','171920.00',
    'previous_qty','0','previous_percent','0.0000','previous_amount','0.00',
    'this_qty','20.0000','this_percent','0.3636','this_amount','62516.36',
    'total_qty','20.0000','total_percent','0.3636','total_amount','62516.36'),
  'IB01: dampers 20 of 55 this month, as the workbook prints them');
select is(pg_temp.stage('IB01','39fc1000-0000-4000-8000-000000000002') ->> 'this_amount', '62516.36', 'IB01: the stage bills what its items are worth');
select is(pg_temp.stage('IB01','39fc1000-0000-4000-8000-000000000002') ->> 'adjustment_this_amount', '0.00', 'IB01: no adjustment');
select is(pg_temp.stage('IB01','39fc1000-0000-4000-8000-000000000002') ->> 'contract_amount', '7736400.00', 'IB01: the stage contract amount');
select ok(not exists (select 1 from jsonb_array_elements(
    public.v1_get_client_invoice_document('39fc1000-0000-4000-8000-000000000001', pg_temp.invoice('IB01')) -> 'document' -> 'buildings') b,
    jsonb_array_elements(b -> 'item_stages') s where s ->> 'stage_key' = 'design'),
  'A percent stage has no item rows');
select ok((select bool_and(document_snapshot -> 'buildings' -> 0 ? 'item_stages') from public.v1_accounts_client_invoice_documents where invoice_id = pg_temp.invoice('IB01')),
  'A new invoice stores its item rows');

-- Claim #02 by the Project Manager (no membership): dampers to 35, all 6 AC units.
select pg_temp.act('pm');
select lives_ok($$select public.v1_save_claim_workbench('39fc1000-0000-4000-8000-000000000001','CLM-02',date '2026-09-01',date '2026-09-24',pg_temp.items('35','6'),array['39fc1000-0000-4000-8000-000000000021']::uuid[],'More deliveries',pg_temp.key())$$,
  'Project Manager prepares a claim');
select lives_ok($$select public.v1_submit_client_claim_to_accounts('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-02'),1,'Checked',pg_temp.key())$$,'Project Manager sends it to Accounts');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-02'),2,'IB02',date '2026-09-29',date '2026-09-29',pg_temp.key())$$,'Invoice IB02 is issued');

select is(
  (select jsonb_build_array(i ->> 'previous_qty', i ->> 'this_qty', i ->> 'total_qty', i ->> 'previous_amount', i ->> 'this_amount', i ->> 'total_amount')
   from (select pg_temp.item(pg_temp.stage('IB02','39fc1000-0000-4000-8000-000000000003'),'damper') i) x),
  '["20.0000", "15.0000", "35.0000", "62516.36", "46887.27", "109403.64"]'::jsonb,
  'IB02: dampers 20 till previous, 15 this month, 35 to date');
select is(pg_temp.item(pg_temp.stage('IB02','39fc1000-0000-4000-8000-000000000003'),'ac') ->> 'this_amount', '7564480.00', 'IB02: all 6 AC units this month');
select is(pg_temp.item(pg_temp.stage('IB02','39fc1000-0000-4000-8000-000000000003'),'ac') ->> 'this_percent', '44.0000', 'IB02: AC units are 44% of the contract this month');

-- An invoice issued before the rows were stored gets them when read.
reset role;
update public.v1_accounts_client_invoice_documents
set document_snapshot = jsonb_set(document_snapshot, '{buildings}',
  (select jsonb_agg(b - 'item_stages') from jsonb_array_elements(document_snapshot -> 'buildings') b))
where invoice_id = pg_temp.invoice('IB01');
create temporary table before_read as
select document_snapshot, snapshot_sha256 from public.v1_accounts_client_invoice_documents where invoice_id = pg_temp.invoice('IB01');
select pg_temp.act('accountant');
select is(pg_temp.item(pg_temp.stage('IB01','39fc1000-0000-4000-8000-000000000002'),'damper') ->> 'this_qty', '20.0000',
  'An older snapshot gets its item rows on read, as of its own claim');
reset role;
select ok((select d.document_snapshot = b.document_snapshot and d.snapshot_sha256 = b.snapshot_sha256
  from public.v1_accounts_client_invoice_documents d, before_read b where d.invoice_id = pg_temp.invoice('IB01')),
  'Reading it does not change the stored snapshot');

-- Contract correction, then claim #03 (B1 only: dampers to 40). Work billed at
-- the old values is worth more now; the difference is an adjustment.
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39fc1000-0000-4000-8000-000000000001',
  (select record_version from public.v1_accounts_project_commercial_profiles where project_id = '39fc1000-0000-4000-8000-000000000001'),
  pg_temp.setup('18085468.00'),'Contract value correction',pg_temp.key())$$,'The contract value is corrected');
select pg_temp.act('pe');
select lives_ok($$select public.v1_save_claim_workbench('39fc1000-0000-4000-8000-000000000001','CLM-03',date '2026-10-01',date '2026-10-24',pg_temp.items('40','6','39fc1000-0000-4000-8000-000000000002'),array['39fc1000-0000-4000-8000-000000000021']::uuid[],'October',pg_temp.key())$$,
  'Claim #03 is prepared after the correction');
select lives_ok($$select public.v1_submit_client_claim_to_accounts('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-03'),1,'Checked',pg_temp.key())$$,'Claim #03 is sent to Accounts');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice('39fc1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-03'),2,'IB03',date '2026-10-29',date '2026-10-29',pg_temp.key())$$,'Invoice IB03 is issued');

create temporary table s3 as select pg_temp.stage('IB03','39fc1000-0000-4000-8000-000000000002') as s;
select is((select pg_temp.item(s,'damper') ->> 'this_qty' from s3), '5.0000', 'IB03: 5 more dampers this month');
select ok((select (s ->> 'adjustment_this_amount')::numeric > 0 from s3), 'IB03: the correction top-up is an adjustment this month');
select is((select (s ->> 'this_amount')::numeric
    - (select sum((i ->> 'this_amount')::numeric) from jsonb_array_elements(s -> 'items') i)
    - (s ->> 'adjustment_this_amount')::numeric from s3) between -0.02 and 0.02, true,
  'IB03: items plus adjustment add up to what the stage bills this month');
select is((select (s ->> 'previous_amount')::numeric
    - (select sum((i ->> 'previous_amount')::numeric) from jsonb_array_elements(s -> 'items') i)
    - (s ->> 'adjustment_previous_amount')::numeric from s3) between -0.02 and 0.02, true,
  'IB03: items plus adjustment add up to what was billed before');
select is((select s ->> 'previous_amount' from s3), '7673883.64', 'IB03: till previous is what was actually billed');

-- Money stays with those who may see it.
select pg_temp.act('se');
select throws_ok($$select public.v1_save_claim_workbench('39fc1000-0000-4000-8000-000000000001','CLM-X',date '2026-11-01',date '2026-11-02',pg_temp.items('41','6','39fc1000-0000-4000-8000-000000000002'),array['39fc1000-0000-4000-8000-000000000021']::uuid[],'SE try',pg_temp.key())$$,
  '42501', null, 'Site Engineer cannot prepare a claim');
select pg_temp.act('procurement');
select throws_ok($$select public.v1_save_claim_workbench('39fc1000-0000-4000-8000-000000000001','CLM-X',date '2026-11-01',date '2026-11-02',pg_temp.items('41','6','39fc1000-0000-4000-8000-000000000002'),array['39fc1000-0000-4000-8000-000000000021']::uuid[],'Procurement try',pg_temp.key())$$,
  '42501', null, 'Procurement cannot prepare a claim');
reset role;
select ok(not has_function_privilege('anon', 'public.v1_accounts_invoice_item_breakdown(uuid, uuid)', 'execute'), 'The item breakdown helper is not callable by anon');
select ok(not has_function_privilege('authenticated', 'public.v1_accounts_invoice_item_breakdown(uuid, uuid)', 'execute'), 'The item breakdown helper is not callable directly');

select * from finish();
rollback;

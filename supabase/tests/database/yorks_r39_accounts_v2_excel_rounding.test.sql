-- R39 Accounts Workspace V2 — Excel rounding, the signed invoice document,
-- business dates in History and the Overview's "to come".
--
-- A claim's gross, VAT and total are rounded once each from the exact sum (as
-- the Yorks workbook), so an invoice total may differ from ex-VAT + VAT by a
-- fil; certifying in full carries the invoice's own figures; the document's
-- "till previous" counts every earlier invoiced claim; History is dated by when
-- things happened and names them; money stays out for those without it.

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
  select ('39fb0000-0000-4000-8000-' || lpad(nextval('pg_temp.key_seq')::text, 12, '0'))::uuid;
$$;

-- Ids: project ...01; buildings ...02 (B1) ...03 (B2); parties ...05 (client)
-- ...06 (main contractor).
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role,job_contract_reference)
values('39fb1000-0000-4000-8000-000000000001','R39-XL-001','R39 Excel rounding','active','project_engineer','10000000-0000-4000-8000-000000000004','admin','N-0001');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable) values
('39fb1000-0000-4000-8000-000000000002','39fb1000-0000-4000-8000-000000000001','building','b1','B1',false),
('39fb1000-0000-4000-8000-000000000003','39fb1000-0000-4000-8000-000000000001','building','b2','B2',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role) values
('39fb1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
('39fb1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_parties(id,project_id,party_kind,party_order,party_name,address) values
('39fb1000-0000-4000-8000-000000000005','39fb1000-0000-4000-8000-000000000001','client',0,'End User Co',null),
('39fb1000-0000-4000-8000-000000000006','39fb1000-0000-4000-8000-000000000001','main_contractor',0,'Main Contractor LLC','P.O. Box 1, Abu Dhabi');

-- Evidence for progress (a site report linked to the project).
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role) values
('39fb1000-0000-4000-8000-000000000021','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role) values
('39fb1000-0000-4000-8000-000000000022','39fb1000-0000-4000-8000-000000000021',1,'xl/site-report.pdf','Site report.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39fb1000-0000-4000-8000-000000000022' where id='39fb1000-0000-4000-8000-000000000021';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role) values
('39fb1000-0000-4000-8000-000000000023','39fb1000-0000-4000-8000-000000000021','39fb1000-0000-4000-8000-000000000001','project','39fb1000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

-- 17,192,000 over two buildings; Design 10% by percent; Material Supply 90% by
-- items: dampers (55 Nos, 1%) and AC units (6 Nos, 44%) in each building.
create function pg_temp.setup() returns jsonb language sql as $$
  select jsonb_build_object('contract_value','17192000.00','currency_code','AED','vat_rate_percent','5.0000',
    'payment_terms_days', 45,
    'buildings', jsonb_build_array(
      jsonb_build_object('building_scope_id','39fb1000-0000-4000-8000-000000000002','allocation_percent','50'),
      jsonb_build_object('building_scope_id','39fb1000-0000-4000-8000-000000000003','allocation_percent','50')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Cooling Load Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','90','position',2,'measurement_mode','items',
        'items', jsonb_build_array(
          jsonb_build_object('item_key','damper','item_label','Motorized Fire Dampers','display_order',1,'quantity','55','unit_code','Nos','weight_percent_of_contract','1'),
          jsonb_build_object('item_key','ac','item_label','AC Units','display_order',2,'quantity','6','unit_code','Nos','weight_percent_of_contract','44')))));
$$;
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39fb1000-0000-4000-8000-000000000001',null,pg_temp.setup(),'Contract',pg_temp.key())$$,'The contract is set up');
select lives_ok($$select public.v1_save_project_invoice_settings('39fb1000-0000-4000-8000-000000000001','XL',null,null,null,null,pg_temp.key())$$,'Invoice settings are set');

create function pg_temp.design_entries() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('progress_entry_id', bp.id, 'confirmed_percent_to_date', '100'))
  from public.v1_accounts_billing_progress bp
  join public.v1_accounts_project_commercial_profiles cp on cp.current_baseline_revision_id = bp.baseline_revision_id
  where bp.project_id = '39fb1000-0000-4000-8000-000000000001' and bp.stage_key = 'design';
$$;
create function pg_temp.material_entries() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('stage_item_id', si.id,
    'confirmed_qty_to_date', case si.item_key when 'damper' then '20' else '6' end))
  from public.v1_accounts_baseline_stage_items si
  join public.v1_accounts_project_commercial_profiles cp on cp.current_baseline_revision_id = si.baseline_revision_id
  where si.project_id = '39fb1000-0000-4000-8000-000000000001' and si.stage_key = 'material_supply';
$$;
create function pg_temp.claim(p_ref text) returns uuid language sql as $$
  select id from public.v1_accounts_client_claims where project_id = '39fb1000-0000-4000-8000-000000000001' and claim_reference = p_ref;
$$;
create function pg_temp.invoice(p_ref text) returns public.v1_accounts_client_invoices language sql as $$
  select * from public.v1_accounts_client_invoices where project_id = '39fb1000-0000-4000-8000-000000000001' and invoice_reference = p_ref;
$$;

-- Claim #01: Design 100% in both buildings, invoiced on 19 Jan 2026.
select pg_temp.act('pe');
select lives_ok($$select public.v1_save_claim_workbench('39fb1000-0000-4000-8000-000000000001','CLM-01',date '2026-01-01',date '2026-01-19',pg_temp.design_entries(),array['39fb1000-0000-4000-8000-000000000021']::uuid[],'January progress',pg_temp.key())$$,'Claim #01 is prepared');
select lives_ok($$select public.v1_submit_client_claim_to_accounts('39fb1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-01'),1,'Checked',pg_temp.key())$$,'Claim #01 is sent to Accounts');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice('39fb1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-01'),2,'XL01',date '2026-01-19',date '2026-01-19',pg_temp.key())$$,'Invoice XL01 is issued, dated 19 Jan 2026');
select is((pg_temp.invoice('XL01')).total_incl_vat_snapshot, 1805160.00::numeric, 'XL01 total is 1,805,160.00');
select lives_ok($$select public.v1_record_client_certification('39fb1000-0000-4000-8000-000000000001',(pg_temp.invoice('XL01')).id,(pg_temp.invoice('XL01')).record_version,'CERT-01',date '2026-02-02','1719200.00',null,pg_temp.key())$$,'XL01 is certified in full');

-- Claim #02: 20 of 55 dampers and all 6 AC units in each building.
select pg_temp.act('pe');
select lives_ok($$select public.v1_save_claim_workbench('39fb1000-0000-4000-8000-000000000001','CLM-02',date '2026-09-01',date '2026-09-24',pg_temp.material_entries(),array['39fb1000-0000-4000-8000-000000000021']::uuid[],'Material deliveries',pg_temp.key())$$,'Claim #02 is prepared');

select is(
  (select array_agg(l.claimed_amount order by l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = pg_temp.claim('CLM-02')),
  array[7626996.36, 7626996.36]::numeric[],
  'Each building line shows its amount rounded to fils');
select ok(
  (select bool_and(l.claimed_amount_exact > 7626996.3636 and l.claimed_amount_exact < 7626996.3637) from public.v1_accounts_client_claim_lines l where l.claim_id = pg_temp.claim('CLM-02')),
  'Each line keeps its exact amount (7,626,996.3636…)');

select pg_temp.act('accountant');
select is(
  public.v1_get_claim_workbench('39fb1000-0000-4000-8000-000000000001', pg_temp.claim('CLM-02')) -> 'claim' ->> 'net_payable',
  '16016692.36', 'The workbench shows the net payable by the Excel rule');

select pg_temp.act('pe');
select lives_ok($$select public.v1_submit_client_claim_to_accounts('39fb1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-02'),1,'Checked',pg_temp.key())$$,'Claim #02 is sent to Accounts');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_issue_client_invoice('39fb1000-0000-4000-8000-000000000001',pg_temp.claim('CLM-02'),2,'XL02',date '2026-09-29',date '2026-09-29',pg_temp.key())$$,'Invoice XL02 is issued, dated 29 Sep 2026');

select is((pg_temp.invoice('XL02')).claimed_ex_vat, 15253992.73::numeric, 'Gross is the exact sum rounded once (lines add to .72)');
select is((pg_temp.invoice('XL02')).vat_amount_snapshot, 762699.64::numeric, 'VAT is the exact gross x 5% rounded once');
select is((pg_temp.invoice('XL02')).total_incl_vat_snapshot, 16016692.36::numeric, 'Total is the exact gross x 1.05 rounded once');
select is((pg_temp.invoice('XL02')).total_incl_vat_snapshot - ((pg_temp.invoice('XL02')).claimed_ex_vat + (pg_temp.invoice('XL02')).vat_amount_snapshot), -0.01::numeric,
  'The total may differ from ex-VAT + VAT by a fil, as on the signed invoices');

-- The relaxed check still refuses anything beyond a fil.
reset role;
select throws_ok($$update public.v1_accounts_client_invoices set total_incl_vat_snapshot = total_incl_vat_snapshot + 0.03 where invoice_reference = 'XL02' and project_id = '39fb1000-0000-4000-8000-000000000001'$$,
  '23514', null, 'A total more than a fil away from ex-VAT + VAT is refused');

-- Certified in full: the certification carries the invoice's VAT and total.
select pg_temp.act('accountant');
select lives_ok($$select public.v1_record_client_certification('39fb1000-0000-4000-8000-000000000001',(pg_temp.invoice('XL02')).id,(pg_temp.invoice('XL02')).record_version,'CERT-02',date '2026-10-20','15253992.73',null,pg_temp.key())$$,'XL02 is certified in full');
select is((select certified_incl_vat from public.v1_accounts_client_certifications where invoice_id = (pg_temp.invoice('XL02')).id),
  16016692.36::numeric, 'The certified total is the invoice total');

-- The frozen document: till previous counts claim #01 on every stage.
create function pg_temp.doc(p_ref text) returns jsonb language sql as $$
  select d.document_snapshot from public.v1_accounts_client_invoice_documents d where d.invoice_id = (pg_temp.invoice(p_ref)).id;
$$;
select is(pg_temp.doc('XL02') -> 'amounts' ->> 'total_incl_vat', '16016692.36', 'The document prints the invoice total');
select is(pg_temp.doc('XL02') -> 'summary' ->> 'previous_total', '1719200.00', 'Till previous counts claim #01 (Design), on a claim with no Design line');
select is(pg_temp.doc('XL02') -> 'summary' ->> 'previous_grand', '1805160.00', 'Till previous with VAT');
select is(pg_temp.doc('XL02') -> 'summary' ->> 'total_total', '16973192.73', 'Cumulative ex-VAT from the exact sums');
select is(pg_temp.doc('XL02') -> 'summary' ->> 'total_vat', '848659.64', 'Cumulative VAT');
select is(pg_temp.doc('XL02') -> 'summary' ->> 'total_grand', '17821852.36', 'Cumulative grand total');
select is((select s ->> 'previous_amount' from jsonb_array_elements(pg_temp.doc('XL02') -> 'summary' -> 'stages') s where s ->> 'stage_key' = 'design'),
  '1719200.00', 'The Design row shows its till-previous amount');
select is((select s ->> 'this_amount' from jsonb_array_elements(pg_temp.doc('XL02') -> 'summary' -> 'stages') s where s ->> 'stage_key' = 'material_supply'),
  '15253992.73', 'The Material Supply row rounds its own exact sum');
select is((select b ->> 'this_amount' from jsonb_array_elements(pg_temp.doc('XL02') -> 'buildings') b where b ->> 'name' = 'B1'),
  '7626996.36', 'Each building rounds its own exact sum');
select is(pg_temp.doc('XL02') -> 'bill_to' ->> 'name', 'Main Contractor LLC', 'With no party chosen, the main contractor is billed');
select is(pg_temp.doc('XL02') ->> 'invoice_date', '2026-09-29', 'The document carries the invoice date');
select is(public.v1_accounts_invoice_snapshot((pg_temp.invoice('XL02')).id) ->> 'invoice_date', '2026-09-29', 'An invoice read carries its invoice date');

-- A cheque for the full total, received 1 Nov, still in hand.
select lives_ok($$select public.v1_create_client_pdc('39fb1000-0000-4000-8000-000000000001',(pg_temp.invoice('XL02')).id,(pg_temp.invoice('XL02')).record_version,'004893',date '2026-11-13','16016692.36','Bank',pg_temp.key())$$,'A cheque for the full total is recorded');
create function pg_temp.pdc() returns public.v1_accounts_client_pdcs language sql as $$
  select * from public.v1_accounts_client_pdcs where invoice_id = (pg_temp.invoice('XL02')).id;
$$;
select lives_ok($$select public.v1_transition_client_pdc('39fb1000-0000-4000-8000-000000000001',(pg_temp.pdc()).id,(pg_temp.pdc()).record_version,'received',date '2026-11-01',null,null,pg_temp.key())$$,'The cheque is received on 1 Nov');

-- Overview: to come is invoiced and not yet paid.
select is(
  (select s -> 'detail' ->> 'to_come' from jsonb_array_elements(public.v1_get_project_accounts_workspace('39fb1000-0000-4000-8000-000000000001') -> 'steps') s where s ->> 'key' = 'paid'),
  '17821852.36', 'To come is both unpaid invoices (1,805,160 + 16,016,692.36), not the unbilled contract');
select is(
  (select s ->> 'state' from jsonb_array_elements(public.v1_get_project_accounts_workspace('39fb1000-0000-4000-8000-000000000001') -> 'steps') s where s ->> 'key' = 'progress'),
  'done', 'With no claim open, progress is done');

-- History: dated by when things happened, named by their references.
create function pg_temp.entries(p_who text) returns setof jsonb language plpgsql as $$
begin
  perform pg_temp.act(p_who);
  return query select e from jsonb_array_elements(
    public.v1_get_accounts_activity('39fb1000-0000-4000-8000-000000000001', null, null, null, null, null, 100, 0) -> 'entries') e;
end;
$$;
select is((select e ->> 'business_date' from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_invoice.submitted' and e -> 'context' ->> 'invoice_reference' = 'XL01'),
  '2026-01-19', 'An invoice is dated by its invoice date');
select is((select e ->> 'business_date' from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_certification.recorded' and e -> 'context' ->> 'invoice_reference' = 'XL02'),
  '2026-10-20', 'A certification is dated by its certification date');
select is((select e -> 'context' ->> 'bill_to' from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_certification.recorded' and e -> 'context' ->> 'invoice_reference' = 'XL02'),
  'Main Contractor LLC', 'A certification names who certified it');
select is((select e ->> 'business_date' from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_pdc.received'),
  '2026-11-01', 'A cheque is dated by the day it was received');
select is((select e -> 'context' ->> 'cheque_number' from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_pdc.received'),
  '004893', 'A cheque entry names the cheque');
select is((select count(*)::integer from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts_progress_confirmed' and e ->> 'business_date' = '2026-01-19'),
  2, 'Progress saved with claim #01 takes the claim''s date');
select is((select (e -> 'context' ->> 'claim_number')::integer from pg_temp.entries('accountant') e where e ->> 'event_type' = 'accounts.client_claim.created' and e -> 'context' ->> 'period_end' = '2026-09-24'),
  2, 'Claim #02 is numbered 2');
select is((select e ->> 'business_date' from pg_temp.entries('accountant') e where e -> 'context' is not null and jsonb_typeof(e -> 'context') = 'object' limit 1), '2026-11-01',
  'The newest happening comes first, whenever it was recorded');
select is((select array_agg(e ->> 'business_date') from pg_temp.entries('accountant') e),
  (select array_agg(d order by d desc) from (select e ->> 'business_date' d from pg_temp.entries('accountant') e) q),
  'History is ordered by the day things happened');

-- Without commercial values the references stay but money does not.
select ok((select bool_and(not (e -> 'context' ? 'amount') and not (e -> 'context' ? 'claimed_ex_vat')
    and not (e -> 'context' ? 'total_incl_vat') and not (e -> 'context' ? 'certified_ex_vat'))
  from pg_temp.entries('se') e where e -> 'context' is not null and jsonb_typeof(e -> 'context') = 'object'),
  'A Site Engineer''s History carries no money');
select ok((select bool_or(e -> 'context' ->> 'invoice_reference' = 'XL02') from pg_temp.entries('se') e),
  'A Site Engineer''s History still names the invoice');
select pg_temp.act('se');
select ok(not (public.v1_get_claim_workbench('39fb1000-0000-4000-8000-000000000001', pg_temp.claim('CLM-02')) -> 'claim' ? 'claimed_ex_vat_exact'),
  'A Site Engineer''s workbench carries no exact gross');
select pg_temp.act('procurement');
select throws_ok($$select public.v1_get_accounts_activity('39fb1000-0000-4000-8000-000000000001', null, null, null, null, null, 100, 0)$$,
  '42501', null, 'Procurement cannot read Accounts History');

-- The bill-to party can be chosen; the contract setup lists the parties' ids.
select pg_temp.act('admin');
select is(public.v1_get_project_commercial_setup('39fb1000-0000-4000-8000-000000000001') -> 'parties' -> 'main_contractor' ->> 'party_id',
  '39fb1000-0000-4000-8000-000000000006', 'The contract setup gives each party''s id');

-- The helpers are internal.
select ok(not has_function_privilege('authenticated', 'public.v1_accounts_excel_amounts(numeric, numeric)', 'execute'), 'The Excel helper is not an API');
select ok(not has_function_privilege('authenticated', 'public.v1_accounts_claim_exact_gross(uuid)', 'execute'), 'The exact-gross helper is not an API');
select ok(not has_function_privilege('authenticated', 'public.v1_accounts_activity_context(text, uuid, uuid, jsonb, boolean, timestamptz)', 'execute'), 'The History context helper is not an API');
select ok(not has_function_privilege('anon', 'public.v1_accounts_claim_number(uuid)', 'execute'), 'The claim-number helper is not an API');

-- The Excel rule itself.
select is((select row(ex_vat, vat, total)::text from public.v1_accounts_excel_amounts(5983597.454545454545, 5)),
  '(5983597.45,299179.87,6282777.33)', 'The signed YRA32202R.1 figures come out exactly');

select * from finish();
rollback;

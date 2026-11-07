-- R39 Accounts Workspace V2 — owner decisions of 7 November 2026
--
-- Who may edit a contract and see commercial values, and how every money record
-- can be reversed or edited. Commands run under each actor's own JWT claims;
-- grants are checked separately at the end.

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

-- A fresh idempotency key each call, from a counter, so scenarios stay readable.
create sequence pg_temp.key_seq;
create function pg_temp.key() returns uuid language sql as $$
  select ('39f9a000-0000-4000-8000-' || lpad(nextval('pg_temp.key_seq')::text, 12, '0'))::uuid;
$$;

create function pg_temp.setup_payload(p_value text) returns jsonb language sql as $$
  select jsonb_build_object('contract_value', p_value, 'currency_code', 'AED', 'vat_rate_percent', '5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id', '39d1a000-0000-4000-8000-000000000002', 'allocation_percent', '100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent')));
$$;

create function pg_temp.revision() returns integer language sql as $$
  select coalesce(max(revision_number), 0)::integer from public.v1_accounts_baseline_revisions
  where project_id = '39d1a000-0000-4000-8000-000000000001';
$$;

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d1a000-0000-4000-8000-000000000001','R39-V2C-001','R39 V2 corrections','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39d1a000-0000-4000-8000-000000000002','39d1a000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d1a000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin'),
      ('39d1a000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d1a000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d1a000-0000-4000-8000-000000000004','39d1a000-0000-4000-8000-000000000003',1,'r39/v2c/p.pdf','p.pdf','application/pdf',128,repeat('e',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d1a000-0000-4000-8000-000000000004' where id='39d1a000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d1a000-0000-4000-8000-000000000005','39d1a000-0000-4000-8000-000000000003','39d1a000-0000-4000-8000-000000000001','project','39d1a000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');
create temporary table r(k text primary key, v jsonb not null);

-- ═══ Decision 2: who may edit a contract ════════════════════════════════════
select pg_temp.act('admin');
select lives_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',null,pg_temp.setup_payload('1000000.00'),'Admin sets it up',pg_temp.key())$$,'Admin can set up the contract');
select pg_temp.act('pe');
select lives_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1000100.00'),'PE edit',pg_temp.key())$$,'Project Engineer can edit the contract');
select pg_temp.act('sme');
select lives_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1000200.00'),'SME edit',pg_temp.key())$$,'Senior Mechanical Engineer can edit the contract');
select pg_temp.act('pm');
select lives_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1000300.00'),'PM edit',pg_temp.key())$$,'Project Manager can edit the contract');
select pg_temp.act('accountant');
select lives_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1000000.00'),'Accountant edit',pg_temp.key())$$,'Accountant can edit the contract');
select pg_temp.act('se');
select throws_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1.00'),'SE edit',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Site Engineer cannot edit the contract');
select pg_temp.act('procurement');
select throws_ok($$select public.v1_save_project_commercial_setup('39d1a000-0000-4000-8000-000000000001',pg_temp.revision(),pg_temp.setup_payload('1.00'),'Procurement edit',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Procurement cannot edit the contract');

-- A per-user denial still beats the new default.
select is(public.v1_permission_exact_role('10000000-0000-4000-8000-000000000001'),'project_engineer','The Project Engineer keeps the exact role');

-- ═══ Decision 3: commercial values ══════════════════════════════════════════
select pg_temp.act('pe');
select ok(public.v1_current_user_has_capability('view_project_commercial_values','39d1a000-0000-4000-8000-000000000001'),'Project Engineer sees commercial values by default');
select ok(not public.v1_current_user_has_capability('view_supplier_costs','39d1a000-0000-4000-8000-000000000001'),'That does not extend to supplier costs');
select pg_temp.act('se');
select ok(not public.v1_current_user_has_capability('view_project_commercial_values','39d1a000-0000-4000-8000-000000000001'),'Site Engineer still does not');
select pg_temp.act('procurement');
select ok(not public.v1_current_user_has_capability('view_project_commercial_values','39d1a000-0000-4000-8000-000000000001'),'Procurement still does not');

-- ═══ An invoice to work on: 50,000 + 5% VAT = 52,500 ════════════════════════
reset role;
insert into r select 'progress', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39d1a000-0000-4000-8000-000000000001' and stage_key='design' order by created_at desc limit 1));
select pg_temp.act('pe');
select public.v1_confirm_billing_progress('39d1a000-0000-4000-8000-000000000001',(select (v->>'id')::uuid from r where k='progress'),(select record_version from public.v1_accounts_billing_progress where id=(select (v->>'id')::uuid from r where k='progress')),'100.0000','d',array['39d1a000-0000-4000-8000-000000000003'::uuid],'c',pg_temp.key());
insert into r select 'claim', public.v1_create_client_claim_draft('39d1a000-0000-4000-8000-000000000001','CLM-C',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (v->>'id')::uuid from r where k='progress'),'claimed_amount','50000.00','evidence_reference','V')),'a',pg_temp.key());
select public.v1_submit_client_claim_to_accounts('39d1a000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from r where k='claim'),1,'r',pg_temp.key());
select pg_temp.act('admin');
select public.v1_save_project_invoice_settings('39d1a000-0000-4000-8000-000000000001','YRC',null,null,null,null,pg_temp.key());
insert into r select 'issue', public.v1_issue_client_invoice('39d1a000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from r where k='claim'),2,null,date '2026-08-26',date '2026-08-26',pg_temp.key());

create function pg_temp.inv() returns uuid language sql as $$ select (v->>'invoice_id')::uuid from r where k='issue'; $$;

-- ═══ The claim workbench keeps claim money to commercial readers ═════════════
create function pg_temp.wb() returns jsonb language sql as $$
  select public.v1_get_claim_workbench('39d1a000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from r where k='claim'));
$$;
select pg_temp.act('se');
select ok(pg_temp.wb()->'claim' ? 'claim_reference','A Site Engineer still sees which claim it is');
select ok(not (pg_temp.wb()->'claim' ? 'claimed_ex_vat'),'A Site Engineer gets no claim total');
select ok(not (pg_temp.wb()->'claim' ? 'net_payable') and not (pg_temp.wb()->'claim' ? 'invoice'),'A Site Engineer gets no payable or invoice');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.wb()->'claim'->'lines') l
  where l ?| array['claimed_amount','stage_value_snapshot','eligible_amount_snapshot','previously_claimed_amount_snapshot']),0,
  'A Site Engineer gets no money on any claim line');
select ok((pg_temp.wb()->'claim'->'lines'->0) ? 'confirmed_percent_snapshot','The line percent stays for a Site Engineer');
select is(pg_temp.wb()->'claim'->>'prepared_by',(select public.v1_safe_profile_display_name(display_name,auth_user_id) from public.v1_profiles where auth_user_id='10000000-0000-4000-8000-000000000001'),'Everyone sees who prepared the claim');
select pg_temp.act('pe');
select is(pg_temp.wb()->'claim'->>'claimed_ex_vat','50000.00','The Project Engineer sees the claim total');
select is(pg_temp.wb()->'claim'->'lines'->0->>'claimed_amount','50000.00','The Project Engineer sees the line amount');
select is(pg_temp.wb()->'claim'->'invoice'->>'invoice_id',pg_temp.inv()::text,'The Project Engineer sees the invoice the claim produced');
create function pg_temp.design(p jsonb) returns jsonb language sql as $$
  select c from jsonb_array_elements(p->'cells') c where c->>'stage_key'='design';
$$;
select is(pg_temp.design(pg_temp.wb())->>'percent_before_claim','0','Nothing of Design was done before the claim');
select is((pg_temp.design(pg_temp.wb())->>'percent_this_claim')::numeric,100::numeric,'The claim holds the Design progress confirmed when it was checked');
select is(pg_temp.design(pg_temp.wb())->>'this_claim_amount','50000.00','The claim holds 50,000 of Design');
select is(pg_temp.design(pg_temp.wb())->>'claimed_before_claim','0.00','No Design money was claimed before it');
select is((select (c->>'percent_this_claim')::numeric from jsonb_array_elements(pg_temp.wb()->'cells') c where c->>'stage_key'='installation'),0::numeric,'A stage the claim has no line for holds nothing');
create function pg_temp.wb_open() returns jsonb language sql as $$
  select public.v1_get_claim_workbench('39d1a000-0000-4000-8000-000000000001');
$$;
select is((pg_temp.design(pg_temp.wb_open())->>'percent_before_claim')::numeric,100::numeric,'With no claim open, Design progress counts as done before the next claim');
select is(pg_temp.design(pg_temp.wb_open())->>'claimed_before_claim','50000.00','With no claim open, all Design money claimed so far counts as before');
select pg_temp.act('se');
select ok(pg_temp.design(pg_temp.wb()) ? 'percent_this_claim','A Site Engineer sees the progress split');
select ok(not (pg_temp.design(pg_temp.wb()) ?| array['claimed_before_claim','this_claim_amount']),'A Site Engineer gets no money split');
select ok(not has_function_privilege('authenticated','public.v1_accounts_dimension_percent_at(uuid,uuid,text,timestamptz)','execute'),'The progress history helper is internal');
select ok(not has_function_privilege('authenticated','public.v1_accounts_item_qty_at(uuid,uuid,text,text,timestamptz)','execute'),'The item history helper is internal');
select pg_temp.act('admin');
select is(pg_temp.wb()->'claim'->>'claimed_ex_vat','50000.00','Admin sees the claim total');
select ok(public.v1_get_project_commercial_setup('39d1a000-0000-4000-8000-000000000001') ?& array['job_contract_reference','project_site'],
  'The contract read carries the project details a contract starts from');
select pg_temp.act('procurement');
select throws_ok($$select pg_temp.wb()$$,'42501',null,'Procurement cannot read the claim workbench');
select pg_temp.act('admin');
create function pg_temp.iv() returns integer language sql as $$ select record_version from public.v1_accounts_client_invoices where id=pg_temp.inv(); $$;
create function pg_temp.paid() returns numeric language sql as $$ select public.v1_accounts_invoice_paid_amount(pg_temp.inv()); $$;
create function pg_temp.pdc(p_no text) returns uuid language sql as $$ select id from public.v1_accounts_client_pdcs where cheque_number=p_no and project_id='39d1a000-0000-4000-8000-000000000001'; $$;
create function pg_temp.pv(p_no text) returns integer language sql as $$ select record_version from public.v1_accounts_client_pdcs where id=pg_temp.pdc(p_no); $$;
create function pg_temp.ps(p_no text) returns text language sql as $$ select status from public.v1_accounts_client_pdcs where id=pg_temp.pdc(p_no); $$;
create function pg_temp.move(p_no text,p_to text,p_reason text,p_ref text default null) returns jsonb language sql as $$
  select public.v1_transition_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc(p_no),pg_temp.pv(p_no),p_to,date '2026-09-20',p_reason,p_ref,pg_temp.key());
$$;

select public.v1_record_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-1',date '2026-08-27','50000.00',null,pg_temp.key());

-- ═══ Cheque: every step can be walked back ══════════════════════════════════
select public.v1_create_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CHQ-1',date '2026-09-15','52500.00','Bank',pg_temp.key());
select pg_temp.move('CHQ-1','received',null);
select throws_ok($$select pg_temp.move('CHQ-1','expected',null)$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Stepping a cheque back needs a reason');
select pg_temp.move('CHQ-1','expected','Marked in hand by mistake');
select is(pg_temp.ps('CHQ-1'),'expected','A received cheque can step back to expected');
select is((select received_date from public.v1_accounts_client_pdcs where id=pg_temp.pdc('CHQ-1')),null::date,'Stepping back clears the received date');
select pg_temp.move('CHQ-1','received',null);
select pg_temp.move('CHQ-1','deposited',null);
select pg_temp.move('CHQ-1','received','Not actually banked');
select is(pg_temp.ps('CHQ-1'),'received','A deposited cheque can step back');
select pg_temp.move('CHQ-1','deposited',null);
select pg_temp.move('CHQ-1','bounced','Insufficient funds');
select ok((select action_required from public.v1_accounts_client_pdcs where id=pg_temp.pdc('CHQ-1')),'A bounced cheque is flagged for action');
select pg_temp.move('CHQ-1','received','Client asked to re-present');
select is(pg_temp.ps('CHQ-1'),'received','A bounced cheque can be re-presented');
select ok(not (select action_required from public.v1_accounts_client_pdcs where id=pg_temp.pdc('CHQ-1')),'Re-presenting clears the flag');
select pg_temp.move('CHQ-1','deposited',null);

-- ═══ Cheque: undo clearing, and clear again with the same bank reference ════
select pg_temp.move('CHQ-1','cleared',null,'BANK-1');
select is(pg_temp.paid(),52500.00::numeric,'Clearing brings the money in');
select is((select status from public.v1_accounts_client_invoices where id=pg_temp.inv()),'paid','The invoice is paid');
select throws_ok($$select pg_temp.move('CHQ-1','deposited',null)$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Undoing clearing needs a reason');
select pg_temp.move('CHQ-1','deposited','Cleared the wrong cheque');
select is(pg_temp.ps('CHQ-1'),'deposited','The cheque goes back to deposited');
select is(pg_temp.paid(),0.00::numeric,'Its money comes back out in the same step');
select is((select status from public.v1_accounts_client_invoices where id=pg_temp.inv()),'certified','The invoice is no longer paid');
select is((select payment_reference from public.v1_accounts_client_payments where invoice_id=pg_temp.inv() and entry_kind='reversal' order by created_at desc limit 1),'REV-BANK-1','The reversal gets a reference by itself');
select pg_temp.move('CHQ-1','cleared',null,'BANK-1');
select is(pg_temp.paid(),52500.00::numeric,'It clears again, with the same bank reference');

-- ═══ Decision 4: reversing a cheque's payment moves the cheque ══════════════
select public.v1_reverse_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),
  (select id from public.v1_accounts_client_payments p where p.invoice_id=pg_temp.inv() and p.entry_kind='receipt' and not exists(select 1 from public.v1_accounts_client_payments x where x.original_payment_id=p.id)),
  date '2026-09-21',null,'Recorded too early',pg_temp.key());
select is(pg_temp.ps('CHQ-1'),'deposited','Reversing a cheque payment puts the cheque back to deposited, not Cleared');
select is(pg_temp.paid(),0.00::numeric,'And the money is out');
select pg_temp.move('CHQ-1','cleared',null,'BANK-1');
select public.v1_reverse_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),
  (select id from public.v1_accounts_client_payments p where p.invoice_id=pg_temp.inv() and p.entry_kind='receipt' and not exists(select 1 from public.v1_accounts_client_payments x where x.original_payment_id=p.id)),
  date '2026-09-22','','Bank returned it after clearing',pg_temp.key(),'bounced');
select is(pg_temp.ps('CHQ-1'),'bounced','A cheque that bounced after clearing can say so');
select ok((select action_required from public.v1_accounts_client_pdcs where id=pg_temp.pdc('CHQ-1')),'And is flagged for action');
select is((select payment_reference from public.v1_accounts_client_payments where invoice_id=pg_temp.inv() and entry_kind='reversal' order by created_at desc, payment_reference desc limit 1),'REV-BANK-1-3','Each reversal of a re-used reference gets its own');
select is((select count(*)::integer from public.v1_accounts_client_pdc_events where pdc_id=pg_temp.pdc('CHQ-1') and from_status='cleared'),3,'Every undo is in the cheque history');

-- ═══ Cheque: edit details, restore, and the caps ════════════════════════════
select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-1'),pg_temp.pv('CHQ-1'),'CHQ-1A',date '2026-09-16','52000.00','New bank','Typed it wrong',pg_temp.key());
select is((select amount from public.v1_accounts_client_pdcs where cheque_number='CHQ-1A'),52000.00::numeric,'A cheque amount can be edited');
select is((select bank_name from public.v1_accounts_client_pdcs where cheque_number='CHQ-1A'),'New bank','So can the bank');
select pg_temp.move('CHQ-1A','received','Re-presented');
select throws_ok($$select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-1A'),pg_temp.pv('CHQ-1A'),'CHQ-1A',date '2026-09-16','52501.00',null,'Too much',pg_temp.key())$$,'23514','R39_ACCOUNTS_PDC_EXPOSURE_CAP_EXCEEDED','An edit cannot exceed what is left to collect');
select throws_ok($$select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-1A'),1,'CHQ-1A',date '2026-09-16','1.00',null,'Stale',pg_temp.key())$$,'40001','R39_ACCOUNTS_VERSION_CONFLICT','A stale edit is refused, not overwritten');
select throws_ok($$select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-1A'),pg_temp.pv('CHQ-1A'),'CHQ-1A',date '2026-09-16','1.00',null,' ',pg_temp.key())$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Editing a cheque needs a reason');
select pg_temp.move('CHQ-1A','cancelled','Client withdrew it');
select public.v1_create_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CHQ-2',date '2026-09-18','52500.00','Bank',pg_temp.key());
select throws_ok($$select pg_temp.move('CHQ-1A','expected','Restore')$$,'23514','R39_ACCOUNTS_PDC_EXPOSURE_CAP_EXCEEDED','Restoring is refused when another cheque already covers the amount');
select pg_temp.move('CHQ-2','cancelled','Wrong one');
select pg_temp.move('CHQ-1A','expected','It was fine after all');
select is(pg_temp.ps('CHQ-1A'),'expected','A cancelled cheque can be restored');
select throws_ok($$select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-1A'),pg_temp.pv('CHQ-1A'),'CHQ-2',date '2026-09-16','100.00',null,'Clash',pg_temp.key())$$,'23505','R39_ACCOUNTS_DUPLICATE_PDC_REFERENCE','A cheque number cannot clash with another cheque');
select pg_temp.move('CHQ-1A','cancelled','Done with it');

-- ═══ Payment: edit in one step ══════════════════════════════════════════════
select public.v1_record_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),date '2026-09-25','bank_transfer','P-1','10000.00',null,pg_temp.key());
insert into r select 'p1', jsonb_build_object('id',(select id from public.v1_accounts_client_payments where invoice_id=pg_temp.inv() and payment_reference='P-1'));
insert into r select 'fixkey', jsonb_build_object('key',pg_temp.key());
insert into r select 'fix1', public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),(select (v->>'id')::uuid from r where k='p1'),date '2026-09-26','cash','P-1','12000.00','Amount typed wrong',(select (v->>'key')::uuid from r where k='fixkey'));
select is(pg_temp.paid(),12000.00::numeric,'Editing a payment leaves only the new amount');
select is((select count(*)::integer from public.v1_accounts_client_payments where invoice_id=pg_temp.inv() and lower(payment_reference)='p-1'),2,'The old entry stays in history and the same reference is reused');
select ok((public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),(select (v->>'invoice_record_version')::integer-1 from r where k='fix1'),(select (v->>'id')::uuid from r where k='p1'),date '2026-09-26','cash','P-1','12000.00','Amount typed wrong',(select (v->>'key')::uuid from r where k='fixkey'))->>'replayed')::boolean,'A retry of the same edit changes nothing');
select is(pg_temp.paid(),12000.00::numeric,'The retry did not double it');
select throws_ok($$select public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),(select (v->>'id')::uuid from r where k='p1'),date '2026-09-26','cash','P-X','1.00','Again',pg_temp.key())$$,'55000','R39_ACCOUNTS_PAYMENT_NOT_REVERSIBLE','An entry already replaced cannot be edited again');
select throws_ok($$select public.v1_record_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),date '2026-09-26','cash','p-1','1.00',null,pg_temp.key())$$,'23505','R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE','A reference in force still cannot be used twice');
select throws_ok($$select public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),(select (v->>'payment_id')::uuid from r where k='fix1'),date '2026-09-26','cash','P-1','52501.00','Too much',pg_temp.key())$$,'23514','R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED','An edit cannot exceed what is certified');
select throws_ok($$select public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),1,(select (v->>'payment_id')::uuid from r where k='fix1'),date '2026-09-26','cash','P-1','1.00','Stale',pg_temp.key())$$,'40001','R39_ACCOUNTS_VERSION_CONFLICT','A stale payment edit is refused');

-- ═══ Certification: edit, never below money received ════════════════════════
select throws_ok($$select public.v1_correct_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-2',date '2026-09-27','10000.00','Too low',pg_temp.key())$$,'23514','R39_ACCOUNTS_CERTIFICATION_BELOW_RECEIVED','A certification cannot drop below money received');
select throws_ok($$select public.v1_correct_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-2',date '2026-09-27','50001.00','Over',pg_temp.key())$$,'23514','R39_ACCOUNTS_CERTIFICATION_CAP_INVALID','A certification still cannot exceed the claim');
select public.v1_correct_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-2',date '2026-09-27','40000.00','Consultant cut it',pg_temp.key());
select is(public.v1_accounts_invoice_certified_ex_vat(pg_temp.inv()),40000.00::numeric,'A certification can be lowered');
select is((select status from public.v1_accounts_client_invoices where id=pg_temp.inv()),'partially_paid','The invoice status follows');
select throws_ok($$select public.v1_record_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-3',date '2026-09-27','30000.00','Lower',pg_temp.key())$$,'23514','R39_ACCOUNTS_CERTIFICATION_CAP_INVALID','The ordinary certify command still only goes up');

-- ═══ Invoice: cancel once everything on it has been undone ══════════════════
select throws_ok($$select public.v1_cancel_client_invoice('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'Wrong client',pg_temp.key())$$,'55000','R39_ACCOUNTS_INVOICE_HAS_DOWNSTREAM_FACTS','An invoice with money on it cannot be cancelled');
select public.v1_reverse_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),(select (v->>'payment_id')::uuid from r where k='fix1'),date '2026-09-28',null,'Undo',pg_temp.key());
select throws_ok($$select public.v1_cancel_client_invoice('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'Wrong client',pg_temp.key())$$,'55000','R39_ACCOUNTS_INVOICE_HAS_DOWNSTREAM_FACTS','Nor one that is still certified');
select public.v1_correct_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'CERT-0',date '2026-09-28','0.00','Certified in error',pg_temp.key());
select is(public.v1_accounts_invoice_certified_ex_vat(pg_temp.inv()),0.00::numeric,'A certification can be undone with zero');
select is((select status from public.v1_accounts_client_invoices where id=pg_temp.inv()),'submitted','The invoice is back to submitted');
select lives_ok($$select public.v1_cancel_client_invoice('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),pg_temp.iv(),'Wrong client',pg_temp.key())$$,'Once everything is undone the invoice can be cancelled');
select is((select count(*)::integer from public.v1_accounts_client_certifications where invoice_id=pg_temp.inv()),3,'Every certification stays in history');

-- ═══ Who may correct client money ═══════════════════════════════════════════
select pg_temp.act('se');
select throws_ok($$select public.v1_correct_client_certification('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),1,'X',date '2026-09-27','1.00','x',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Site Engineer cannot correct a certification');
select throws_ok($$select public.v1_update_client_pdc('39d1a000-0000-4000-8000-000000000001',pg_temp.pdc('CHQ-2'),1,'X',date '2026-09-27','1.00',null,'x',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Site Engineer cannot edit a cheque');
select pg_temp.act('pe');
select throws_ok($$select public.v1_correct_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),1,gen_random_uuid(),date '2026-09-27','cash','X','1.00','x',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Project Engineer cannot edit a payment');
select throws_ok($$select pg_temp.move('CHQ-2','expected','x')$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Project Engineer cannot move a cheque');
select pg_temp.act('procurement');
select throws_ok($$select public.v1_reverse_client_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.inv(),1,gen_random_uuid(),date '2026-09-27',null,'x',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Procurement cannot reverse a client payment');

-- ═══ Supplier bills ═════════════════════════════════════════════════════════
reset role;
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39d1a000-0000-4000-8000-000000000013','commercial','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39d1a000-0000-4000-8000-000000000014','39d1a000-0000-4000-8000-000000000013',1,'r39/v2c/s.pdf','s.pdf','application/pdf',128,repeat('f',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39d1a000-0000-4000-8000-000000000014' where id='39d1a000-0000-4000-8000-000000000013';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39d1a000-0000-4000-8000-000000000015','39d1a000-0000-4000-8000-000000000013','39d1a000-0000-4000-8000-000000000001','project','39d1a000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

select pg_temp.act('accountant');
insert into r select 'bill', public.v1_create_supplier_bill_draft('39d1a000-0000-4000-8000-000000000001',null,'Supplier Co','SUP-1',date '2026-09-01',date '2026-10-01','1000.00','5.0000',null,null,null,'39d1a000-0000-4000-8000-000000000013',null,null,pg_temp.key());
create function pg_temp.bill() returns uuid language sql as $$ select (v->>'supplier_bill_id')::uuid from r where k='bill'; $$;
create function pg_temp.bv() returns integer language sql as $$ select record_version from public.v1_accounts_supplier_bills where id=pg_temp.bill(); $$;
create function pg_temp.bpaid() returns numeric language sql as $$ select public.v1_accounts_supplier_paid_amount(pg_temp.bill()); $$;
select pg_temp.act('admin');
select public.v1_approve_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Evidence follows',pg_temp.key());
select public.v1_record_supplier_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),date '2026-09-10','bank_transfer','SP-1','500.00',null,'Evidence follows',pg_temp.key());
insert into r select 'sp1', jsonb_build_object('id',(select id from public.v1_accounts_supplier_payments where supplier_bill_id=pg_temp.bill() and payment_reference='SP-1'));

select pg_temp.act('accountant');
insert into r select 'sfix', public.v1_correct_supplier_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),(select (v->>'id')::uuid from r where k='sp1'),date '2026-09-11','cash','SP-1','600.00','Wrong amount',pg_temp.key());
select is(pg_temp.bpaid(),600.00::numeric,'Editing a supplier payment leaves only the new amount');
select throws_ok($$select public.v1_correct_supplier_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),(select (v->>'payment_id')::uuid from r where k='sfix'),date '2026-09-11','cash','SP-1','1050.01','Over',pg_temp.key())$$,'23514','R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED','An edit cannot exceed the bill');
select throws_ok($$select public.v1_correct_supplier_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),1,(select (v->>'payment_id')::uuid from r where k='sfix'),date '2026-09-11','cash','SP-1','1.00','Stale',pg_temp.key())$$,'40001','R39_ACCOUNTS_VERSION_CONFLICT','A stale supplier edit is refused');
select throws_ok($$select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Fix it',pg_temp.key())$$,'55000','R39_ACCOUNTS_SUPPLIER_BILL_HAS_PAYMENTS','A bill with money on it cannot be reopened');
select public.v1_reverse_supplier_payment('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),(select (v->>'payment_id')::uuid from r where k='sfix'),date '2026-09-12',null,'Undo',pg_temp.key());
select is(pg_temp.bpaid(),0.00::numeric,'A supplier reversal needs no reference typed');
select pg_temp.act('procurement');
select throws_ok($$select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Mine',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Without cost access Procurement cannot take back an approval');
select pg_temp.act('pe');
select throws_ok($$select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Mine',pg_temp.key())$$,'42501','R39_ACCOUNTS_ACCESS_DENIED','Project Engineer cannot reopen a bill');
select pg_temp.act('accountant');
select throws_ok($$select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),' ',pg_temp.key())$$,'22023','R39_ACCOUNTS_REASON_REQUIRED','Reopening needs a reason');
select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Wrong invoice date',pg_temp.key());
select is((select status from public.v1_accounts_supplier_bills where id=pg_temp.bill()),'draft','An approved bill can return to draft');
select is((select approved_at from public.v1_accounts_supplier_bills where id=pg_temp.bill()),null::timestamptz,'Its approval is cleared');
select throws_ok($$select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Again',pg_temp.key())$$,'55000','R39_ACCOUNTS_SUPPLIER_BILL_NOT_REOPENABLE','A draft is already open');
select public.v1_cancel_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Duplicate',pg_temp.key());
select public.v1_reopen_supplier_bill('39d1a000-0000-4000-8000-000000000001',pg_temp.bill(),pg_temp.bv(),'Not a duplicate',pg_temp.key());
select is((select status from public.v1_accounts_supplier_bills where id=pg_temp.bill()),'draft','A cancelled bill can be restored');
select is((select count(*)::integer from public.v1_accounts_supplier_payments where supplier_bill_id=pg_temp.bill()),4,'All the supplier entries stay in history');

-- ═══ Audit and grants ═══════════════════════════════════════════════════════
select ok(exists(select 1 from public.v1_audit_events where event_type='accounts.client_payment.corrected' and project_id='39d1a000-0000-4000-8000-000000000001'),'A payment edit is audited');
select ok(exists(select 1 from public.v1_audit_events where event_type='accounts.client_pdc.edited' and project_id='39d1a000-0000-4000-8000-000000000001'),'A cheque edit is audited');
select ok(exists(select 1 from public.v1_audit_events where event_type='accounts.client_certification.corrected' and project_id='39d1a000-0000-4000-8000-000000000001'),'A certification edit is audited');
select ok(exists(select 1 from public.v1_audit_events where event_type='accounts.supplier_bill.reopened' and project_id='39d1a000-0000-4000-8000-000000000001'),'Reopening a bill is audited');
select ok(not has_function_privilege('anon','public.v1_correct_client_payment(uuid,uuid,integer,uuid,date,text,text,text,text,uuid)','execute'),'Anonymous users cannot correct payments');
select ok(has_function_privilege('authenticated','public.v1_reverse_client_payment(uuid,uuid,integer,uuid,date,text,text,uuid,text)','execute'),'Signed-in users reach the reversal command');
select ok(not has_function_privilege('authenticated','public.v1_accounts_client_reversal_reference(uuid,text)','execute'),'The reference helper is internal');
select throws_ok($$update public.v1_accounts_client_payments set amount=1 where invoice_id=pg_temp.inv()$$,null,null,'Payment history stays append-only');

select finish();
rollback;

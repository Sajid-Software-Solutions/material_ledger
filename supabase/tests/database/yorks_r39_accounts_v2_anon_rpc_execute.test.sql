-- R39 Accounts Workspace V2 — anonymous EXECUTE removed from nine Accounts RPCs
--
-- 20261108120000_accounts_v2_revoke_anon_rpc_execute.sql revokes EXECUTE from
-- PUBLIC and anon on nine functions. This file proves:
--   1. anon (and PUBLIC) can no longer execute any of them, and no Accounts
--      function anon can execute is left in the catalogue;
--   2. authenticated and service_role keep EXECUTE;
--   3. Project Engineer, Site Engineer, Procurement, Admin and Accountant get
--      exactly the outcome they got before: each probe stops right after the
--      authorization gate, so an allowed role reaches the first input check
--      and a denied role gets R39_ACCOUNTS_ACCESS_DENIED, on a project they
--      belong to and on one they do not;
--   4. the full path still works for signed-in users, and the claim workbench
--      still hides money from a Site Engineer.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Project P: PE and SE are members. Project Q: nobody is a member.
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role) values
('39ac0000-0000-4000-8000-000000000001','R39-ANON-001','R39 anon execute','active','project_engineer','10000000-0000-4000-8000-000000000004','admin'),
('39ac0000-0000-4000-8000-000000000006','R39-ANON-002','R39 anon execute, no members','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39ac0000-0000-4000-8000-000000000002','39ac0000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role) values
('39ac0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','Anon execute test','10000000-0000-4000-8000-000000000004','admin'),
('39ac0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','Anon execute test','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39ac0000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39ac0000-0000-4000-8000-000000000004','39ac0000-0000-4000-8000-000000000003',1,'r39/anon/p.pdf','p.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39ac0000-0000-4000-8000-000000000004' where id='39ac0000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39ac0000-0000-4000-8000-000000000005','39ac0000-0000-4000-8000-000000000003','39ac0000-0000-4000-8000-000000000001','project','39ac0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

-- Sets the JWT claims for one of the five seeded actors.
create function pg_temp.act(p_who text) returns void language plpgsql as $$
declare v_id text; v_role text;
begin
  select id, role into strict v_id, v_role from (values
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

-- Runs one statement as the current role and reports 'ok' or 'SQLSTATE message'.
create function pg_temp.outcome(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;

-- The nine functions, by exact signature.
create temporary table v1_anon_fn(fn text primary key, signature text not null);
insert into v1_anon_fn values
('v1_save_project_commercial_setup','public.v1_save_project_commercial_setup(uuid,integer,jsonb,text,uuid)'),
('v1_get_claim_workbench','public.v1_get_claim_workbench(uuid,uuid)'),
('v1_reopen_client_claim','public.v1_reopen_client_claim(uuid,uuid,integer,text,uuid)'),
('v1_save_project_invoice_settings','public.v1_save_project_invoice_settings(uuid,text,text,uuid,text,integer,uuid)'),
('v1_issue_client_invoice','public.v1_issue_client_invoice(uuid,uuid,integer,text,date,date,uuid)'),
('v1_get_client_invoice_document','public.v1_get_client_invoice_document(uuid,uuid)'),
('v1_preview_client_invoice_document','public.v1_preview_client_invoice_document(uuid,uuid)'),
('v1_revise_client_invoice','public.v1_revise_client_invoice(uuid,uuid,integer,text,uuid)'),
('v1_save_claim_workbench','public.v1_save_claim_workbench(uuid,text,date,date,jsonb,uuid[],text,uuid)');

-- One probe per function. Every input is invalid in a way the function checks
-- only after its authorization gate, so the probe changes nothing and shows
-- who gets past the gate. :project is replaced per run.
create temporary table v1_anon_probe(fn text primary key references v1_anon_fn, call_sql text not null, past_gate text not null);
insert into v1_anon_probe values
('v1_save_project_commercial_setup',
  $q$select public.v1_save_project_commercial_setup(':project', null, null, 'probe', '39ac0000-0000-4000-8000-0000000000f1')$q$,
  '22023 R39_ACCOUNTS_SETUP_REQUIRED'),
('v1_get_claim_workbench',
  $q$select public.v1_get_claim_workbench(':project', null)$q$,
  'ok'),
('v1_reopen_client_claim',
  $q$select public.v1_reopen_client_claim(':project', '39ac0000-0000-4000-8000-0000000000ee', 1, ' ', '39ac0000-0000-4000-8000-0000000000f2')$q$,
  '22023 R39_ACCOUNTS_REASON_REQUIRED'),
('v1_save_project_invoice_settings',
  $q$select public.v1_save_project_invoice_settings(':project', ' ', null, null, null, null, '39ac0000-0000-4000-8000-0000000000f3')$q$,
  '22023 R39_ACCOUNTS_INVOICE_PREFIX_REQUIRED'),
('v1_issue_client_invoice',
  $q$select public.v1_issue_client_invoice(':project', '39ac0000-0000-4000-8000-0000000000ee', 1, null, null, null, '39ac0000-0000-4000-8000-0000000000f4')$q$,
  '22023 R39_ACCOUNTS_INVOICE_DATE_REQUIRED'),
('v1_get_client_invoice_document',
  $q$select public.v1_get_client_invoice_document(':project', '39ac0000-0000-4000-8000-0000000000ee')$q$,
  'P0002 R39_ACCOUNTS_INVOICE_DOCUMENT_NOT_FOUND'),
('v1_preview_client_invoice_document',
  $q$select public.v1_preview_client_invoice_document(':project', '39ac0000-0000-4000-8000-0000000000ee')$q$,
  'P0002 R39_ACCOUNTS_CLAIM_NOT_FOUND'),
('v1_revise_client_invoice',
  $q$select public.v1_revise_client_invoice(':project', '39ac0000-0000-4000-8000-0000000000ee', 1, ' ', '39ac0000-0000-4000-8000-0000000000f5')$q$,
  '22023 R39_ACCOUNTS_REASON_REQUIRED'),
('v1_save_claim_workbench',
  $q$select public.v1_save_claim_workbench(':project', null, null, null, '{}'::jsonb, null, 'probe', '39ac0000-0000-4000-8000-0000000000f6')$q$,
  '22023 R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY');

-- Who gets past each gate today. Project scope: P (member) or Q (no member).
-- Admin and Accountant are organization-wide; PE and SE need membership.
-- Note: v1_get_client_invoice_document checks only view_project_accounts, so a
-- Site Engineer member reaches the frozen invoice document. This file pins that
-- existing behavior; it does not approve it.
create temporary table v1_anon_expect(who text, project text, fn text references v1_anon_fn, allowed boolean not null,
  primary key (who, project, fn));
insert into v1_anon_expect
select w.who, p.project, f.fn, coalesce((
  select true from (values
    ('pe','P','v1_save_project_commercial_setup'),('pe','P','v1_get_claim_workbench'),
    ('pe','P','v1_reopen_client_claim'),('pe','P','v1_get_client_invoice_document'),
    ('pe','P','v1_preview_client_invoice_document'),('pe','P','v1_save_claim_workbench'),
    ('se','P','v1_get_claim_workbench'),('se','P','v1_get_client_invoice_document'),
    ('admin','*','v1_save_project_commercial_setup'),('admin','*','v1_get_claim_workbench'),
    ('admin','*','v1_reopen_client_claim'),('admin','*','v1_save_project_invoice_settings'),
    ('admin','*','v1_issue_client_invoice'),('admin','*','v1_get_client_invoice_document'),
    ('admin','*','v1_preview_client_invoice_document'),('admin','*','v1_revise_client_invoice'),
    ('accountant','*','v1_save_project_commercial_setup'),('accountant','*','v1_get_claim_workbench'),
    ('accountant','*','v1_save_project_invoice_settings'),('accountant','*','v1_issue_client_invoice'),
    ('accountant','*','v1_get_client_invoice_document'),('accountant','*','v1_preview_client_invoice_document'),
    ('accountant','*','v1_revise_client_invoice')
  ) as g(who, project, fn)
  where g.who = w.who and g.fn = f.fn and g.project in (p.project, '*')), false)
from (values ('pe'),('se'),('procurement'),('admin'),('accountant')) as w(who)
cross join (values ('P'),('Q')) as p(project)
cross join v1_anon_fn f;

create temporary table v1_anon_result(who text, project text, fn text, outcome text, primary key (who, project, fn));
grant select, insert on v1_anon_probe, v1_anon_result to authenticated, anon;

create function pg_temp.run_probes(p_who text, p_project text) returns void language plpgsql as $$
declare r record;
begin
  for r in select fn, call_sql from v1_anon_probe order by fn loop
    insert into v1_anon_result values (p_who, p_project, r.fn, pg_temp.outcome(replace(r.call_sql, ':project',
      case p_project when 'P' then '39ac0000-0000-4000-8000-000000000001' else '39ac0000-0000-4000-8000-000000000006' end)));
  end loop;
end;
$$;

-- ═══ 1. anon and PUBLIC ═════════════════════════════════════════════════════
select ok(not has_function_privilege('anon', signature, 'EXECUTE'), 'anon cannot execute ' || fn)
from v1_anon_fn order by fn;
select ok(not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
    where p.oid = f.signature::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE'),
  'PUBLIC holds no EXECUTE on ' || fn)
from v1_anon_fn f order by fn;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select pg_temp.run_probes('anon', 'P');
reset role;
select is(r.outcome, '42501 permission denied for function ' || r.fn, 'anon calling ' || r.fn || ' is refused by the grant')
from v1_anon_result r where r.who = 'anon' order by r.fn;

select is((
  select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'v1\_%'
    and (p.proname ~ '(accounts|claim|invoice|certification|pdc|supplier_bill)'
         or p.proname = 'v1_save_project_commercial_setup')
    and has_function_privilege('anon', p.oid, 'EXECUTE')),
  0, 'No Accounts function in public is executable by anon');

-- ═══ 2. authenticated and service_role keep EXECUTE ═════════════════════════
select ok(has_function_privilege('authenticated', signature, 'EXECUTE'), 'authenticated still executes ' || fn)
from v1_anon_fn order by fn;
select ok(has_function_privilege('service_role', signature, 'EXECUTE'), 'service_role still executes ' || fn)
from v1_anon_fn order by fn;

-- ═══ 3. The five roles get the same outcome as before ═══════════════════════
select pg_temp.act('pe');          set local role authenticated; select pg_temp.run_probes('pe','P');          select pg_temp.run_probes('pe','Q');          reset role;
select pg_temp.act('se');          set local role authenticated; select pg_temp.run_probes('se','P');          select pg_temp.run_probes('se','Q');          reset role;
select pg_temp.act('procurement'); set local role authenticated; select pg_temp.run_probes('procurement','P'); select pg_temp.run_probes('procurement','Q'); reset role;
select pg_temp.act('admin');       set local role authenticated; select pg_temp.run_probes('admin','P');       select pg_temp.run_probes('admin','Q');       reset role;
select pg_temp.act('accountant');  set local role authenticated; select pg_temp.run_probes('accountant','P');  select pg_temp.run_probes('accountant','Q');  reset role;

select is(r.outcome,
  case when e.allowed then p.past_gate else '42501 R39_ACCOUNTS_ACCESS_DENIED' end,
  format('%s on project %s (%s): %s %s', r.who, r.project,
    case r.project when 'P' then 'member' else 'not a member' end,
    r.fn, case when e.allowed then 'passes the gate' else 'is denied' end))
from v1_anon_result r
join v1_anon_expect e using (who, project, fn)
join v1_anon_probe p using (fn)
order by r.who, r.project, r.fn;
select is((select count(*)::integer from v1_anon_result where who <> 'anon'), 90, 'Every role, project and function was probed');

-- ═══ 4. The full path still works for signed-in users ═══════════════════════
create temporary table v1_anon_flow(result_key text primary key, payload jsonb not null);
grant select, insert on v1_anon_flow to authenticated;

select pg_temp.act('admin');
set local role authenticated;
insert into v1_anon_flow select 'setup', public.v1_save_project_commercial_setup('39ac0000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','39ac0000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','material_supply','stage_label','Material Supply','allocation_percent','50','position',2,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','30','position',3,'measurement_mode','percent'),
      jsonb_build_object('stage_key','commissioning_handover','stage_label','Commissioning and Handover','allocation_percent','5','position',4,'measurement_mode','percent'),
      jsonb_build_object('stage_key','energizing','stage_label','Energizing','allocation_percent','5','position',5,'measurement_mode','percent'))),
  'Setup','39ac0000-0000-4000-8000-000000000101');
reset role;

select pg_temp.act('accountant');
set local role authenticated;
insert into v1_anon_flow select 'settings', public.v1_save_project_invoice_settings('39ac0000-0000-4000-8000-000000000001','ANON',null,null,null,null,'39ac0000-0000-4000-8000-000000000102');
reset role;
insert into v1_anon_flow select 'pid_design', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39ac0000-0000-4000-8000-000000000001' and stage_key='design'));
insert into v1_anon_flow select 'pid_install', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='39ac0000-0000-4000-8000-000000000001' and stage_key='installation'));

-- PE confirms two stages and prepares two claims for Accounts.
select pg_temp.act('pe');
set local role authenticated;
select public.v1_confirm_billing_progress('39ac0000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_anon_flow where result_key='pid_design'),1,'100.0000','d',array['39ac0000-0000-4000-8000-000000000003'::uuid],'c','39ac0000-0000-4000-8000-000000000103');
select public.v1_confirm_billing_progress('39ac0000-0000-4000-8000-000000000001',(select (payload->>'id')::uuid from v1_anon_flow where result_key='pid_install'),1,'100.0000','i',array['39ac0000-0000-4000-8000-000000000003'::uuid],'c','39ac0000-0000-4000-8000-000000000104');
insert into v1_anon_flow select 'claimA', public.v1_create_client_claim_draft('39ac0000-0000-4000-8000-000000000001','CLM-ANON-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_anon_flow where result_key='pid_design'),'claimed_amount','50000.00','evidence_reference','V')),'a','39ac0000-0000-4000-8000-000000000105');
select public.v1_submit_client_claim_to_accounts('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimA'),1,'r','39ac0000-0000-4000-8000-000000000106');
insert into v1_anon_flow select 'claimB', public.v1_create_client_claim_draft('39ac0000-0000-4000-8000-000000000001','CLM-ANON-B',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'id')::uuid from v1_anon_flow where result_key='pid_install'),'claimed_amount','30000.00','evidence_reference','V')),'b','39ac0000-0000-4000-8000-000000000107');
select public.v1_submit_client_claim_to_accounts('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimB'),1,'r','39ac0000-0000-4000-8000-000000000108');
insert into v1_anon_flow select 'wb_pe', public.v1_get_claim_workbench('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimA'));
insert into v1_anon_flow select 'preview_pe', public.v1_preview_client_invoice_document('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimA'));
insert into v1_anon_flow select 'reopen_pe', public.v1_reopen_client_claim('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimB'),2,'Back to draft','39ac0000-0000-4000-8000-000000000109');
reset role;

select pg_temp.act('se');
set local role authenticated;
insert into v1_anon_flow select 'wb_se', public.v1_get_claim_workbench('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimA'));
reset role;

select pg_temp.act('accountant');
set local role authenticated;
insert into v1_anon_flow select 'issue', public.v1_issue_client_invoice('39ac0000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_anon_flow where result_key='claimA'),2,null,date '2026-08-26',date '2026-08-26','39ac0000-0000-4000-8000-00000000010a');
insert into v1_anon_flow select 'doc_accountant', public.v1_get_client_invoice_document('39ac0000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_anon_flow where result_key='issue'));
reset role;

select pg_temp.act('pe');
set local role authenticated;
insert into v1_anon_flow select 'doc_pe', public.v1_get_client_invoice_document('39ac0000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_anon_flow where result_key='issue'));
reset role;

select pg_temp.act('admin');
set local role authenticated;
insert into v1_anon_flow select 'revise', public.v1_revise_client_invoice('39ac0000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_anon_flow where result_key='issue'),2,'Client asked for a change','39ac0000-0000-4000-8000-00000000010b');
reset role;

select pg_temp.act('pe');
set local role authenticated;
insert into v1_anon_flow select 'save_wb', public.v1_save_claim_workbench('39ac0000-0000-4000-8000-000000000001','CLM-ANON-WB',date '2026-09-01',date '2026-09-25','[]'::jsonb,array[]::uuid[],'Workbench','39ac0000-0000-4000-8000-00000000010c');
reset role;

-- Procurement still cannot read the workbench, even with a baseline in place.
select pg_temp.act('procurement');
set local role authenticated;
select throws_ok($$select public.v1_get_claim_workbench('39ac0000-0000-4000-8000-000000000001', null)$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED','Procurement still cannot read the claim workbench');
reset role;

select ok((select payload ? 'baseline_revision_id' from v1_anon_flow where result_key='setup'),'Admin saves the commercial setup');
select is((select payload->>'invoice_prefix' from v1_anon_flow where result_key='settings'),'ANON','Accountant saves the invoice settings');
select is((select payload->'claim'->>'claimed_ex_vat' from v1_anon_flow where result_key='wb_pe'),'50000.00','Project Engineer reads the claim workbench with its money');
select is((select payload->'claim'->>'status' from v1_anon_flow where result_key='wb_se'),'ready_for_accounts','Site Engineer reads the claim workbench');
select ok((select not ((payload->'claim') ? 'claimed_ex_vat') and not ((payload->'claim') ? 'net_payable') from v1_anon_flow where result_key='wb_se'),
  'The claim workbench still hides the claim total and payable from a Site Engineer');
select is((select payload->'document'->'amounts'->>'ex_vat' from v1_anon_flow where result_key='preview_pe'),'50000.00','Project Engineer previews the invoice document');
select is((select payload->>'status' from v1_anon_flow where result_key='reopen_pe'),'draft','Project Engineer reopens a claim');
select is((select payload->>'invoice_reference' from v1_anon_flow where result_key='issue'),'ANON01','Accountant issues the invoice');
select is((select payload->'document'->'amounts'->>'ex_vat' from v1_anon_flow where result_key='doc_accountant'),'50000.00','Accountant opens the issued invoice document');
select is((select payload->'document'->'amounts'->>'ex_vat' from v1_anon_flow where result_key='doc_pe'),'50000.00','Project Engineer opens the issued invoice document');
select is((select payload->>'status' from v1_anon_flow where result_key='revise'),'draft','Admin revises the invoice into a successor draft claim');
select ok((select payload is not null and jsonb_typeof(payload) = 'object' from v1_anon_flow where result_key='save_wb'),'Project Engineer saves the claim workbench');

select finish();
rollback;

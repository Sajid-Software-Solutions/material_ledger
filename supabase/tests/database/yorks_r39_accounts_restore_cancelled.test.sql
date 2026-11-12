-- R39 Accounts — restore a cancelled invoice or a deleted claim (12 Nov 2026)
--
-- Positive: Admin and a Project Engineer member restore; the invoice returns
-- to its own status and number, its claim to invoiced, a deleted draft to
-- draft; the restore is audited and a retry replays. Negative: Procurement and
-- a Site Engineer member are denied; a stale version conflicts; a live record,
-- an invoiced claim, a second open claim, progress claimed again and a revised
-- contract are refused.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('3b120000-0000-4000-8000-000000000001','R39-RST-001','R39 restore','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('3b120000-0000-4000-8000-000000000002','3b120000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('3b120000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','restore','10000000-0000-4000-8000-000000000004','admin'),
      ('3b120000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','restore','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('3b120000-0000-4000-8000-000000000003','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('3b120000-0000-4000-8000-000000000004','3b120000-0000-4000-8000-000000000003',1,'r39/rst/p.pdf','p.pdf','application/pdf',128,repeat('d',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='3b120000-0000-4000-8000-000000000004' where id='3b120000-0000-4000-8000-000000000003';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('3b120000-0000-4000-8000-000000000005','3b120000-0000-4000-8000-000000000003','3b120000-0000-4000-8000-000000000001','project','3b120000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_rst(k text primary key, v jsonb not null);
grant select,insert,update on v1_rst to authenticated;

-- Contract: design stage 10% of 1,000,000 = 100,000 eligible at 100% progress.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('3b120000-0000-4000-8000-000000000001', null,
  jsonb_build_object('contract_value','1000000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','3b120000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','90','position',2,'measurement_mode','percent'))),
  'Setup','3b190000-0000-4000-8000-000000000001');
select public.v1_save_project_invoice_settings('3b120000-0000-4000-8000-000000000001','RST',null,null,null,null,'3b190000-0000-4000-8000-000000000002');
reset role;
insert into v1_rst select 'pid', jsonb_build_object('id',(select id from public.v1_accounts_billing_progress where project_id='3b120000-0000-4000-8000-000000000001' and stage_key='design'));

-- Claim A (50,000), checked and invoiced.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select public.v1_confirm_billing_progress('3b120000-0000-4000-8000-000000000001',(select (v->>'id')::uuid from v1_rst where k='pid'),1,'100.0000','d',array['3b120000-0000-4000-8000-000000000003'::uuid],'c','3b190000-0000-4000-8000-000000000003');
insert into v1_rst select 'a', public.v1_create_client_claim_draft('3b120000-0000-4000-8000-000000000001','CLM-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (v->>'id')::uuid from v1_rst where k='pid'),'claimed_amount','50000.00','evidence_reference','V')),'a','3b190000-0000-4000-8000-000000000004');
select public.v1_submit_client_claim_to_accounts('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='a'),1,'r','3b190000-0000-4000-8000-000000000005');
insert into v1_rst select 'inv', public.v1_issue_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='a'),2,null,date '2026-08-26',date '2026-08-26','3b190000-0000-4000-8000-000000000006');
reset role;
insert into v1_rst select 'ref', to_jsonb((select invoice_reference from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv')));
insert into v1_rst select 'iv', to_jsonb((select record_version from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv')));

-- Cancel the invoice (its claim is cancelled with it).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_cancel_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'Wrong period','3b190000-0000-4000-8000-000000000007');
reset role;
update v1_rst set v=to_jsonb((select record_version from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv'))) where k='iv';
select is((select status from public.v1_accounts_client_claims where id=(select (v->>'claim_id')::uuid from v1_rst where k='a')),'cancelled','Cancelling the invoice cancelled claim A');

-- Negative: Procurement and a Site Engineer member may not restore.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',true);
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'x','3b190000-0000-4000-8000-000000000010')$$,
  '42501',null,'Procurement cannot restore an invoice');
select throws_ok($$select public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='a'),1,'x','3b190000-0000-4000-8000-000000000011')$$,
  '42501',null,'Procurement cannot restore a claim');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'x','3b190000-0000-4000-8000-000000000012')$$,
  '42501',null,'A Site Engineer member cannot restore an invoice');
select throws_ok($$select public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='a'),1,'x','3b190000-0000-4000-8000-000000000013')$$,
  '42501',null,'A Site Engineer member cannot restore a claim');

-- The Project Engineer starts claim B (60,000) on the released progress.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_rst select 'b', public.v1_create_client_claim_draft('3b120000-0000-4000-8000-000000000001','CLM-B',date '2026-09-01',date '2026-09-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (v->>'id')::uuid from v1_rst where k='pid'),'claimed_amount','60000.00','evidence_reference','V')),'b','3b190000-0000-4000-8000-000000000014');

-- Stale version, then progress claimed again: both refused.
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),999,'x','3b190000-0000-4000-8000-000000000015')$$,
  '40001','R39_ACCOUNTS_VERSION_CONFLICT','A stale invoice version conflicts');
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'Mistake','3b190000-0000-4000-8000-000000000016')$$,
  '23514','R39_ACCOUNTS_CLAIM_CAP_EXCEEDED','Progress claimed again by claim B blocks the restore');

-- Delete claim B; the invoice now restores, for the Project Engineer.
select public.v1_cancel_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='b'),1,'Not needed','3b190000-0000-4000-8000-000000000017');
insert into v1_rst select 'restored', public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'Cancelled by mistake','3b190000-0000-4000-8000-000000000018');
insert into v1_rst select 'replay', public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'Cancelled by mistake','3b190000-0000-4000-8000-000000000018');
reset role;

select is((select v->>'status' from v1_rst where k='restored'),'submitted','The invoice returns to the status it had');
select is((select status from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv')),'submitted','The stored invoice is submitted again');
select is((select invoice_reference from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv')),(select v#>>'{}' from v1_rst where k='ref'),'The invoice keeps its own number');
select ok((select cancelled_at is null and cancellation_reason is null from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv')),'The cancellation fields are cleared on the invoice');
select is((select status from public.v1_accounts_client_claims where id=(select (v->>'claim_id')::uuid from v1_rst where k='a')),'invoiced','Claim A is invoiced again');
select is((select v->>'replayed' from v1_rst where k='replay'),'true','A retry with the same key replays');
select is((select count(*) from public.v1_audit_events where entity_id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv') and event_type='accounts.client_invoice.restored'),1::bigint,'The restore is audited once');
select is((select count(*) from public.v1_audit_events where entity_id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv') and event_type='accounts.client_invoice.cancelled'),1::bigint,'The cancellation stays in the audit trail');
select is((select reason from public.v1_audit_events where entity_id=(select (v->>'claim_id')::uuid from v1_rst where k='a') and event_type='accounts.client_claim.restored'),'Cancelled by mistake','The claim restore is audited with the reason');
update v1_rst set v=to_jsonb((select record_version from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv'))) where k='iv';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
-- A live invoice is not restorable; nor is claim B while A holds the progress.
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'x','3b190000-0000-4000-8000-000000000019')$$,
  '55000','R39_ACCOUNTS_INVOICE_NOT_RESTORABLE','A live invoice cannot be restored');
select throws_ok($$select public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='b'),2,'x','3b190000-0000-4000-8000-00000000001a')$$,
  '23514','R39_ACCOUNTS_CLAIM_CAP_EXCEEDED','A deleted claim whose progress was claimed again is refused');

-- Claim C (20,000) deleted, then D opened: C waits for D.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_rst select 'c', public.v1_create_client_claim_draft('3b120000-0000-4000-8000-000000000001','CLM-C',date '2026-10-01',date '2026-10-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (v->>'id')::uuid from v1_rst where k='pid'),'claimed_amount','20000.00','evidence_reference','V')),'c','3b190000-0000-4000-8000-00000000001b');
select public.v1_cancel_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='c'),1,'Oops','3b190000-0000-4000-8000-00000000001c');
insert into v1_rst select 'd', public.v1_create_client_claim_draft('3b120000-0000-4000-8000-000000000001','CLM-D',date '2026-10-01',date '2026-10-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (v->>'id')::uuid from v1_rst where k='pid'),'claimed_amount','10000.00','evidence_reference','V')),'d','3b190000-0000-4000-8000-00000000001d');
select throws_ok($$select public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='c'),2,'Oops','3b190000-0000-4000-8000-00000000001e')$$,
  '55000','R39_ACCOUNTS_OPEN_CLAIM_EXISTS','Only one claim may be open at a time');
select public.v1_cancel_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='d'),1,'Use C','3b190000-0000-4000-8000-00000000001f');
insert into v1_rst select 'c_restored', public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='c'),2,'Deleted by mistake','3b190000-0000-4000-8000-000000000020');
reset role;
select is((select v->>'status' from v1_rst where k='c_restored'),'draft','A deleted draft returns as a draft');
select is((select status from public.v1_accounts_client_claims where id=(select (v->>'claim_id')::uuid from v1_rst where k='c')),'draft','The stored claim is a draft again');
select ok((select cancelled_at is null from public.v1_accounts_client_claims where id=(select (v->>'claim_id')::uuid from v1_rst where k='c')),'The claim cancellation fields are cleared');

-- An invoiced claim comes back only with its invoice.
update v1_rst set v=to_jsonb((select record_version from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv'))) where k='iv';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_cancel_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='c'),3,'Clear the way','3b190000-0000-4000-8000-000000000021');
select public.v1_cancel_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'Again','3b190000-0000-4000-8000-000000000022');
reset role;
insert into v1_rst select 'av', to_jsonb((select record_version from public.v1_accounts_client_claims where id=(select (v->>'claim_id')::uuid from v1_rst where k='a')));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select throws_ok($$select public.v1_restore_client_claim('3b120000-0000-4000-8000-000000000001',(select (v->>'claim_id')::uuid from v1_rst where k='a'),(select (v#>>'{}')::int from v1_rst where k='av'),'x','3b190000-0000-4000-8000-000000000023')$$,
  '55000','R39_ACCOUNTS_CLAIM_NOT_RESTORABLE','An invoiced claim is restored with its invoice, not alone');

-- A revised contract: the cancelled invoice's figures are from the old one.
reset role;
update v1_rst set v=to_jsonb((select record_version from public.v1_accounts_client_invoices where id=(select (v->>'invoice_id')::uuid from v1_rst where k='inv'))) where k='iv';
insert into v1_rst select 'pv', to_jsonb((select record_version from public.v1_accounts_project_commercial_profiles where project_id='3b120000-0000-4000-8000-000000000001'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select public.v1_save_project_commercial_setup('3b120000-0000-4000-8000-000000000001', (select (v#>>'{}')::int from v1_rst where k='pv'),
  jsonb_build_object('contract_value','1200000.00','currency_code','AED','vat_rate_percent','5.0000',
    'buildings', jsonb_build_array(jsonb_build_object('building_scope_id','3b120000-0000-4000-8000-000000000002','allocation_percent','100')),
    'stages', jsonb_build_array(
      jsonb_build_object('stage_key','design','stage_label','Design','allocation_percent','10','position',1,'measurement_mode','percent'),
      jsonb_build_object('stage_key','installation','stage_label','Installation','allocation_percent','90','position',2,'measurement_mode','percent'))),
  'Variation','3b190000-0000-4000-8000-000000000024');
select throws_ok($$select public.v1_restore_client_invoice('3b120000-0000-4000-8000-000000000001',(select (v->>'invoice_id')::uuid from v1_rst where k='inv'),(select (v#>>'{}')::int from v1_rst where k='iv'),'x','3b190000-0000-4000-8000-000000000025')$$,
  '55000','R39_ACCOUNTS_RESTORE_CONTRACT_CHANGED','A restore after a contract revision is refused');
reset role;

select ok(not has_function_privilege('anon','public.v1_restore_client_invoice(uuid,uuid,integer,text,uuid)','execute'),'anon cannot call the invoice restore');
select ok(not has_function_privilege('authenticated','public.v1_accounts_restore_check_claim(uuid,uuid)','execute'),'The restore check is internal');

select * from finish();
rollback;

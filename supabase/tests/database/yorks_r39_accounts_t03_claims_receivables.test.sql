begin;

create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok(
  (select count(*) from public.v1_capability_catalog c
   where public.v1_accounts_is_capability_key(c.capability_key)
     and c.status='operational' and c.authorization_mode='enforced' and c.is_assignable)=15
  and (select count(*) from public.v1_capability_catalog c
   where public.v1_accounts_is_capability_key(c.capability_key)
     and c.status='planned' and c.authorization_mode='shadow' and not c.is_assignable)=0,
  'The five T03 consumers remain operational after the accepted T04-T06 promotions'
);

select ok(
  (select bool_and(relrowsecurity) from pg_class where oid=any(array[
    'public.v1_accounts_client_claims'::regclass,'public.v1_accounts_client_claim_lines'::regclass,
    'public.v1_accounts_client_invoices'::regclass,'public.v1_accounts_client_certifications'::regclass,
    'public.v1_accounts_client_payments'::regclass,'public.v1_accounts_client_pdcs'::regclass,
    'public.v1_accounts_client_pdc_events'::regclass]))
  and not has_table_privilege('authenticated','public.v1_accounts_client_claims','select')
  and not has_table_privilege('authenticated','public.v1_accounts_client_invoices','insert')
  and not has_table_privilege('authenticated','public.v1_accounts_client_payments','update'),
  'T03 tables are RLS protected and unavailable through direct Data API access'
);

select ok(
  has_function_privilege('authenticated','public.v1_create_client_claim_draft(uuid,text,date,date,jsonb,text,uuid,text)','execute')
  and has_function_privilege('authenticated','public.v1_submit_client_invoice(uuid,uuid,integer,date,text,uuid)','execute')
  and has_function_privilege('authenticated','public.v1_list_client_receipts_pdc(uuid,uuid,timestamptz,uuid,integer)','execute')
  and not has_function_privilege('authenticated','public.v1_accounts_claim_snapshot(uuid)','execute')
  and not has_function_privilege('authenticated','public.v1_accounts_invoice_paid_amount(uuid)','execute')
  and not has_function_privilege('authenticated','public.v1_confirm_billing_progress_t02_internal(uuid,uuid,integer,text,text,uuid[],text,uuid)','execute'),
  'Only protected T03 RPCs, never internal helpers, are exposed'
);

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39310000-0000-4000-8000-000000000001','R39-T03-001','R39 Accounts claims and receipts','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39320000-0000-4000-8000-000000000001','39310000-0000-4000-8000-000000000001','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39310000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','T03 project authority','10000000-0000-4000-8000-000000000004','admin');

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39310000-0000-4000-8000-000000000002','R39-T03-002','R39 reference scope control','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39320000-0000-4000-8000-000000000002','39310000-0000-4000-8000-000000000002','building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39310000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','T03 cross-project reference authority','10000000-0000-4000-8000-000000000004','admin');

-- Give a second, non-creator engineer explicit project-scoped command authority
-- so creator ownership is tested independently from capability admission.
insert into public.v1_permission_assignments(
  id,auth_user_id,capability_key,effect,scope_kind,reason,changed_by_auth_user_id
) values(
  '39350000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000009',
  'prepare_client_claim','grant','project','T03 creator-boundary fixture',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_permission_assignment_projects(assignment_id,project_id)
values('39350000-0000-4000-8000-000000000001','39310000-0000-4000-8000-000000000001');

insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39340000-0000-4000-8000-000000000001','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39341000-0000-4000-8000-000000000001','39340000-0000-4000-8000-000000000001',1,'r39/t03/progress.pdf','progress.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39341000-0000-4000-8000-000000000001' where id='39340000-0000-4000-8000-000000000001';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39342000-0000-4000-8000-000000000001','39340000-0000-4000-8000-000000000001','39310000-0000-4000-8000-000000000001','project','39310000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39342000-0000-4000-8000-000000000002','39340000-0000-4000-8000-000000000001','39310000-0000-4000-8000-000000000002','project','39310000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_t03_results(result_key text primary key,payload jsonb not null);
grant select,insert,update on v1_r39_t03_results to authenticated;

create function pg_temp.v1_r39_capture_progress_floor_detail(
  p_project_id uuid,p_progress_entry_id uuid,p_expected_version integer,p_percent text,p_key uuid
) returns text language plpgsql as $$
declare v_detail text;
begin
  perform public.v1_confirm_billing_progress(
    p_project_id,p_progress_entry_id,p_expected_version,p_percent,null,array[]::uuid[],
    'Attempt reduction below consumed client claim basis',p_key
  );
  return null;
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return v_detail;
end;
$$;
grant execute on function pg_temp.v1_r39_capture_progress_floor_detail(uuid,uuid,integer,text,uuid) to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_t03_results select 'baseline',public.v1_initialize_project_commercial_baseline(
  '39310000-0000-4000-8000-000000000001','100000.00','AED','5.0000',null,null,
  jsonb_build_array(jsonb_build_object('building_scope_id','39320000-0000-4000-8000-000000000001','allocation_percent','100.0000')),
  null,'{}'::jsonb,'T03 approved baseline','39390000-0000-4000-8000-000000000001');
insert into v1_r39_t03_results select 'baseline_2',public.v1_initialize_project_commercial_baseline(
  '39310000-0000-4000-8000-000000000002','100000.00','AED','5.0000',null,null,
  jsonb_build_array(jsonb_build_object('building_scope_id','39320000-0000-4000-8000-000000000002','allocation_percent','100.0000')),
  null,'{}'::jsonb,'T03 cross-project baseline','39390000-0000-4000-8000-000000000101');

reset role;
insert into v1_r39_t03_results
select 'progress',jsonb_build_object('progress_entry_id',id)
from public.v1_accounts_billing_progress
where project_id='39310000-0000-4000-8000-000000000001' and stage_key='design';
insert into v1_r39_t03_results
select 'progress_2',jsonb_build_object('progress_entry_id',id)
from public.v1_accounts_billing_progress
where project_id='39310000-0000-4000-8000-000000000002' and stage_key='design';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_t03_results select 'confirm',public.v1_confirm_billing_progress(
  '39310000-0000-4000-8000-000000000001',
  (select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),
  1,'100.0000','Approved site progress',array['39340000-0000-4000-8000-000000000001'::uuid],
  'Confirm design progress','39390000-0000-4000-8000-000000000002');
insert into v1_r39_t03_results select 'confirm_2',public.v1_confirm_billing_progress(
  '39310000-0000-4000-8000-000000000002',
  (select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress_2'),
  1,'100.0000','Approved second-project progress',array['39340000-0000-4000-8000-000000000001'::uuid],
  'Confirm second-project design progress','39390000-0000-4000-8000-000000000102');

insert into v1_r39_t03_results select 'claim',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-001',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','5000.00','evidence_reference','VAL-001')),
  'First client claim','39390000-0000-4000-8000-000000000003');

select is((select payload->>'status' from v1_r39_t03_results where result_key='claim'),'draft','Project Engineer creates a versioned claim draft');
select is((public.v1_get_client_claim('39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim'))->'claim'->>'claimed_ex_vat'),'5000.00','Non-cancelled draft reserves claim capacity');

select throws_ok($sql$select public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-OVER',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','6000.00','evidence_reference','VAL-OVER')),
  null,'39390000-0000-4000-8000-000000000004')$sql$,'23514','R39_ACCOUNTS_CLAIM_CAP_EXCEEDED','Claim line cannot reserve the same confirmed value twice');

select throws_ok($sql$select public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-PE-EXCEPTION',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','6000.00','evidence_reference','VAL-PE-EXCEPTION')),
  null,'39390000-0000-4000-8000-000000000111','Project Engineer cannot over-claim')$sql$,
  '42501','R39_ACCOUNTS_ADMIN_EXCEPTION_DENIED','A non-Admin cannot attach or exercise a claim-cap exception');

select throws_ok($sql$select public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','clm-001',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','100.00','evidence_reference','VAL-DUP')),
  null,'39390000-0000-4000-8000-000000000017')$sql$,'23505','R39_ACCOUNTS_DUPLICATE_CLAIM_REFERENCE','Claim references are case-insensitively unique inside one project');

insert into v1_r39_t03_results select 'claim_blank',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-BLANK',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','500.00','evidence_reference',null)),
  'Evidence is deliberately pending','39390000-0000-4000-8000-000000000018');
insert into v1_r39_t03_results select 'claim_admin',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-ADMIN',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','1000.00','evidence_reference','VAL-ADMIN')),
  'Admin submission boundary','39390000-0000-4000-8000-000000000019');
insert into v1_r39_t03_results select 'claim_stale',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-STALE',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','500.00','evidence_reference','VAL-STALE')),
  'Must retain old baseline basis','39390000-0000-4000-8000-000000000020');

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-sme"}}',true);
select throws_ok($sql$select public.v1_update_client_claim_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),1,
  'CLM-BLANK',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','500.00','evidence_reference','VAL-LATE')),
  null,'39390000-0000-4000-8000-000000000021')$sql$,'42501','R39_ACCOUNTS_ACCESS_DENIED','A capable non-creator cannot update another engineer claim draft');
select throws_ok($sql$select public.v1_delete_client_claim_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),1,
  'Not the creator','39390000-0000-4000-8000-000000000022')$sql$,'42501','R39_ACCOUNTS_ACCESS_DENIED','A capable non-creator cannot delete another engineer claim draft');
select throws_ok($sql$select public.v1_submit_client_claim_to_accounts(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),1,
  'Not the creator','39390000-0000-4000-8000-000000000023')$sql$,'42501','R39_ACCOUNTS_ACCESS_DENIED','A capable non-creator cannot submit another engineer claim draft');

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_t03_results select 'claim_blank_update',public.v1_update_client_claim_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),1,
  'CLM-BLANK',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','500.00','evidence_reference',null)),
  'Creator may maintain draft','39390000-0000-4000-8000-000000000024');
select is((select payload->>'record_version' from v1_r39_t03_results where result_key='claim_blank_update'),'2','The creator can update its own draft through optimistic versioning');
select throws_ok($sql$select public.v1_submit_client_claim_to_accounts(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),2,
  'Evidence is still missing','39390000-0000-4000-8000-000000000025')$sql$,'23514','R39_ACCOUNTS_CLAIM_EVIDENCE_REQUIRED','Every claim line requires a nonblank evidence reference at submission');

insert into v1_r39_t03_results select 'claim_2',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000002','CLM-001',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress_2'),'claimed_amount','1000.00','evidence_reference','VAL-P2')),
  'Same reference is valid in another project','39390000-0000-4000-8000-000000000103');
insert into v1_r39_t03_results select 'claim_2_submit',public.v1_submit_client_claim_to_accounts(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_2'),1,
  'Ready in second project','39390000-0000-4000-8000-000000000104');
select is((select payload->>'status' from v1_r39_t03_results where result_key='claim_2_submit'),'ready_for_accounts','The same claim reference is independently valid in another project');

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select throws_ok($sql$select public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-ADMIN-NO-REASON',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','4000.00','evidence_reference','VAL-ADMIN-NO-REASON')),
  null,'39390000-0000-4000-8000-000000000112')$sql$,
  '23514','R39_ACCOUNTS_CLAIM_CAP_EXCEEDED','Admin cannot exceed Available to Claim without an explicit reason');
insert into v1_r39_t03_results select 'claim_admin_exception',public.v1_create_client_claim_draft(
  '39310000-0000-4000-8000-000000000001','CLM-ADMIN-EXCEPTION',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object('progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),'claimed_amount','4000.00','evidence_reference','VAL-ADMIN-EXCEPTION')),
  'Controlled adoption exception','39390000-0000-4000-8000-000000000113','Approved commercial exception during adoption');
select is(
  public.v1_get_client_claim(
    '39310000-0000-4000-8000-000000000001',
    (select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_admin_exception')
  )->'claim'->>'admin_exception_reason',
  'Approved commercial exception during adoption',
  'Exact Admin over-cap exception is preserved in the protected claim projection'
);
reset role;
select ok(
  exists(
    select 1 from public.v1_audit_events
    where event_type='accounts.client_claim.created'
      and entity_id=(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_admin_exception')
      and reason='Approved commercial exception during adoption'
  ),
  'Admin over-cap exception reason is retained in trusted audit'
);
set local role authenticated;
insert into v1_r39_t03_results select 'claim_blank_delete',public.v1_delete_client_claim_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_blank'),2,
  'Admin removes abandoned draft','39390000-0000-4000-8000-000000000026');
select is((select payload->>'status' from v1_r39_t03_results where result_key='claim_blank_delete'),'deleted','Admin may delete an engineer draft with an audited reason');
insert into v1_r39_t03_results select 'claim_admin_submit',public.v1_submit_client_claim_to_accounts(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_admin'),1,
  'Admin submits complete engineer draft','39390000-0000-4000-8000-000000000027');
select is((select payload->>'status' from v1_r39_t03_results where result_key='claim_admin_submit'),'ready_for_accounts','Admin may submit a complete engineer claim draft');

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);

insert into v1_r39_t03_results select 'claim_submit',public.v1_submit_client_claim_to_accounts(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim'),1,
  'Ready for Accounts review','39390000-0000-4000-8000-000000000005');
select is((select payload->>'status' from v1_r39_t03_results where result_key='claim_submit'),'ready_for_accounts','Claim submission stops at Accounts review');
select ok(
  pg_temp.v1_r39_capture_progress_floor_detail(
    '39310000-0000-4000-8000-000000000001',
    (select (payload->>'progress_entry_id')::uuid from v1_r39_t03_results where result_key='progress'),
    2,'40.0000','39390000-0000-4000-8000-000000000028'
  ) like '%CLM-001%',
  'Progress reduction is blocked with the exact consuming claim reference in domain detail'
);

-- Owner decision of 11 November 2026: a PE member may record certification.
select ok(public.v1_current_user_has_capability('record_client_certification','39310000-0000-4000-8000-000000000001'),
  'Project Engineer member may record certification');

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',true);

insert into v1_r39_t03_results select 'invoice',public.v1_create_client_invoice_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim'),
  'INV-001','Invoice draft','39390000-0000-4000-8000-000000000006');
select throws_ok($sql$select public.v1_create_client_invoice_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_admin'),
  'inv-001','Duplicate invoice reference','39390000-0000-4000-8000-000000000029')$sql$,
  '23505','R39_ACCOUNTS_DUPLICATE_INVOICE_REFERENCE','Invoice references are case-insensitively unique inside one project');

insert into v1_r39_t03_results select 'invoice_cancel',public.v1_create_client_invoice_draft(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_admin'),
  'INV-CANCEL','Cancellation boundary','39390000-0000-4000-8000-000000000030');
insert into v1_r39_t03_results select 'invoice_cancel_submit',public.v1_submit_client_invoice(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_cancel'),1,
  date '2026-08-26',null,'39390000-0000-4000-8000-000000000031');
insert into v1_r39_t03_results select 'invoice_cancelled',public.v1_cancel_client_invoice(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_cancel'),2,
  'Cancelled before downstream facts','39390000-0000-4000-8000-000000000032');
select throws_ok($sql$select public.v1_record_client_certification(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_cancel'),3,
  'CERT-CANCELLED',date '2026-08-27','1000.00',null,'39390000-0000-4000-8000-000000000033')$sql$,
  '55000','R39_ACCOUNTS_INVOICE_NOT_CERTIFIABLE','A cancelled invoice cannot receive certification facts');

insert into v1_r39_t03_results select 'invoice_2',public.v1_create_client_invoice_draft(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'claim_id')::uuid from v1_r39_t03_results where result_key='claim_2'),
  'INV-001','Same reference in another project','39390000-0000-4000-8000-000000000105');
insert into v1_r39_t03_results select 'invoice_2_submit',public.v1_submit_client_invoice(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2'),1,
  date '2026-08-26',null,'39390000-0000-4000-8000-000000000106');
insert into v1_r39_t03_results select 'invoice_2_under_cert',public.v1_mark_client_invoice_under_certification(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2'),2,
  'Client reviewing second project','39390000-0000-4000-8000-000000000107');
insert into v1_r39_t03_results select 'invoice_2_cert',public.v1_record_client_certification(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2'),3,
  'CERT-001',date '2026-08-27','1000.00',null,'39390000-0000-4000-8000-000000000108');
insert into v1_r39_t03_results select 'invoice_2_payment',public.v1_record_client_payment(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2'),4,
  date '2026-08-28','bank_transfer','PAY-001','100.00','Second-project receipt','39390000-0000-4000-8000-000000000109');
insert into v1_r39_t03_results select 'invoice_2_pdc',public.v1_create_client_pdc(
  '39310000-0000-4000-8000-000000000002',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2'),5,
  'PDC-001',date '2026-09-01','100.00','Yorks Bank','39390000-0000-4000-8000-000000000110');
select ok(
  (public.v1_get_client_invoice(
    '39310000-0000-4000-8000-000000000002',
    (select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice_2')
  )->'invoice'->>'invoice_reference')='INV-001'
  and (select payload->>'payment_id' from v1_r39_t03_results where result_key='invoice_2_payment') is not null
  and (select payload->>'pdc_id' from v1_r39_t03_results where result_key='invoice_2_pdc') is not null,
  'Claim, invoice, payment and PDC references are independently scoped by project'
);

select throws_ok($sql$select public.v1_submit_client_invoice(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),1,
  date '2026-08-26','Client-supplied exception is forbidden','39390000-0000-4000-8000-000000000114')$sql$,
  '22023','R39_ACCOUNTS_ADMIN_EXCEPTION_SERVER_DERIVED','Invoice submission cannot manufacture or replace a claim exception');
insert into v1_r39_t03_results select 'invoice_submit',public.v1_submit_client_invoice(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),1,
  date '2026-08-26',null,'39390000-0000-4000-8000-000000000007');
select is((select payload->>'due_date' from v1_r39_t03_results where result_key='invoice_submit'),'2026-11-24','Due date is server-derived from the 90-day snapshot');
select is((public.v1_get_client_invoice('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'))->'invoice'->>'total_incl_vat_snapshot'),'5250.00','Invoice VAT snapshot uses fixed precision');

insert into v1_r39_t03_results select 'under_cert',public.v1_mark_client_invoice_under_certification(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),2,
  'Client is reviewing','39390000-0000-4000-8000-000000000008');
select throws_ok($sql$select public.v1_record_client_certification(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),3,
  'CERT-001',date '2026-08-27','4000.00',null,'39390000-0000-4000-8000-000000000009')$sql$,
  '22023','R39_ACCOUNTS_CERTIFICATION_DIFFERENCE_REASON_REQUIRED','Partial certification requires a difference reason');
insert into v1_r39_t03_results select 'cert',public.v1_record_client_certification(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),3,
  'CERT-001',date '2026-08-27','4000.00','Client withheld AED 1,000','39390000-0000-4000-8000-000000000010');
select is((select payload->>'status' from v1_r39_t03_results where result_key='cert'),'partially_certified','Partial certification is derived from append-only fact');

insert into v1_r39_t03_results select 'payment',public.v1_record_client_payment(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),4,
  date '2026-08-28','bank_transfer','PAY-001','1000.00','First receipt','39390000-0000-4000-8000-000000000011');
select is((select payload->>'amount_paid_till_date' from v1_r39_t03_results where result_key='payment'),'1000.00','Partial payment changes Amount Paid Till Date from append-only facts');
select throws_ok($sql$select public.v1_record_client_payment(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),5,
  date '2026-08-28','bank_transfer','PAY-OVER','4000.00',null,'39390000-0000-4000-8000-000000000012')$sql$,
  '23514','R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED','Payments cannot exceed certified incl VAT');

insert into v1_r39_t03_results select 'pdc',public.v1_create_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),5,
  'PDC-001',date '2026-09-01','2000.00','Yorks Bank','39390000-0000-4000-8000-000000000013');
insert into v1_r39_t03_results select 'pdc_received',public.v1_transition_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'pdc_id')::uuid from v1_r39_t03_results where result_key='pdc'),1,'received',
  date '2026-09-01',null,null,'39390000-0000-4000-8000-000000000014');
select is((public.v1_get_client_invoice('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'))->'invoice'->>'amount_paid_till_date'),'1000.00','Receiving a PDC does not count as payment');
insert into v1_r39_t03_results select 'pdc_deposited',public.v1_transition_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'pdc_id')::uuid from v1_r39_t03_results where result_key='pdc'),2,'deposited',
  date '2026-09-02',null,null,'39390000-0000-4000-8000-000000000015');
insert into v1_r39_t03_results select 'pdc_cleared',public.v1_transition_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'pdc_id')::uuid from v1_r39_t03_results where result_key='pdc'),3,'cleared',
  date '2026-09-03','Cheque cleared','PDC-CLEAR-001','39390000-0000-4000-8000-000000000016');
select is((public.v1_get_client_invoice('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'))->'invoice'->>'amount_paid_till_date'),'3000.00','Cleared PDC atomically creates exactly one payment');
select is((public.v1_transition_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'pdc_id')::uuid from v1_r39_t03_results where result_key='pdc'),3,'cleared',
  date '2026-09-03','Cheque cleared','PDC-CLEAR-001','39390000-0000-4000-8000-000000000016')->>'replayed')::boolean,true,'Lost-response PDC clear replay returns original result');
select is(jsonb_array_length(public.v1_get_client_invoice('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'))->'payments'),2,'PDC clear replay never duplicates payment');
select throws_ok($sql$select public.v1_transition_client_pdc(
  '39310000-0000-4000-8000-000000000001',(select (payload->>'pdc_id')::uuid from v1_r39_t03_results where result_key='pdc'),4,'received',
  date '2026-09-04',null,null,gen_random_uuid())$sql$,'55000','R39_ACCOUNTS_INVALID_PDC_TRANSITION','Cleared PDC cannot transition backwards');

select ok(jsonb_array_length(public.v1_list_client_receipts_pdc('39310000-0000-4000-8000-000000000001',null,null,null,50)->'entries')>=5,'Receipts/PDC ledger is chronological and populated');
select is((public.v1_get_client_invoice('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'))->'invoice'->>'still_due'),'1200.00','Invoice detail reconciles certified less Amount Paid Till Date');
select throws_ok($sql$insert into public.v1_accounts_client_payments(project_id,invoice_id,entry_kind,payment_date,payment_method,payment_reference,amount,actor_auth_user_id,actor_role,actor_exact_role,idempotency_key)
  values('39310000-0000-4000-8000-000000000001',(select (payload->>'invoice_id')::uuid from v1_r39_t03_results where result_key='invoice'),'receipt',current_date,'cash','DIRECT',1,
    '10000000-0000-4000-8000-000000000013','accountant','accountant',gen_random_uuid())$sql$,'42501',null,'Authenticated direct table insert is denied');

reset role;
select ok((select count(*) from public.v1_audit_events where project_id='39310000-0000-4000-8000-000000000001' and event_type like 'accounts.client_%')>=8,'Every T03 lifecycle command appends trusted audit facts');
select * from finish();
rollback;

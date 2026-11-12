begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

-- Use the real read resolvers and persisted domain records. These fixture
-- helpers only select an item from the public recipient-owned page; no
-- authorization or domain function is replaced.
create function pg_temp.record_context_item(p_type text,p_id uuid)
returns jsonb language sql as $$
 select item from jsonb_array_elements(public.v1_notification_page()->'records') item
 where item->>'entity_type'=p_type and item->>'entity_id'=p_id::text limit 1;
$$;
create function pg_temp.record_context_search(p_search text,p_type text,p_id uuid)
returns boolean language sql as $$
 select exists(select 1 from jsonb_array_elements(
   public.v1_notification_page(p_search=>p_search)->'records') item
   where item->>'entity_type'=p_type and item->>'entity_id'=p_id::text);
$$;
grant execute on function pg_temp.record_context_item(text,uuid),
 pg_temp.record_context_search(text,text,uuid) to authenticated;

select ok(not has_function_privilege('authenticated',
 'public.v1_notification_record_label(public.v1_notifications)','execute'),
 'Authenticated callers cannot execute the private record-label helper');
select ok(not has_function_privilege('anon',
 'public.v1_notification_record_label(public.v1_notifications)','execute'),
 'Anonymous callers cannot execute the private record-label helper');

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,
 created_by_auth_user_id,created_by_role)
values('ac110000-0000-4000-8000-000000000001','CTX-PROJECT-1',
 'Private project name excluded from notification context','active','project_engineer',
 '10000000-0000-4000-8000-000000000004','admin'),
 ('ac110000-0000-4000-8000-000000000002','CTX-OTHER-PROJECT',
 'Other project','active','project_engineer',
 '10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('ac120000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'building','b01','Building 01',false);
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,
 effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
select 'ac110000-0000-4000-8000-000000000001',
 ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 case i when 1 then 'project_engineer' else 'site_engineer' end,
 now()-interval '1 day','Notification context read scope',
 '10000000-0000-4000-8000-000000000004','admin'
from generate_series(1,2) i;
insert into public.v1_material_requests(id,project_id,scope_id,request_number,title,
 state,created_by_auth_user_id,requester_display_name,requester_project_role,
 current_action_owner_role,current_action_code,submitted_at)
values('ac130000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'ac120000-0000-4000-8000-000000000001','CTX-MR-321','Private material purpose',
 'closed','10000000-0000-4000-8000-000000000002','Local Site Engineer','site_engineer',
 'none','none',now()-interval '1 day');
insert into public.v1_material_returns(id,project_id,scope_id,return_number,state,
 drafted_by_auth_user_id,drafted_by_role,submitted_by_auth_user_id,
 submitted_by_role,submitted_at)
values('ac140000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'ac120000-0000-4000-8000-000000000001','CTX-RETURN-654','awaiting_approval',
 '10000000-0000-4000-8000-000000000002','site_engineer',
 '10000000-0000-4000-8000-000000000002','site_engineer',now());

insert into public.v1_company_material_request_categories(id,category_code,display_name)
values('ac150000-0000-4000-8000-000000000001','ctx','Context category');
insert into public.v1_company_material_request_units(id,unit_code,display_name)
values('ac150000-0000-4000-8000-000000000002','CTX','Context unit');
insert into public.v1_company_material_request_approval_routes(id,category_id,
 responsible_unit_id,primary_approver_auth_user_id,policy_version)
values('ac150000-0000-4000-8000-000000000003','ac150000-0000-4000-8000-000000000001',
 'ac150000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','ctx-v1');
insert into public.v1_company_material_requests(id,request_number,state,category_id,
 responsible_unit_id,purpose,delivery_collection_point,beneficiary_auth_user_id,
 beneficiary_display_name,authorized_receiver_auth_user_id,authorized_receiver_display_name,
 created_by_auth_user_id,requester_display_name,requester_exact_role,approval_route_id,
 approval_policy_version,approver_auth_user_id,approver_display_name,submitted_at)
values('ac160000-0000-4000-8000-000000000001','CTX-CMR-987','awaiting_company_approval',
 'ac150000-0000-4000-8000-000000000001','ac150000-0000-4000-8000-000000000002',
 'Private Company purpose excluded from notification context','Private collection point',
 '10000000-0000-4000-8000-000000000002','Local Site Engineer',
 '10000000-0000-4000-8000-000000000002','Local Site Engineer',
 '10000000-0000-4000-8000-000000000002','Local Site Engineer','site_engineer',
 'ac150000-0000-4000-8000-000000000003','ctx-v1',
 '10000000-0000-4000-8000-000000000001','Local Project Engineer',now());

-- Workforce has explicit read capability and dated responsibility. Merely
-- holding a Project/Site Engineer or Procurement role is insufficient.
insert into public.v1_workforce_internal_locations(id,location_code,location_name,
 department,is_active,created_by_auth_user_id,updated_by_auth_user_id)
values('ac210000-0000-4000-8000-000000000001','CTX','Context location','Workshop',true,
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_teams(id,team_code,team_name,valid_from,valid_to,
 is_active,created_by_auth_user_id,updated_by_auth_user_id)
values('ac220000-0000-4000-8000-000000000001','CTX-TEAM-89','Private team name',
 '2026-08-01','2026-08-31',true,
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_calendars(id,calendar_code,calendar_name,timezone_name,
 standard_scheduled_minutes,break_minutes,valid_from,valid_to,is_active,
 created_by_auth_user_id,updated_by_auth_user_id)
values('ac230000-0000-4000-8000-000000000001','CTX','Context calendar','Asia/Dubai',
 480,0,'2026-08-01','2026-08-31',true,
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_calendar_weekdays(calendar_id,iso_weekday,day_type,
 created_by_auth_user_id,updated_by_auth_user_id)
select 'ac230000-0000-4000-8000-000000000001',i,'regular_working_day',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'
from generate_series(1,7) i;
insert into public.v1_workforce_team_schedule_links(id,team_id,calendar_id,valid_from,
 valid_to,reason,created_by_auth_user_id,updated_by_auth_user_id)
values('ac240000-0000-4000-8000-000000000001','ac220000-0000-4000-8000-000000000001',
 'ac230000-0000-4000-8000-000000000001','2026-08-01','2026-08-31','Context schedule',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_workers(id,worker_number,full_name,designation,
 employer_company,worker_type,joining_date,current_status,
 created_by_auth_user_id,updated_by_auth_user_id)
values('ac250000-0000-4000-8000-000000000001','CTX-WORKER','Private worker name',
 'Technician','Yorks','yorks_employee','2026-08-01','active',
 '10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
insert into public.v1_workforce_worker_assignments(id,worker_id,assignment_kind,team_id,
 internal_location_id,valid_from,valid_to,reason,assigned_by_auth_user_id,
 assigned_by_exact_role,updated_by_auth_user_id)
values('ac260000-0000-4000-8000-000000000001','ac250000-0000-4000-8000-000000000001',
 'primary','ac220000-0000-4000-8000-000000000001','ac210000-0000-4000-8000-000000000001',
 '2026-08-01','2026-08-31','Context worker assignment',
 '10000000-0000-4000-8000-000000000004','admin','10000000-0000-4000-8000-000000000004');
insert into public.v1_permission_assignments(auth_user_id,capability_key,effect,
 scope_kind,effective_from,reason,changed_by_auth_user_id)
select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'workforce.view','grant','organization','2026-01-01','Context Workforce view',
 '10000000-0000-4000-8000-000000000004'
from generate_series(1,3) i;
insert into public.v1_workforce_responsibility_assignments(auth_user_id,scope_kind,
 valid_from,valid_to,reason,assigned_by_auth_user_id,assigned_by_exact_role,updated_by_auth_user_id)
select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'organization',
 '2026-08-01','2026-08-31','Context dated read responsibility',
 '10000000-0000-4000-8000-000000000004','admin','10000000-0000-4000-8000-000000000004'
from generate_series(1,4) i;
insert into public.v1_workforce_monthly_periods(id,team_id,period_month,
 created_by_auth_user_id,updated_by_auth_user_id)
values('ac270000-0000-4000-8000-000000000001','ac220000-0000-4000-8000-000000000001',
 '2026-08-01','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');

create temporary table context_targets(entity_type text,entity_id uuid,project_id uuid,
 event_code text,expected_label text,search_reference text);
insert into context_targets values
 ('material_request','ac130000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','material_request_approval_required',
 'CTX-PROJECT-1 · CTX-MR-321','CTX-MR-321'),
 ('material_return','ac140000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','material_return_approval_required',
 'CTX-PROJECT-1 · CTX-RETURN-654','CTX-RETURN-654'),
 ('company_material_request','ac160000-0000-4000-8000-000000000001',null,
 'company_material_request_approval_requested','CTX-CMR-987','CTX-CMR-987'),
 ('workforce_daily_roster','ac220000-0000-4000-8000-000000000001',null,
 'workforce_daily_attendance_missing','CTX-TEAM-89 · 2026-08-15','2026-08-15'),
 ('workforce_monthly_period','ac270000-0000-4000-8000-000000000001',null,
 'workforce_monthly_period_incomplete','CTX-TEAM-89 · 2026-08','2026-08');
grant select on context_targets to authenticated;
insert into public.v1_notifications(recipient_auth_user_id,event_code,entity_type,entity_id,
 project_id)
select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 t.event_code,t.entity_type,t.entity_id,t.project_id
from generate_series(1,4) i cross join context_targets t;
insert into public.v1_workforce_notification_digests(digest_kind,team_id,work_date,
 recipient_auth_user_id,item_count,notification_id,idempotency_key)
select 'daily_attendance_missing',n.entity_id,'2026-08-15',n.recipient_auth_user_id,
 1,n.id,gen_random_uuid() from public.v1_notifications n
where n.entity_type='workforce_daily_roster' and n.entity_id='ac220000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Project Engineer reads the protected reference for '||entity_type) from context_targets;
select ok(pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'Project Engineer searches the same safe identifier for '||entity_type) from context_targets;
select ok(not exists(select 1 from jsonb_array_elements(public.v1_notification_page()->'attention') item
 where item->>'entity_id'='ac130000-0000-4000-8000-000000000001'),
 'Closed MR approval history is no longer fresh attention');
select is(pg_temp.record_context_item('material_request','ac130000-0000-4000-8000-000000000001')->>'record_label',
 'CTX-PROJECT-1 · CTX-MR-321','Obsolete approval action keeps its authorized historical reference');

select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Site Engineer reads the protected reference for '||entity_type) from context_targets;
select ok(pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'Site Engineer searches the same safe identifier for '||entity_type) from context_targets;

select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Procurement reads the protected reference for '||entity_type)
from context_targets where entity_type<>'company_material_request';
select is(pg_temp.record_context_item('company_material_request','ac160000-0000-4000-8000-000000000001')->>'record_label',
 null::text,'Procurement cannot reveal a Company request pending approval');
select ok(not pg_temp.record_context_search('CTX-CMR-987','company_material_request',
 'ac160000-0000-4000-8000-000000000001'),'Denied Company reference cannot be used as a search oracle');

select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Admin reads the protected reference for '||entity_type) from context_targets;
select is(jsonb_array_length(public.v1_notification_page(p_search=>'Private')->'records'),0,
 'Search never reads project/purpose/worker/team private names');

-- Complete attendance using the app's real command. The old missing-attendance
-- alert stops being actionable but still has a readable date/team reference.
select lives_ok($$select public.v1_save_workforce_attendance_day(
 '{"worker_id":"ac250000-0000-4000-8000-000000000001","work_date":"2026-08-15","attendance_status":"present","regular_minutes":480,"overtime_minutes":0,"reason":"Context digest resolved"}',
 null,'ac280000-0000-4000-8000-000000000001')$$,
 'A real attendance command resolves the daily digest');
select is(pg_temp.record_context_item('workforce_daily_roster','ac220000-0000-4000-8000-000000000001')->>'record_label',
 'CTX-TEAM-89 · 2026-08-15','Completed digest keeps its team/date in durable history');
select ok(not exists(select 1 from jsonb_array_elements(public.v1_notification_page()->'attention') item
 where item->>'entity_type'='workforce_daily_roster'
 and item->>'entity_id'='ac220000-0000-4000-8000-000000000001'),
 'Completed digest reference does not revive obsolete attention');
reset role;

-- Accounts context is admitted through Accounts authority while the exact
-- Accountant role's technical project-view boundary remains denied.
-- The seed PE intentionally has legacy commercial visibility. Deny that
-- capability for this project to exercise a real non-commercial PE persona.
insert into public.v1_permission_assignments(id,auth_user_id,capability_key,effect,
 scope_kind,effective_from,reason,changed_by_auth_user_id)
values('ac300000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
 'view_project_commercial_values','deny','project','2026-01-01',
 'Context non-commercial Project Engineer','10000000-0000-4000-8000-000000000004');
insert into public.v1_permission_assignment_projects(assignment_id,project_id)
values('ac300000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select lives_ok($$select public.v1_initialize_project_commercial_baseline(
 'ac110000-0000-4000-8000-000000000001','100000.00','AED','5.0000',null,null,
 '[{"building_scope_id":"ac120000-0000-4000-8000-000000000001","allocation_percent":"100.0000"}]',
 null,'{}','Context baseline','ac310000-0000-4000-8000-000000000001')$$,
 'Accounts fixtures use a valid trusted commercial baseline');
reset role;
insert into public.v1_accounts_client_claims(id,project_id,baseline_revision_id,
 claim_reference,claim_period_start,claim_period_end,created_by_auth_user_id,
 created_by_role,created_by_exact_role,idempotency_key)
select 'ac320000-0000-4000-8000-000000000001',p.project_id,p.current_baseline_revision_id,
 'CTX-CLAIM-51','2026-08-01','2026-08-31','10000000-0000-4000-8000-000000000001',
 'project_engineer','project_engineer','ac390000-0000-4000-8000-000000000001'
from public.v1_accounts_project_commercial_profiles p
where p.project_id='ac110000-0000-4000-8000-000000000001';
insert into public.v1_accounts_client_invoices(id,project_id,claim_id,invoice_reference,
 claimed_ex_vat,vat_rate_percent_snapshot,vat_amount_snapshot,total_incl_vat_snapshot,
 payment_terms_days_snapshot,reminder_lead_days_snapshot,created_by_auth_user_id,
 created_by_role,created_by_exact_role,idempotency_key)
values('ac330000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'ac320000-0000-4000-8000-000000000001','CTX-INVOICE-52',1000,5,50,1050,90,10,
 '10000000-0000-4000-8000-000000000013','accountant','accountant',
 'ac390000-0000-4000-8000-000000000002');
insert into public.v1_accounts_client_certifications(id,project_id,invoice_id,
 revision_number,certification_reference,certification_date,certified_ex_vat,
 certified_vat,certified_incl_vat,actor_auth_user_id,actor_role,actor_exact_role,idempotency_key)
values('ac340000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'ac330000-0000-4000-8000-000000000001',1,'CTX-CERT-53','2026-08-31',1000,50,1050,
 '10000000-0000-4000-8000-000000000013','accountant','accountant',
 'ac390000-0000-4000-8000-000000000003');
insert into public.v1_accounts_client_pdcs(id,project_id,invoice_id,cheque_number,
 cheque_date,amount,bank_name,created_by_auth_user_id,created_by_role,
 created_by_exact_role,idempotency_key)
values('ac350000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'ac330000-0000-4000-8000-000000000001','CTX-CHEQUE-54','2026-12-01',1050,
 'Private bank name','10000000-0000-4000-8000-000000000013','accountant','accountant',
 'ac390000-0000-4000-8000-000000000004');
insert into public.v1_accounts_supplier_bills(id,project_id,supplier_name_snapshot,
 supplier_invoice_reference,invoice_date,due_date,ex_vat_amount,vat_rate_percent,
 vat_amount,total_incl_vat,created_by_auth_user_id,created_by_role,
 created_by_exact_role,idempotency_key)
values('ac360000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001',
 'Private supplier name','CTX-BILL-55','2026-08-31','2026-12-01',1000,5,50,1050,
 '10000000-0000-4000-8000-000000000013','accountant','accountant',
 'ac390000-0000-4000-8000-000000000005');
delete from context_targets;
insert into context_targets values
 ('accounts_client_claim','ac320000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','accounts_claim_ready',
 'CTX-PROJECT-1 · CTX-CLAIM-51','CTX-CLAIM-51'),
 ('accounts_client_invoice','ac330000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','accounts_invoice_overdue',
 'CTX-PROJECT-1 · CTX-INVOICE-52','CTX-INVOICE-52'),
 ('accounts_client_certification','ac340000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','accounts_certification_difference',
 'CTX-PROJECT-1 · CTX-INVOICE-52 · CTX-CERT-53','CTX-CERT-53'),
 ('accounts_client_pdc','ac350000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','accounts_pdc_overdue',
 'CTX-PROJECT-1 · CTX-INVOICE-52 · 2026-12-01 · 00000001','2026-12-01'),
 ('accounts_supplier_bill','ac360000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001','accounts_supplier_bill_ready',
 'CTX-PROJECT-1 · CTX-BILL-55','CTX-BILL-55');
insert into public.v1_notifications(recipient_auth_user_id,event_code,entity_type,entity_id,project_id)
select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 t.event_code,t.entity_type,t.entity_id,t.project_id
from unnest(array[1,2,3,4,13]) i cross join context_targets t;

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select ok(not public.v1_current_user_has_capability('projects.view',
 'ac110000-0000-4000-8000-000000000001'),'Accountant technical project access remains denied');
select ok(public.v1_current_user_has_capability('view_project_accounts',
 'ac110000-0000-4000-8000-000000000001'),'Accountant retains independent scoped Accounts authority');
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Accounts authority alone admits the controlled reference for '||entity_type) from context_targets;
select ok(pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'Accounts identifier is searchable without technical project view for '||entity_type) from context_targets;
select is(jsonb_array_length(public.v1_notification_page(p_search=>'Private')->'records'),0,
 'Accounts reference search never reads amounts, names or bank details');
select is(jsonb_array_length(public.v1_notification_page(p_search=>'CTX-CHEQUE-54')->'records'),0,
 'PDC context never exposes or searches the protected cheque number');

select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
-- This PE carries a per-user commercial-values denial, which still hides the
-- client references. Since the owner decision of 11 November 2026 a PE member
-- holds view_supplier_costs, so the supplier bill reference is admitted.
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',null::text,
 'A commercial-values denial still hides the Accounts reference for '||entity_type)
from context_targets where entity_type<>'accounts_supplier_bill';
select ok(not pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'A commercial-values denial still blocks searching the Accounts reference for '||entity_type)
from context_targets where entity_type<>'accounts_supplier_bill';
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Project Engineer member reads the supplier bill reference')
from context_targets where entity_type='accounts_supplier_bill';
select ok(pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'Project Engineer member can search the supplier bill reference')
from context_targets where entity_type='accounts_supplier_bill';
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',null::text,
 'Site Engineer cannot reveal restricted Accounts reference for '||entity_type) from context_targets;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',null::text,
 'Procurement receives no ungranted Accounts reference for '||entity_type)
from context_targets where entity_type<>'accounts_supplier_bill';
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',expected_label,
 'Admin receives authorized Accounts reference for '||entity_type) from context_targets;
reset role;

-- Deny commercial values separately from supplier costs. Row history remains
-- recipient-owned while both labels and search results update immediately.
insert into public.v1_permission_assignments(id,auth_user_id,capability_key,effect,
 scope_kind,effective_from,reason,changed_by_auth_user_id)
values('ac3a0000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000013',
 'view_project_commercial_values','deny','project','2026-01-01','Context commercial deny',
 '10000000-0000-4000-8000-000000000004');
insert into public.v1_permission_assignment_projects(assignment_id,project_id)
values('ac3a0000-0000-4000-8000-000000000001','ac110000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select is(pg_temp.record_context_item(entity_type,entity_id)->>'record_label',null::text,
 'Commercial capability denial removes '||entity_type||' context')
from context_targets where entity_type<>'accounts_supplier_bill';
select ok(not pg_temp.record_context_search(search_reference,entity_type,entity_id),
 'Revoked commercial reference cannot match search for '||entity_type)
from context_targets where entity_type<>'accounts_supplier_bill';
select ok(pg_temp.record_context_item('accounts_client_invoice',
 'ac330000-0000-4000-8000-000000000001') is not null,
 'Revocation keeps the original authoritative notification row');
select is(pg_temp.record_context_item('accounts_supplier_bill',
 'ac360000-0000-4000-8000-000000000001')->>'record_label',
 'CTX-PROJECT-1 · CTX-BILL-55','Independent supplier-cost authority remains intact');
reset role;
insert into public.v1_permission_assignments(id,auth_user_id,capability_key,effect,
 scope_kind,effective_from,reason,changed_by_auth_user_id)
values('ac3a0000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000013',
 'view_project_accounts','deny','project','2026-01-01','Context Accounts deny',
 '10000000-0000-4000-8000-000000000004');
insert into public.v1_permission_assignment_projects(assignment_id,project_id)
values('ac3a0000-0000-4000-8000-000000000002','ac110000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant"}}',true);
select is(pg_temp.record_context_item('accounts_supplier_bill',
 'ac360000-0000-4000-8000-000000000001')->>'record_label',null::text,
 'Accounts access denial removes supplier reference despite cost authority');
select ok(not pg_temp.record_context_search('CTX-BILL-55','accounts_supplier_bill',
 'ac360000-0000-4000-8000-000000000001'),'Denied Accounts access removes supplier reference search');
reset role;

update public.v1_project_members set effective_to=now()-interval '1 second',
 revoked_by_auth_user_id='10000000-0000-4000-8000-000000000004',
 revoked_by_role='admin',revoked_reason='Context revoked project membership'
where project_id='ac110000-0000-4000-8000-000000000001'
 and member_auth_user_id='10000000-0000-4000-8000-000000000001';
update public.v1_permission_assignments set effective_until=now()-interval '1 second'
where auth_user_id='10000000-0000-4000-8000-000000000001'
 and capability_key='workforce.view' and scope_kind='organization';
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select is(pg_temp.record_context_item('material_request','ac130000-0000-4000-8000-000000000001')->>'record_label',
 null::text,'Ended project membership removes MR reference');
select ok(not pg_temp.record_context_search('CTX-MR-321','material_request',
 'ac130000-0000-4000-8000-000000000001'),'Ended membership cannot search MR reference');
select is(pg_temp.record_context_item('material_return','ac140000-0000-4000-8000-000000000001')->>'record_label',
 null::text,'Ended project membership removes Return reference');
select is(pg_temp.record_context_item('workforce_daily_roster','ac220000-0000-4000-8000-000000000001')->>'record_label',
 null::text,'Expired Workforce view removes retained daily reference');
select is(pg_temp.record_context_item('workforce_monthly_period','ac270000-0000-4000-8000-000000000001')->>'record_label',
 null::text,'Expired Workforce view removes monthly reference');
select ok(not pg_temp.record_context_search('CTX-TEAM-89','workforce_daily_roster',
 'ac220000-0000-4000-8000-000000000001'),'Revoked daily reference is not a search oracle');
select ok(not pg_temp.record_context_search('2026-08','workforce_monthly_period',
 'ac270000-0000-4000-8000-000000000001'),'Revoked monthly date is not a search oracle');
reset role;

-- An absent target and a mismatched Accounts project fail closed. Do not delete
-- the historical notification or reveal a reference from a different project.
insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id,project_id)
values('ac410000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004',
 'material_request_submitted','material_request','ac420000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000001'),
 ('ac410000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004',
 'accounts_invoice_due_soon','accounts_client_invoice','ac330000-0000-4000-8000-000000000001',
 'ac110000-0000-4000-8000-000000000002');
select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select is(public.v1_notification_record_label(n),null::text,
 'Missing entity retains history with no fabricated project-only label')
from public.v1_notifications n where id='ac410000-0000-4000-8000-000000000001';
select is(public.v1_notification_record_label(n),null::text,
 'Notification project must match the Accounts record project')
from public.v1_notifications n where id='ac410000-0000-4000-8000-000000000002';
select is(public.v1_notification_record_label(n),null::text,
 'Private helper fails closed for another recipient even to a trusted internal caller')
from public.v1_notifications n where n.recipient_auth_user_id='10000000-0000-4000-8000-000000000002'
 and n.entity_type='company_material_request' and n.entity_id='ac160000-0000-4000-8000-000000000001';
update public.v1_profiles set is_active=false
where auth_user_id='10000000-0000-4000-8000-000000000004';
select is(public.v1_notification_record_label(n),null::text,
 'Private helper rejects inactive recipient context')
from public.v1_notifications n where n.recipient_auth_user_id='10000000-0000-4000-8000-000000000004'
 and n.entity_type='company_material_request' and n.entity_id='ac160000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.v1_notification_page()$$,'42501',
 'V1_NOTIFICATION_LIST_DENIED','Inactive recipient cannot load or search history');
reset role;
select set_config('request.jwt.claims','{}',true);
select is(public.v1_notification_record_label(n),null::text,
 'Private helper rejects an unauthenticated internal context')
from public.v1_notifications n where id='ac410000-0000-4000-8000-000000000001';
set local role anon;
select throws_ok($$select public.v1_notification_page()$$,'42501',null,
 'Anonymous notification reads remain denied');
reset role;
select * from finish();
rollback;

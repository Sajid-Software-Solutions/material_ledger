begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values
 ('a1500000-0000-4000-8000-000000000011','p0-workshop@yorks.local.test','{"role":"workshop_in_charge"}','{"full_name":"P0 Workshop"}'),
 ('a1500000-0000-4000-8000-000000000012','p0-document@yorks.local.test','{"role":"document_controller"}','{"full_name":"P0 Document"}');
insert into public.v1_projects(id,project_ref,name,state,created_by_auth_user_id,created_by_role)
select ('a1500000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'P0-PERMISSION-MAP-'||i,'Permission map fixture',
 case i when 2 then 'archived' else 'active' end,
 '10000000-0000-4000-8000-000000000001','project_engineer'
from generate_series(1,3) i;
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,assigned_by_auth_user_id,assigned_by_role,reason)
select 'a1500000-0000-4000-8000-000000000001', actor,
 case when actor='10000000-0000-4000-8000-000000000001' then 'project_engineer' else 'site_engineer' end,
 now()-interval '1 day','10000000-0000-4000-8000-000000000004','admin','P0 assigned team'
from unnest(array['10000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000002'::uuid]) actor;
-- Scoped explicit and legacy deny/grant precedence, plus expired assignments.
insert into public.v1_permission_assignments(auth_user_id,capability_key,effect,scope_kind,origin,effective_from,effective_until,reason)
values
 ('10000000-0000-4000-8000-000000000001','material_requests.approve','deny','organization','permission_management',now()-interval '1 day',null,'P0 parity explicit deny'),
 ('10000000-0000-4000-8000-000000000002','material_requests.approve','grant','organization','permission_management',now()-interval '1 day',null,'P0 parity explicit grant'),
 ('10000000-0000-4000-8000-000000000003','material_requests.view','deny','organization','legacy_app_user',now()-interval '1 day',now()-interval '1 hour','P0 parity expired deny');
-- Compare the exact existing resolver, not a handwritten role expectation.
create temporary table permission_cases as
select actor.id actor, actor.raw_app_meta_data->>'role' exact_role,
 project.id project_id, capability.key
from auth.users actor
cross join (select id from public.v1_projects where project_ref like 'P0-PERMISSION-MAP-%' union all select null::uuid) project
cross join unnest(array['material_requests.view','material_requests.edit',
 'material_requests.approve','material_requests.return_for_changes','procurement.arrange',
 'dispatch.create','receipts.confirm','material_requests.close']) capability(key)
where actor.raw_app_meta_data->>'role' in ('project_engineer','site_engineer','procurement','admin','senior_mechanical_engineer','project_manager','accountant','workshop_in_charge','document_controller');
select is(
 (public.v1_material_register_permission_map(actor,project_id,array['material_requests.view','material_requests.edit','material_requests.approve','material_requests.return_for_changes','procurement.arrange','dispatch.create','receipts.confirm','material_requests.close'])->>key)::boolean,
 (public.v1_permission_authoritative_resolution(actor,key,project_id)->>'effective')::boolean,
 'Current mode parity: '||exact_role||' '||coalesce(project_id::text,'organization')||' '||key)
from permission_cases;
-- Root shadow mode must retain the legacy dependency resolver semantics.
update public.v1_capability_catalog set authorization_mode='shadow'
where capability_key like 'material_requests.%' or capability_key in ('procurement.arrange','dispatch.create','receipts.confirm');
select is(
 (public.v1_material_register_permission_map(actor,project_id,array[key])->>key)::boolean,
 (public.v1_permission_authoritative_resolution(actor,key,project_id)->>'effective')::boolean,
 'Shadow mode parity: '||exact_role||' '||key)
from permission_cases;
update public.v1_capability_catalog set authorization_mode='enforced'
where capability_key like 'material_requests.%' or capability_key in ('procurement.arrange','dispatch.create','receipts.confirm');
-- A project grant overrides the same actor's organization deny only in that project.
insert into public.v1_permission_assignments(id,auth_user_id,capability_key,effect,scope_kind,effective_from,reason)
values('a1500000-0000-4000-8000-000000000099','10000000-0000-4000-8000-000000000001','material_requests.approve','grant','project',now()-interval '1 day','P0 project-specific grant');
insert into public.v1_permission_assignment_projects(assignment_id,project_id)
values('a1500000-0000-4000-8000-000000000099','a1500000-0000-4000-8000-000000000001');
select is(
 (public.v1_material_register_permission_map(actor,project_id,array[key])->>key)::boolean,
 (public.v1_permission_authoritative_resolution(actor,key,project_id)->>'effective')::boolean,
 'Project scope precedence parity: '||exact_role||' '||key)
from permission_cases where exact_role='project_engineer';
-- A dependency deny must still suppress all dependent actions.
insert into public.v1_permission_assignments(auth_user_id,capability_key,effect,scope_kind,effective_from,reason)
values('10000000-0000-4000-8000-000000000004','projects.view','deny','organization',now()-interval '1 day','P0 dependency denial');
select is(
 (public.v1_material_register_permission_map(actor,project_id,array['material_requests.view','material_requests.edit','material_requests.approve','material_requests.return_for_changes','procurement.arrange','dispatch.create','receipts.confirm','material_requests.close'])->>key)::boolean,
 (public.v1_permission_authoritative_resolution(actor,key,project_id)->>'effective')::boolean,
 'Dependency denial parity: '||exact_role||' '||key)
from permission_cases where exact_role='admin';
select ok(not has_function_privilege('authenticated','public.v1_material_register_permission_map(uuid,uuid,text[])','execute'),'Internal permission map cannot be called by authenticated clients');
select ok(not has_function_privilege('anon','public.v1_material_register_permission_map(uuid,uuid,text[])','execute'),'Internal permission map cannot be called anonymously');
select * from finish();
rollback;

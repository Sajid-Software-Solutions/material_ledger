begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
insert into public.v1_permission_assignments(auth_user_id,capability_key,effect,scope_kind,origin,effective_from,reason,changed_by_auth_user_id)
select u::uuid,c,'grant','organization','permission_management','2026-01-01','Team worker test','10000000-0000-4000-8000-000000000004'::uuid
from unnest(array['10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003']) u
cross join unnest(array['workforce.view','workforce.attendance.maintain']) c;
insert into public.v1_workforce_teams(id,team_code,team_name,default_supervisor_auth_user_id,valid_from,created_by_auth_user_id,updated_by_auth_user_id)
values('5afe0000-0000-4000-8000-000000000001','SELF-1','Own team','10000000-0000-4000-8000-000000000002','2026-01-01','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004'),
('5afe0000-0000-4000-8000-000000000002','SELF-2','Other team','10000000-0000-4000-8000-000000000003','2026-01-01','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');
select ok(not has_function_privilege('anon','public.v1_create_workforce_team_worker(uuid,jsonb,uuid)','execute'),'Anonymous cannot create workers');
select ok(not has_function_privilege('authenticated','public.v1_workforce_can_add_team_worker(uuid)','execute'),'Authority helper is private');
select ok(not has_table_privilege('authenticated','public.v1_workforce_workers','insert'),'No direct table creation');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select is(jsonb_array_length(public.v1_get_workforce_team_workers()->'teams'),1,'Site engineer sees only assigned team');
select throws_ok($$select public.v1_get_workforce_team_workers('5afe0000-0000-4000-8000-000000000002')$$,'42501','V1_WORKFORCE_TEAM_WORKER_DENIED','Other team read denied');
select throws_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000002','{}','5afe1000-0000-4000-8000-000000000001')$$,'42501','V1_WORKFORCE_TEAM_WORKER_DENIED','Other team mutation denied');
select is(
 public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{"full_name":"Test team worker","designation":"Technician","employer_company":"Test","joining_date":"2026-01-01","worker_type":"temporary_worker"}','5afe1000-0000-4000-8000-000000000002'),
 public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{"full_name":"Test team worker","designation":"Technician","employer_company":"Test","joining_date":"2026-01-01","worker_type":"temporary_worker"}','5afe1000-0000-4000-8000-000000000002'),
 'Identical retry returns same worker and assignment');
select is(jsonb_array_length(public.v1_get_workforce_team_workers('5afe0000-0000-4000-8000-000000000001')->'workers'),1,'Worker immediately appears in own team');
select throws_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{"full_name":"Incomplete"}','5afe1000-0000-4000-8000-000000000003')$$,'22023','V1_WORKFORCE_WORKER_REQUIRED_FIELDS','Incomplete identity cannot create half a worker');
select throws_ok($$select public.v1_save_workforce_worker('{}',null,'5afe1000-0000-4000-8000-000000000004')$$,'42501','V1_WORKFORCE_MANAGEMENT_REQUIRED','Team entry does not grant organization management');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select lives_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000002','{"full_name":"Warehouse test worker","designation":"Helper","employer_company":"Test","joining_date":"2026-01-01","worker_type":"yorks_employee"}','5afe1000-0000-4000-8000-000000000005')$$,'Warehouse recorder can add to assigned team');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select throws_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{}','5afe1000-0000-4000-8000-000000000006')$$,'42501','V1_WORKFORCE_TEAM_WORKER_DENIED','Engineer capability alone is insufficient without team assignment');
reset role;
update public.v1_workforce_teams set default_supervisor_auth_user_id='10000000-0000-4000-8000-000000000001' where id='5afe0000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{"full_name":"Engineer test worker","designation":"Helper","employer_company":"Test","joining_date":"2026-01-01","worker_type":"yorks_employee"}','5afe1000-0000-4000-8000-000000000007')$$,'Assigned project engineer can add');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select throws_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{}','5afe1000-0000-4000-8000-000000000008')$$,'42501','V1_WORKFORCE_TEAM_WORKER_DENIED','Former supervisor is denied immediately');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select lives_ok($$select public.v1_create_workforce_team_worker('5afe0000-0000-4000-8000-000000000001','{"full_name":"Admin test worker","designation":"Helper","employer_company":"Test","joining_date":"2026-01-01","worker_type":"yorks_employee"}','5afe1000-0000-4000-8000-000000000009')$$,'Admin retained authority');
reset role;
select is((select count(*) from public.v1_workforce_workers where full_name='Test team worker'),1::bigint,'Retry did not duplicate identity');
select is((select count(*) from public.v1_workforce_worker_assignments a join public.v1_workforce_workers w on w.id=a.worker_id where w.full_name='Test team worker'),1::bigint,'Retry did not duplicate assignment');
select * from finish();
rollback;

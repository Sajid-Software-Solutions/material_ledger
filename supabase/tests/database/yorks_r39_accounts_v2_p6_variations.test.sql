-- R39 Accounts Workspace V2 — P6 part e pgTAP: variations (VO) register

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39d17000-0000-4000-8000-000000000001','R39-V2P6V-001','R39 V2 variations','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39d17000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','x','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p6v(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p6v to authenticated;

-- Admin creates a variation, replays idempotently, lists, then edits it.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p6v select 'create', public.v1_save_accounts_variation('39d17000-0000-4000-8000-000000000001',null,'VO-01','Extra ductwork',45000.00,'pending',null,'39f90000-0000-4000-8000-0000000000d1');
insert into v1_r39_p6v select 'replay', public.v1_save_accounts_variation('39d17000-0000-4000-8000-000000000001',null,'VO-01','Extra ductwork',45000.00,'pending',null,'39f90000-0000-4000-8000-0000000000d1');
insert into v1_r39_p6v select 'list', public.v1_list_accounts_variations('39d17000-0000-4000-8000-000000000001');
insert into v1_r39_p6v select 'edit', public.v1_save_accounts_variation('39d17000-0000-4000-8000-000000000001',
  (select (payload->>'variation_id')::uuid from v1_r39_p6v where result_key='create'),
  'VO-01','Extra ductwork',45000.00,'approved',1,'39f90000-0000-4000-8000-0000000000d2');
select throws_ok(
  $$select public.v1_save_accounts_variation('39d17000-0000-4000-8000-000000000001',(select (payload->>'variation_id')::uuid from v1_r39_p6v where result_key='create'),'VO-01','x',1.0,'approved',999,'39f90000-0000-4000-8000-0000000000d3')$$,
  '40001','R39_ACCOUNTS_VERSION_CONFLICT','Editing a variation rejects a stale expected version');
reset role;

select is((select payload->>'record_version' from v1_r39_p6v where result_key='create'),'1','Created variation starts at version 1');
select is((select payload->>'replayed' from v1_r39_p6v where result_key='replay'),'true','Same idempotency key replays without a second insert');
select is((select jsonb_array_length((select payload from v1_r39_p6v where result_key='list')->'variations')),1,'Exactly one variation after an idempotent create');
select is((select v->>'amount' from jsonb_array_elements((select payload from v1_r39_p6v where result_key='list')->'variations') v where v->>'vo_number'='VO-01'),'45000.00','Variation amount carried through');
select is((select v->>'status' from jsonb_array_elements((select payload from v1_r39_p6v where result_key='list')->'variations') v where v->>'vo_number'='VO-01'),'pending','Variation status defaults to pending on create');
select is((select payload->>'record_version' from v1_r39_p6v where result_key='edit'),'2','Editing a variation bumps the version');

-- Role negative: a site engineer (no configure_project_commercials) cannot add.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select throws_ok(
  $$select public.v1_save_accounts_variation('39d17000-0000-4000-8000-000000000001',null,'VO-X','x',1.0,'pending',null,'39f90000-0000-4000-8000-0000000000d4')$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED','Site engineer without configure_project_commercials cannot add a variation');
reset role;

select finish();
rollback;

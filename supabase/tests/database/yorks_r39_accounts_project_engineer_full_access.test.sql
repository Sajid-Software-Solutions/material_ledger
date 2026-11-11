-- R39 Accounts — Project Engineer full commercial access (11 November 2026)
--
-- A Project Engineer with dated membership holds every Accounts capability on
-- that project, including supplier bills, supplier payments and supplier
-- costs. A Project Engineer without membership, a Site Engineer and
-- Procurement keep their previous, narrower access.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('3a110000-0000-4000-8000-000000000001','R39-PEFA-001','PE full access member','active','project_engineer','10000000-0000-4000-8000-000000000004','admin'),
      ('3a110000-0000-4000-8000-000000000002','R39-PEFA-002','PE full access outsider','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('3a110000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','PE full access','10000000-0000-4000-8000-000000000004','admin'),
      ('3a110000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','site_engineer',clock_timestamp()-interval '1 day','PE full access','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_pefa_keys(capability_key text primary key);
insert into v1_pefa_keys
select catalog.capability_key from public.v1_capability_catalog catalog
where public.v1_accounts_is_capability_key(catalog.capability_key);
grant select on v1_pefa_keys to authenticated;

select ok((select count(*) from v1_pefa_keys) >= 15, 'The Accounts key set is present');
select is(
  (select count(*) from public.v1_permission_role_defaults d
   join v1_pefa_keys k using (capability_key)
   where d.role_name = 'project_engineer' and d.is_granted and not d.can_delegate),
  (select count(*) from v1_pefa_keys),
  'Project Engineer holds every Accounts key by default, without delegation');

-- Project Engineer, member: every key.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select is(
  (select count(*) from v1_pefa_keys
   where public.v1_current_user_has_capability(capability_key, '3a110000-0000-4000-8000-000000000001')),
  (select count(*) from v1_pefa_keys),
  'Project Engineer member holds every Accounts capability on the project');
select ok(public.v1_current_user_has_capability('approve_supplier_bill_payment','3a110000-0000-4000-8000-000000000001'),
  'Project Engineer member may approve and pay supplier bills');
select ok(public.v1_current_user_has_capability('view_supplier_costs','3a110000-0000-4000-8000-000000000001'),
  'Project Engineer member sees supplier costs');
select lives_ok(
  $$select public.v1_list_supplier_bill_delivery_options('3a110000-0000-4000-8000-000000000001')$$,
  'Project Engineer member passes the supplier command role check');

-- Project Engineer, not a member: nothing.
select is(
  (select count(*) from v1_pefa_keys
   where public.v1_current_user_has_capability(capability_key, '3a110000-0000-4000-8000-000000000002')),
  0::bigint,
  'Project Engineer without membership holds no Accounts capability');
select throws_ok(
  $$select public.v1_list_supplier_bill_delivery_options('3a110000-0000-4000-8000-000000000002')$$,
  '42501', null,
  'Project Engineer without membership is denied supplier bills');

-- Site Engineer, member: unchanged.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-se"}}',true);
select ok(not public.v1_current_user_has_capability('manage_supplier_bills','3a110000-0000-4000-8000-000000000001'),
  'Site Engineer member gains no supplier bill access');
select ok(not public.v1_current_user_has_capability('view_project_commercial_values','3a110000-0000-4000-8000-000000000001'),
  'Site Engineer member gains no commercial values');
select throws_ok(
  $$select public.v1_list_supplier_bill_delivery_options('3a110000-0000-4000-8000-000000000001')$$,
  '42501', null,
  'Site Engineer member is denied supplier bills');

-- Procurement: unchanged.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',true);
select ok(not public.v1_current_user_has_capability('approve_supplier_bill_payment','3a110000-0000-4000-8000-000000000001'),
  'Procurement still cannot approve supplier bill payment');
select ok(not public.v1_current_user_has_capability('view_project_commercial_values','3a110000-0000-4000-8000-000000000001'),
  'Procurement still sees no project commercial values');

-- Admin: unchanged.
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
select ok(public.v1_current_user_has_capability('approve_supplier_bill_payment','3a110000-0000-4000-8000-000000000002'),
  'Admin keeps supplier bill approval on every project');

reset role;

-- Supplier commands and actor-role constraints admit Project Engineer.
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any(array[
       'v1_create_supplier_bill_draft','v1_update_supplier_bill_draft',
       'v1_cancel_supplier_bill','v1_approve_supplier_bill',
       'v1_reopen_supplier_bill','v1_record_supplier_payment',
       'v1_reverse_supplier_payment','v1_correct_supplier_payment',
       'v1_list_supplier_bill_delivery_options'])
     and position('''project_engineer''' in pg_get_functiondef(p.oid)) = 0),
  0::bigint,
  'Every supplier bill and payment command admits Project Engineer');
select is(
  (select count(*) from pg_constraint c
   join pg_class t on t.oid = c.conrelid
   join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname like 'v1\_accounts\_%' and c.contype = 'c'
     and pg_get_constraintdef(c.oid) like '%''accountant''::text%'
     and pg_get_constraintdef(c.oid) like '%''admin''::text%'
     and pg_get_constraintdef(c.oid) not like '%''project_engineer''::text%'
     and pg_get_constraintdef(c.oid) ~ '(role|exact_role)'),
  0::bigint,
  'No Accounts actor-role constraint excludes Project Engineer');

select * from finish();
rollback;

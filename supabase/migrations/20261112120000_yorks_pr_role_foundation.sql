-- Yorks PR role foundation (owner decision, 12 November 2026,
-- PRODUCT_DECISIONS.md section 37).
--
-- PR is the tenth exact platform role (claim `pr`, canonical `pr`). PR looks
-- after the company's people. It fully manages user accounts (as Senior
-- Mechanical Engineer does), worker records, Workforce, HR/leave and Rentals,
-- and reads every Project and its Accounts. Like Accountant, PR is never a
-- technical project member and can never hold a project, BOQ, Material
-- Request, dispatch, receipt, return, inventory or Accounts mutation
-- capability: a hard capability boundary enforces that in the resolver and
-- in the assignment guard.
--
-- Rentals write access arrives in the following migration, which replaces
-- the Admin-only rental guard with a capability check.
--
-- Data preservation: every change is additive or a strict-superset role
-- check. No row is rewritten or removed.
-- Rollback: stop assigning the PR role (no PR account exists before this
-- release), then fix forward. Never delete permission or actor history.

begin;

-- ---------------------------------------------------------------------------
-- 1. Identity: exact -> canonical, audit-safe role and profile mirror.
-- ---------------------------------------------------------------------------

create or replace function public.v1_canonical_role_from_exact_role(
  p_role text
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case p_role
    when 'project_engineer' then 'project_engineer'
    when 'site_engineer' then 'site_engineer'
    when 'senior_mechanical_engineer' then 'project_engineer'
    when 'project_manager' then 'project_engineer'
    when 'workshop_in_charge' then 'project_engineer'
    when 'document_controller' then 'project_engineer'
    when 'procurement' then 'procurement'
    when 'accountant' then 'accountant'
    when 'pr' then 'pr'
    when 'admin' then 'admin'
    else ''
  end;
$$;

create or replace function public.v1_safe_auth_audit_role(
  p_raw_app_meta_data jsonb
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case coalesce(p_raw_app_meta_data ->> 'role', '')
    when 'project_engineer' then 'project_engineer'
    when 'site_engineer' then 'site_engineer'
    when 'senior_mechanical_engineer' then 'senior_mechanical_engineer'
    when 'project_manager' then 'project_manager'
    when 'workshop_in_charge' then 'workshop_in_charge'
    when 'document_controller' then 'document_controller'
    when 'procurement' then 'procurement'
    when 'accountant' then 'accountant'
    when 'pr' then 'pr'
    when 'admin' then 'admin'
    when 'engineer' then 'engineer'
    else 'unrecognized'
  end;
$$;

-- Guarded function-body rewrite: the anchor must exist exactly as expected,
-- otherwise the migration stops instead of guessing. A body that already
-- carries the marker is left alone, so the script is repeatable.
create or replace function pg_temp.v1_pr_rewrite(
  p_function regprocedure,
  p_anchor text,
  p_replacement text,
  p_marker text
)
returns void
language plpgsql
as $$
declare
  v_definition text := pg_get_functiondef(p_function);
  v_updated text;
begin
  if position(p_marker in v_definition) > 0 then
    return;
  end if;
  v_updated := replace(v_definition, p_anchor, p_replacement);
  if v_updated = v_definition then
    raise exception 'V1_PR_ROLE_REWRITE_ANCHOR_MISSING: %', p_function;
  end if;
  execute v_updated;
end;
$$;

select pg_temp.v1_pr_rewrite(
  'public.v1_sync_profile_from_auth(uuid)'::regprocedure,
  'when ''accountant'' then ''accountant''',
  'when ''accountant'' then ''accountant''
    when ''pr'' then ''pr''',
  'when ''pr'' then ''pr'''
);

-- ---------------------------------------------------------------------------
-- 2. Role CHECK constraints: every actor/role list that admits Accountant
--    also admits PR. Accounts actor columns are excluded on purpose: PR
--    never writes an Accounts record.
-- ---------------------------------------------------------------------------

do $role_checks$
declare
  v_row record;
begin
  for v_row in
    select
      constraint_row.conrelid::regclass as table_name,
      constraint_row.conname,
      pg_get_constraintdef(constraint_row.oid) as definition
    from pg_constraint constraint_row
    join pg_class table_row on table_row.oid = constraint_row.conrelid
    join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and constraint_row.contype = 'c'
      and pg_get_constraintdef(constraint_row.oid)
        like '%''accountant''::text%'
      and pg_get_constraintdef(constraint_row.oid) not like '%''pr''::text%'
      and table_row.relname not like 'v1\_accounts\_%'
  loop
    execute format(
      'alter table %s drop constraint %I, add constraint %I %s',
      v_row.table_name,
      v_row.conname,
      v_row.conname,
      replace(
        v_row.definition,
        '''accountant''::text',
        '''accountant''::text, ''pr''::text'
      )
    );
  end loop;
end;
$role_checks$;

-- ---------------------------------------------------------------------------
-- 3. Capability boundary. PR may only ever hold these keys, whatever a
--    template or a per-person grant says.
-- ---------------------------------------------------------------------------

create or replace function public.v1_pr_may_hold_capability(
  p_capability_key text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_capability_key = any(array[
    -- User Management, as Senior Mechanical Engineer.
    'users.view', 'users.create', 'users.activation.manage',
    'users.password.reset', 'users.profile.edit', 'users.roles.assign',
    'permissions.view', 'permissions.manage', 'permissions.delegate',
    -- People: worker records, Workforce, HR and leave.
    'worker_records.view', 'worker_records.manage',
    'workforce.view', 'workforce.attendance.maintain',
    'workforce.timesheets.maintain', 'workforce.timesheets.review',
    'workforce.timesheets.correct_during_review',
    'workforce.timesheets.verify', 'workforce.timesheets.final_approve',
    'workforce.periods.reopen', 'workforce.reports.export',
    'workforce.workers.manage', 'workforce.teams.manage',
    'workforce.configuration.manage',
    'people.view', 'people.manage', 'people.salary.view',
    'leave.view_all', 'leave.manage',
    -- Rentals.
    'rentals.view', 'rentals.manage', 'rentals.import_export',
    'rentals.documents.manage',
    -- Read-only Projects.
    'projects.view', 'projects.view_all', 'boq.view', 'documents.view',
    -- Read-only Accounts.
    'view_project_accounts', 'view_project_commercial_values',
    'export_accounts_registers',
    -- Team chat.
    'chat.view', 'chat.send'
  ]::text[]);
$$;

revoke all on function public.v1_pr_may_hold_capability(text)
  from public, anon, authenticated;

select pg_temp.v1_pr_rewrite(
  'public.v1_permission_candidate_raw(uuid,text,uuid)'::regprocedure,
  '  if v_catalog.status <> ''operational'' then',
  '  if v_role = ''pr''
    and not public.v1_pr_may_hold_capability(p_capability_key) then
    return jsonb_build_object(''effective'', false, ''source'', ''hard_invariant'');
  end if;
  if v_catalog.status <> ''operational'' then',
  'v1_pr_may_hold_capability'
);

select pg_temp.v1_pr_rewrite(
  'public.v1_permission_legacy_raw(uuid,text,uuid)'::regprocedure,
  '  if v_catalog.status <> ''operational'' then',
  '  if v_role = ''pr''
    and not public.v1_pr_may_hold_capability(p_capability_key) then
    return jsonb_build_object(''effective'', false, ''source'', ''hard_invariant'');
  end if;
  if v_catalog.status <> ''operational'' then',
  'v1_pr_may_hold_capability'
);

select pg_temp.v1_pr_rewrite(
  'public.v1_permission_guard_assignment()'::regprocedure,
  '  if not v_catalog_found
    or new.scope_kind <> all(v_catalog.allowed_scope_kinds)',
  '  if v_target_role = ''pr''
    and new.effect = ''grant''
    and (
      not v_catalog_found
      or not public.v1_pr_may_hold_capability(new.capability_key)
    ) then
    raise exception ''V1_PR_CAPABILITY_DENIED''
      using errcode = ''42501'';
  end if;
  if not v_catalog_found
    or new.scope_kind <> all(v_catalog.allowed_scope_kinds)',
  'V1_PR_CAPABILITY_DENIED'
);

-- PR is never a technical project member, before or after a role change.
select pg_temp.v1_pr_rewrite(
  'public.v1_accounts_guard_technical_membership()'::regprocedure,
  ') = ''accountant'' then',
  ') in (''accountant'', ''pr'') then',
  '(''accountant'', ''pr'')'
);
select pg_temp.v1_pr_rewrite(
  'public.v1_accounts_guard_profile_role_change()'::regprocedure,
  'new.canonical_role_snapshot = ''accountant''',
  'new.canonical_role_snapshot in (''accountant'', ''pr'')',
  '(''accountant'', ''pr'')'
);

-- PR reads every project; its capability boundary keeps that read-only.
select pg_temp.v1_pr_rewrite(
  'public.v1_permission_has_project_access(uuid,uuid)'::regprocedure,
  '''workshop_in_charge'', ''document_controller''
  ) then',
  '''workshop_in_charge'', ''document_controller'', ''pr''
  ) then',
  '''document_controller'', ''pr'''
);

-- Read-only Accounts on every project.
select pg_temp.v1_pr_rewrite(
  'public.v1_accounts_has_project_scope(uuid,uuid,text)'::regprocedure,
  '  if v_exact_role = ''procurement'' then',
  '  if v_exact_role = ''pr'' then
    return p_capability_key in (
      ''view_project_accounts'', ''view_project_commercial_values'',
      ''export_accounts_registers''
    );
  end if;
  if v_exact_role = ''procurement'' then',
  'v_exact_role = ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_accounts_portfolio_role_allowed()'::regprocedure,
  '''admin'', ''accountant'',',
  '''admin'', ''accountant'', ''pr'',',
  '''accountant'', ''pr'''
);

-- ---------------------------------------------------------------------------
-- 4. User Management: PR operates the protected user gateway exactly as
--    Admin and Senior Mechanical Engineer do, and is itself a protected
--    manager-level target for everyone else.
-- ---------------------------------------------------------------------------

select pg_temp.v1_pr_rewrite(
  'public.v1_user_configuration_actor()'::regprocedure,
  '''admin'', ''senior_mechanical_engineer''',
  '''admin'', ''senior_mechanical_engineer'', ''pr''',
  '''senior_mechanical_engineer'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_auth_admin_actor_can_manage_role(uuid,text)'::regprocedure,
  '(''admin'', ''senior_mechanical_engineer'')',
  '(''admin'', ''senior_mechanical_engineer'', ''pr'')',
  '''senior_mechanical_engineer'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_auth_admin_actor_can_manage_role_strict(uuid,text)'::regprocedure,
  '(''admin'', ''senior_mechanical_engineer'')',
  '(''admin'', ''senior_mechanical_engineer'', ''pr'')',
  '''senior_mechanical_engineer'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_auth_users_admin_audit_trigger()'::regprocedure,
  'v_actor_exact_role not in (''admin'', ''senior_mechanical_engineer'')',
  'v_actor_exact_role not in (''admin'', ''senior_mechanical_engineer'', ''pr'')',
  '''senior_mechanical_engineer'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_permission_actor_can_assign_role_template(text)'::regprocedure,
  'v_actor_role in (''admin'', ''senior_mechanical_engineer'')',
  'v_actor_role in (''admin'', ''senior_mechanical_engineer'', ''pr'')',
  '''senior_mechanical_engineer'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_permission_protect_last_manager_auth()'::regprocedure,
  'v_new_role in (''admin'', ''senior_mechanical_engineer'')',
  'v_new_role in (''admin'', ''senior_mechanical_engineer'', ''pr'')',
  '''senior_mechanical_engineer'', ''pr'''
);

-- ---------------------------------------------------------------------------
-- 5. Full active-user lists.
-- ---------------------------------------------------------------------------

select pg_temp.v1_pr_rewrite(
  'public.v1_get_runtime_configuration()'::regprocedure,
  '''accountant'', ''senior_mechanical_engineer'',',
  '''accountant'', ''pr'', ''senior_mechanical_engineer'',',
  '''accountant'', ''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_company_material_request_active_authorization(uuid,uuid,uuid,text)'::regprocedure,
  '''admin'',''accountant'',',
  '''admin'',''accountant'',''pr'',',
  '''accountant'',''pr'''
);
select pg_temp.v1_pr_rewrite(
  'public.v1_provision_company_material_request_staff_authorizations(uuid)'::regprocedure,
  '''admin'',''accountant'',',
  '''admin'',''accountant'',''pr'',',
  '''accountant'',''pr'''
);

-- ---------------------------------------------------------------------------
-- 6. Role defaults: a row for every catalog key; grants only inside the PR
--    boundary (planned keys stay off through the catalog status). PR may
--    delegate what Senior Mechanical Engineer may delegate, plus the
--    people-facing keys it owns.
-- ---------------------------------------------------------------------------

insert into public.v1_role_capability_defaults (
  role_name, capability, is_enabled
)
values
  ('pr', 'view_commercials', false),
  ('pr', 'manage_commercials', false)
on conflict (role_name, capability) do nothing;

insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select
  'pr',
  catalog.capability_key,
  public.v1_pr_may_hold_capability(catalog.capability_key),
  public.v1_pr_may_hold_capability(catalog.capability_key)
    and (
      catalog.capability_key in (
        'worker_records.view', 'worker_records.manage',
        'workforce.view', 'workforce.attendance.maintain',
        'people.view', 'leave.view_all', 'rentals.view'
      )
      or coalesce((
        select sme.can_delegate
        from public.v1_permission_role_defaults sme
        where sme.role_name = 'senior_mechanical_engineer'
          and sme.capability_key = catalog.capability_key
      ), false)
    )
from public.v1_capability_catalog catalog
on conflict (role_name, capability_key) do nothing;

notify pgrst, 'reload schema';

commit;

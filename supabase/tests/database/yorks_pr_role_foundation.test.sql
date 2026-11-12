begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Fixed local personas: Admin ...0004, Site Engineer ...0002, PR ...0014.

-- Identity ----------------------------------------------------------------------

select is(
  public.v1_canonical_role_from_exact_role('pr'),
  'pr',
  'PR is its own canonical role, never folded into another'
);
select ok(public.v1_is_valid_role('pr'), 'PR is a valid exact role');
select is(
  public.v1_safe_auth_audit_role('{"role":"pr"}'::jsonb),
  'pr',
  'PR is audited by its exact name'
);
select is(
  (select canonical_role_snapshot from public.v1_profiles
   where auth_user_id = '10000000-0000-4000-8000-000000000014'),
  'pr',
  'The seeded PR profile mirrors the canonical PR role'
);

-- Role template ------------------------------------------------------------------

select is(
  (select count(*) from public.v1_permission_role_defaults
   where role_name = 'pr'),
  (select count(*) from public.v1_capability_catalog),
  'PR has an explicit default for every catalog capability'
);
select ok(
  not exists (
    select 1 from public.v1_permission_role_defaults
    where role_name = 'pr' and is_granted
      and not public.v1_pr_may_hold_capability(capability_key)
  ),
  'No PR default grant falls outside the PR boundary'
);
select ok(
  jsonb_path_exists(
    public.v1_get_user_admin_options(null) -> 'assignable_exact_roles',
    '$[*] ? (@ == "pr")'
  ) or exists (
    select 1
    from jsonb_array_elements(
      public.v1_get_user_admin_options(null) -> 'assignable_exact_roles'
    ) element
    where element ->> 'role' = 'pr' or element #>> '{}' = 'pr'
  ),
  'The Create user role picker offers PR'
);

-- Project fixture ----------------------------------------------------------------

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '3e010000-0000-4000-8000-000000000001', 'PR-T01-001',
  'PR role test project', 'active', 'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

-- Positive: what PR holds ------------------------------------------------------

select ok(
  (public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000014', capability_key, null
  ) ->> 'effective')::boolean,
  'PR holds ' || capability_key
)
from unnest(array[
  'users.view', 'users.create', 'users.roles.assign',
  'users.password.reset', 'users.activation.manage',
  'permissions.manage', 'worker_records.view', 'worker_records.manage',
  'workforce.view', 'workforce.attendance.maintain',
  'workforce.teams.manage', 'workforce.workers.manage',
  'rentals.view', 'rentals.manage', 'people.view', 'people.manage',
  'leave.manage', 'chat.view'
]::text[]) capability_key;

select ok(
  (public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000014', capability_key,
    '3e010000-0000-4000-8000-000000000001'
  ) ->> 'effective')::boolean,
  'PR reads the project through ' || capability_key
)
from unnest(array[
  'projects.view', 'boq.view', 'documents.view',
  'view_project_accounts', 'view_project_commercial_values',
  'export_accounts_registers'
]::text[]) capability_key;

select ok(
  public.v1_permission_has_project_access(
    '10000000-0000-4000-8000-000000000014',
    '3e010000-0000-4000-8000-000000000001'
  ),
  'PR sees every project without membership'
);
select ok(
  public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000014',
    '3e010000-0000-4000-8000-000000000001',
    'view_project_accounts'
  ),
  'PR has read-only Accounts scope on every project'
);

-- Negative: the hard boundary ------------------------------------------------

select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000014', capability_key,
    '3e010000-0000-4000-8000-000000000001'
  ) ->> 'source',
  'hard_invariant',
  'PR is hard-denied ' || capability_key
)
from unnest(array[
  'projects.edit', 'projects.manage_team', 'boq.edit', 'boq.import',
  'material_requests.create', 'material_requests.approve',
  'procurement.arrange', 'dispatch.create', 'receipts.confirm',
  'returns.create', 'returns.confirm', 'documents.upload',
  'manage_client_invoices', 'record_client_payment', 'manage_pdc',
  'manage_supplier_bills', 'view_supplier_costs',
  'configure_project_commercials', 'prepare_client_claim'
]::text[]) capability_key;

select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000014', capability_key, null
  ) ->> 'source',
  'hard_invariant',
  'PR is hard-denied ' || capability_key
)
from unnest(array[
  'inventory.items.manage', 'inventory.stock.adjust', 'inventory.view',
  'configuration.publish', 'audit.view', 'commercials.view',
  'projects.create'
]::text[]) capability_key;

select ok(
  not public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000014',
    '3e010000-0000-4000-8000-000000000001',
    'manage_client_invoices'
  ),
  'PR has no Accounts write scope'
);

select throws_ok(
  $$insert into public.v1_permission_assignments(
      id, auth_user_id, capability_key, effect, scope_kind, origin,
      effective_from, reason, changed_by_auth_user_id
    ) values (
      '3e200000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000014',
      'boq.edit', 'grant', 'organization', 'permission_management',
      '2026-08-01', 'Boundary test',
      '10000000-0000-4000-8000-000000000004'
    )$$,
  '42501', 'V1_PR_CAPABILITY_DENIED',
  'A per-person grant cannot give PR a technical capability'
);
select lives_ok(
  $$insert into public.v1_permission_assignments(
      id, auth_user_id, capability_key, effect, scope_kind, origin,
      effective_from, reason, changed_by_auth_user_id
    ) values (
      '3e200000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000014',
      'people.salary.view', 'deny', 'organization', 'permission_management',
      '2026-08-01', 'Boundary test',
      '10000000-0000-4000-8000-000000000004'
    )$$,
  'A deny inside the PR boundary is still accepted'
);

select throws_ok(
  $$insert into public.v1_project_members (
      project_id, member_auth_user_id, project_role, effective_from,
      reason, assigned_by_auth_user_id, assigned_by_role
    ) values (
      '3e010000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000014', 'project_engineer',
      clock_timestamp(), 'PR technical membership test',
      '10000000-0000-4000-8000-000000000004', 'admin'
    )$$,
  '42501', null,
  'PR can never become a technical project member'
);

-- User Management authority ------------------------------------------------

select ok(
  public.v1_auth_admin_actor_can_manage_role(
    '10000000-0000-4000-8000-000000000014', 'admin'
  ),
  'PR may assign any role, as Senior Mechanical Engineer can'
);
select ok(
  not public.v1_auth_admin_actor_can_manage_role(
    '10000000-0000-4000-8000-000000000002', 'pr'
  ),
  'A Site Engineer cannot create or change a PR account'
);
select ok(
  not (public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000002', 'users.view', null
  ) ->> 'effective')::boolean,
  'A Site Engineer still has no User Management'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000014","role":"authenticated","app_metadata":{"role":"pr","app_user_id":"usr-local-pr"}}',
  true
);
select ok(
  public.v1_user_configuration_actor(),
  'PR operates the protected user configuration gateway'
);
select ok(
  public.v1_accounts_portfolio_role_allowed(),
  'PR may open the read-only Accounts portfolio'
);
select is(
  public.v1_current_exact_role(),
  'pr',
  'The live claim resolves to the exact PR role'
);
select lives_ok(
  $$select public.v1_rental_assert_admin()$$,
  'PR passes the Rentals operator guard'
);
select ok(
  public.v1_get_rental_portfolio() is not null,
  'PR reads the rental portfolio'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  not public.v1_user_configuration_actor(),
  'A Site Engineer does not operate the user configuration gateway'
);
select throws_ok(
  $$select public.v1_rental_assert_admin()$$,
  '42501', 'V1_RENTAL_ADMIN_REQUIRED',
  'A Site Engineer is still refused Rentals'
);
reset role;

select * from finish();
rollback;

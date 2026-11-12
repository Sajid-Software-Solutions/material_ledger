begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select is(
  (select count(*) from public.v1_capability_catalog
   where capability_key in ('analytics.view', 'analytics.export')),
  2::bigint,
  'Analytics defines exactly the reviewed view and reserved export keys'
);

select ok(
  (select status = 'operational'
      and authorization_mode = 'enforced'
      and is_assignable
      and allowed_scope_kinds = array['organization']::text[]
   from public.v1_capability_catalog
   where capability_key = 'analytics.view'),
  'Analytics view is enforced, assignable and organization-scoped'
);

select ok(
  (select status = 'planned'
      and authorization_mode = 'shadow'
      and not is_assignable
   from public.v1_capability_catalog
   where capability_key = 'analytics.export'),
  'Analytics export remains planned, shadow and nonassignable'
);

select is(
  (select count(*) from public.v1_permission_role_defaults
   where capability_key in ('analytics.view', 'analytics.export')),
  20::bigint,
  'Every Analytics capability has one default for each exact role'
);

select ok(
  (select is_granted and can_delegate
   from public.v1_permission_role_defaults
   where role_name = 'admin' and capability_key = 'analytics.view')
  and not exists (
    select 1 from public.v1_permission_role_defaults
    where capability_key = 'analytics.view'
      and role_name <> 'admin'
      and (is_granted or can_delegate)
  ),
  'Only Admin receives the initial Analytics view ceiling'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_get_operational_analytics_foundation(uuid,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.v1_get_operational_analytics_foundation(uuid,integer)',
    'execute'
  ),
  'Only authenticated identities can invoke the protected projection'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '5a010000-0000-4000-8000-000000000001',
  'ANALYTICS-001', 'Analytics zero-state proof', 'active',
  'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '5a010000-0000-4000-8000-000000000002',
  'ANALYTICS-002', 'Analytics currency-boundary proof', 'active',
  'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

insert into public.v1_accounts_project_commercial_profiles (
  project_id, status, created_by_auth_user_id, created_by_role,
  created_by_exact_role
) values
  ('5a010000-0000-4000-8000-000000000001', 'active',
   '10000000-0000-4000-8000-000000000004', 'admin', 'admin'),
  ('5a010000-0000-4000-8000-000000000002', 'active',
   '10000000-0000-4000-8000-000000000004', 'admin', 'admin');

insert into public.v1_accounts_baseline_revisions (
  id, project_id, revision_number, status, contract_value, currency_code,
  vat_rate_percent, payment_terms_days, reminder_lead_days,
  management_review_policy, reason, approved_by_auth_user_id,
  approved_by_role, approved_by_exact_role, idempotency_key
) values
  ('5a030000-0000-4000-8000-000000000001',
   '5a010000-0000-4000-8000-000000000001', 1, 'current', 125000, 'AED',
   5, 30, 7, '{"mode":"fixture"}', 'Analytics AED proof',
   '10000000-0000-4000-8000-000000000004', 'admin', 'admin',
   '5a090000-0000-4000-8000-000000000001'),
  ('5a030000-0000-4000-8000-000000000002',
   '5a010000-0000-4000-8000-000000000002', 1, 'current', 90000, 'EUR',
   5, 30, 7, '{"mode":"fixture"}', 'Analytics EUR proof',
   '10000000-0000-4000-8000-000000000004', 'admin', 'admin',
   '5a090000-0000-4000-8000-000000000002');

update public.v1_accounts_project_commercial_profiles profile
set current_baseline_revision_id = case profile.project_id
  when '5a010000-0000-4000-8000-000000000001'::uuid
    then '5a030000-0000-4000-8000-000000000001'::uuid
  else '5a030000-0000-4000-8000-000000000002'::uuid end;

insert into public.v1_rental_properties (
  id, unit_code, property_name, property_type, location, occupancy_state,
  created_by_auth_user_id, updated_by_auth_user_id
) values (
  '5a040000-0000-4000-8000-000000000001', 'AN-R01',
  'Analytics aggregate rental', 'office', 'Abu Dhabi', 'vacant',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select public.v1_get_operational_analytics_foundation(null, 6)$$,
  '42501',
  'permission denied for function v1_get_operational_analytics_foundation',
  'Anonymous callers cannot execute Analytics'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_get_operational_analytics_foundation(null, 6)$$,
  '42501', 'YORKS_OPERATIONAL_ANALYTICS_DENIED',
  'A Project Engineer does not inherit Analytics from the technical role'
);

reset role;
insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, origin,
  reason, changed_by_auth_user_id
) values (
  '5a020000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  'analytics.view', 'grant', 'organization', 'permission_management',
  'Analytics delegation intersection proof',
  '10000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select lives_ok(
  $$select public.v1_get_operational_analytics_foundation(null, 3)$$,
  'An explicit organization grant opens Analytics for another active user'
);
select is(
  public.v1_get_operational_analytics_foundation(null, 3)
    #>> '{coverage,accounts,state}',
  'denied',
  'Delegated Analytics access does not grant Accounts authority'
);
select ok(
  not (
    public.v1_get_operational_analytics_foundation(null, 3)
      ?| array['accounts', 'workforce', 'rentals']
  ),
  'Delegated users receive no unavailable sensitive-domain payloads'
);
select throws_ok(
  $$select public.v1_get_operational_analytics_foundation(
      '5a010000-0000-4000-8000-000000000001', 3
    )$$,
  '42501', 'YORKS_OPERATIONAL_ANALYTICS_PROJECT_DENIED',
  'Analytics delegation does not bypass ordinary project readability'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select lives_ok(
  $$select public.v1_get_operational_analytics_foundation(null, 6)$$,
  'Admin can load the company Analytics projection'
);

select is(
  (public.v1_get_operational_analytics_foundation(null, 6)
    ->> 'schema_version')::integer,
  2,
  'The response has an explicit schema version'
);

select is(
  public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{coverage,projects,state}',
  'available',
  'Project metrics are marked available only with project read authority'
);

select is(
  public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{coverage,material_requests,state}',
  'available',
  'Material Request metrics are marked available only with request authority'
);

select is(
  public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{coverage,accounts,state}',
  'available',
  'Accounts is included only through its protected project-value authority'
);

select is(
  public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{coverage,rentals,state}',
  'available',
  'Exact Admin receives the accepted aggregate Rental projection'
);

select is(
  jsonb_array_length(
    public.v1_get_operational_analytics_foundation(null, 6)
      #> '{accounts,currency_groups}'
  ),
  2,
  'Accounts keeps independently confirmed currency groups separate'
);

select is(
  public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{accounts,currency_groups,0,currency_code}',
  'AED',
  'Account currency groups have stable ISO ordering'
);

select is(
  (public.v1_get_operational_analytics_foundation(null, 6)
    #>> '{rentals,total_properties}')::integer,
  1,
  'Rental portfolio counts come from the accepted Rental source'
);

select ok(
  (public.v1_get_operational_analytics_foundation(null, 6)
    ->> 'is_partial')::boolean,
  'Foundation remains visibly partial while domains are source-only'
);

select is(
  jsonb_array_length(
    public.v1_get_operational_analytics_foundation(null, 6)
      #> '{material_requests,monthly_flow}'
  ),
  6,
  'Monthly flow is bounded to the selected supported period'
);

select is(
  (
    with response as (
      select public.v1_get_operational_analytics_foundation(null, 6)
        -> 'material_requests' as value
    )
    select (value ->> 'total')::integer from response
  ),
  (
    with response as (
      select public.v1_get_operational_analytics_foundation(null, 6)
        -> 'material_requests' as value
    )
    select
      (value ->> 'drafts')::integer
      + (value ->> 'awaiting_engineering_approval')::integer
      + (value ->> 'to_arrange')::integer
      + (value ->> 'changes_requested')::integer
      + (value ->> 'dispatch_ready')::integer
      + (value ->> 'receipt_pending')::integer
      + (value ->> 'received')::integer
      + (value ->> 'closed')::integer
      + (value ->> 'cancelled')::integer
    from response
  ),
  'Material Request state buckets reconcile to the readable total'
);

select is(
  (public.v1_get_operational_analytics_foundation(
      '5a010000-0000-4000-8000-000000000001', 3
    ) #>> '{projects,total}')::integer,
  1,
  'A selected project returns exactly its readable project total'
);

select is(
  (public.v1_get_operational_analytics_foundation(
      '5a010000-0000-4000-8000-000000000001', 3
    ) #>> '{material_requests,total}')::integer,
  0,
  'A confirmed zero is returned when the selected project truly has no requests'
);

select is(
  public.v1_get_operational_analytics_foundation(
    '5a010000-0000-4000-8000-000000000001', 3
  ) #>> '{coverage,rentals,state}',
  'source_only',
  'A project filter does not reinterpret company Rentals as project data'
);

select ok(
  not (
    public.v1_get_operational_analytics_foundation(
      '5a010000-0000-4000-8000-000000000001', 3
    ) ?| array['workforce', 'rentals']
  ),
  'Project Analytics omits organization-only Workforce and Rental payloads'
);

select ok(
  not (
    public.v1_get_operational_analytics_foundation(null, 6)::text ~*
    '(unit_cost|total_cost|salary|tenant_name|contact_number|cheque_number|document_url)'
  ),
  'The company response contains no line cost, salary, tenant, cheque or document details'
);

select throws_ok(
  $$select public.v1_get_operational_analytics_foundation(null, 5)$$,
  '22023', 'YORKS_OPERATIONAL_ANALYTICS_MONTHS_INVALID',
  'Unsupported periods fail closed instead of changing query bounds'
);

select ok(
  not public.v1_current_user_has_capability('analytics.export', null),
  'Reserved Analytics export authority resolves false even for Admin'
);

select * from finish();
rollback;

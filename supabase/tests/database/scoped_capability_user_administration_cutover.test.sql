begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select ok(
  to_regprocedure(
    'public.v1_auth_admin_audit_capability_version()'
  ) is not null
  and (
    select public.v1_auth_admin_audit_capability_version() >= 3
  )
  and position(
    'v1_permission_authoritative_resolution' in pg_get_functiondef(
      'public.v1_auth_users_admin_audit_trigger()'::regprocedure
    )
  ) > 0,
  'User Administration is enforced only with the capability-aware Auth boundary'
);

select is(
  (
    select array_agg(catalog.capability_key order by catalog.capability_key)
    from public.v1_capability_catalog catalog
    where catalog.authorization_mode = 'enforced'
      and catalog.capability_key like any (array['users.%', 'permissions.%'])
  ),
  array[
    'permissions.delegate', 'permissions.manage', 'permissions.view',
    'users.activation.manage', 'users.create', 'users.password.reset',
    'users.roles.assign', 'users.view'
  ]::text[],
  'Only trusted User and Permission Management consumers are enforced'
);

select ok(
  (select authorization_mode = 'shadow'
   from public.v1_capability_catalog
   where capability_key = 'users.profile.edit')
  and (select status = 'planned' and not is_assignable
       from public.v1_capability_catalog
       where capability_key = 'users.delete'),
  'Unnormalized profile editing and retained-record deletion stay unavailable'
);

select ok(
  (select dependencies @> array['users.view', 'users.roles.assign']::text[]
   from public.v1_capability_catalog
   where capability_key = 'users.create')
  and (select dependencies @> array['users.view']::text[]
       from public.v1_capability_catalog
       where capability_key = 'permissions.view'),
  'Management actions retain their directory and role-assignment dependencies'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select ok(
  public.v1_current_user_has_capability('users.view', null)
  and public.v1_current_user_has_capability('users.create', null)
  and public.v1_current_user_has_capability('permissions.manage', null),
  'Exact Admin keeps its complete established management surface'
);

select ok(
  public.v1_current_user_can_assign_exact_role(
    'usr-local-site-engineer', 'procurement'
  )
  and public.v1_current_user_can_assign_new_exact_role('procurement')
  and not public.v1_current_user_can_assign_exact_role(
    'usr-local-admin', 'procurement'
  ),
  'Admin role assignment is target-aware and rejects self mutation'
);

select ok(
  jsonb_array_length(
    public.v1_get_user_admin_options(null)
      -> 'assignable_exact_roles'
  ) = 10
  and (public.v1_get_user_admin_options(null)
    ->> 'can_assign_role')::boolean
  and not (public.v1_get_user_admin_options(null)
    ->> 'can_reset_password')::boolean
  and not (public.v1_get_user_admin_options(null)
    ->> 'can_manage_activation')::boolean,
  'Create mode projects all ten Admin-assignable exact roles and no target actions'
);

select ok(
  jsonb_array_length(
    public.v1_get_user_admin_options('usr-local-site-engineer')
      -> 'assignable_exact_roles'
  ) = 10
  and (public.v1_get_user_admin_options('usr-local-site-engineer')
    ->> 'can_reset_password')::boolean
  and (public.v1_get_user_admin_options('usr-local-site-engineer')
    ->> 'can_manage_activation')::boolean
  and jsonb_array_length(
    public.v1_get_user_admin_options('usr-local-admin')
      -> 'assignable_exact_roles'
  ) = 0
  and not (public.v1_get_user_admin_options('usr-local-admin')
    ->> 'can_reset_password')::boolean
  and not (public.v1_get_user_admin_options('usr-local-admin')
    ->> 'can_manage_activation')::boolean,
  'Existing-target options are action-specific and every self action fails closed'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);

select ok(
  public.v1_current_user_has_capability('users.roles.assign', null)
  and public.v1_current_user_has_capability('permissions.manage', null)
  and public.v1_current_user_can_assign_new_exact_role('admin'),
  'Senior Mechanical Engineer retains existing audited User Management authority'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  not public.v1_current_user_has_capability('users.view', null)
  and not public.v1_current_user_has_capability('permissions.view', null)
  and not public.v1_current_user_can_assign_new_exact_role('site_engineer'),
  'An ordinary user receives no management access from route knowledge or RPC execution'
);

select throws_ok(
  $$select public.v1_get_user_admin_options('usr-local-procurement')$$,
  '42501', 'V1_USER_ADMIN_OPTIONS_ACCESS_DENIED',
  'An actor without live users.roles.assign cannot enumerate role or action options'
);

reset role;
update auth.users auth_user
set raw_app_meta_data = jsonb_set(
  auth_user.raw_app_meta_data,
  '{caps}',
  (
    select jsonb_agg(
      case value when 'viewCommercials' then 'cost' else value end
      order by ordinal
    )
    from jsonb_array_elements_text(
      public.v1_auth_expected_server_caps(
        auth_user.raw_app_meta_data ->> 'role'
      )
    ) with ordinality as capability(value, ordinal)
  ),
  true
)
where id = '10000000-0000-4000-8000-000000000004'::uuid;

select ok(
  (public.v1_auth_claim_compatibility_report() -> 'mismatches')::text
    not like '%usr-local-admin%',
  'Historical cost claim remains semantically equivalent to viewCommercials during zero-surprise cutover'
);

update auth.users auth_user
set raw_app_meta_data = jsonb_set(
  auth_user.raw_app_meta_data,
  '{caps}',
  public.v1_auth_expected_server_caps(
    auth_user.raw_app_meta_data ->> 'role'
  ),
  true
)
where id = '10000000-0000-4000-8000-000000000004'::uuid;

update auth.users
set raw_app_meta_data = jsonb_set(
  jsonb_set(
    raw_app_meta_data,
    '{caps}',
    case id
      when '10000000-0000-4000-8000-000000000002'::uuid
        then '["unexpected_legacy_cap"]'::jsonb
      when '10000000-0000-4000-8000-000000000004'::uuid
        then '["salary"]'::jsonb
      else raw_app_meta_data -> 'caps'
    end,
    true
  ),
  '{roles}',
  case id
    when '10000000-0000-4000-8000-000000000002'::uuid
      then '["site_engineer", "admin"]'::jsonb
    else coalesce(raw_app_meta_data -> 'roles', '[]'::jsonb)
  end,
  true
)
where id in (
  '10000000-0000-4000-8000-000000000002'::uuid,
  '10000000-0000-4000-8000-000000000004'::uuid
);

select ok(
  (public.v1_auth_claim_compatibility_report()
    ->> 'mismatch_count')::integer >= 2
  and (public.v1_auth_claim_compatibility_report()
    ->> 'stale_secondary_roles_count')::integer >= 1
  and public.v1_auth_claim_compatibility_report()::text
    like '%usr-local-site-engineer%'
  and public.v1_auth_claim_compatibility_report()::text not like '%@%'
  and public.v1_auth_claim_compatibility_report()::text
    not like '%10000000-0000-4000-8000-000000000002%',
  'Compatibility preflight reports extra, missing and stale claims using safe application identifiers only'
);

update public.v1_capability_catalog
set authorization_mode = 'shadow'
where capability_key in ('users.view', 'users.roles.assign');

select throws_ok(
  $test$
  do $claims_cutover$
  begin
    perform public.v1_assert_auth_claim_compatibility();
    update public.v1_capability_catalog
    set authorization_mode = 'enforced'
    where capability_key in ('users.view', 'users.roles.assign');
  end;
  $claims_cutover$;
  $test$,
  '23514',
  'V1_AUTH_COMPATIBILITY_CLAIMS_RECONCILIATION_REQUIRED',
  'Unreconciled retained Auth claims abort User Administration cutover before any mode flip'
);

select is(
  (
    select count(*)::integer
    from public.v1_capability_catalog
    where capability_key in ('users.view', 'users.roles.assign')
      and authorization_mode = 'shadow'
  ),
  2,
  'A compatibility-claim failure leaves the entire cutover mode set unchanged'
);

update auth.users auth_user
set raw_app_meta_data = jsonb_set(
  auth_user.raw_app_meta_data,
  '{caps}',
  public.v1_auth_expected_server_caps(
    auth_user.raw_app_meta_data ->> 'role'
  ),
  true
)
where public.v1_permission_exact_role(auth_user.id) <> '';

select lives_ok(
  $$select public.v1_assert_auth_claim_compatibility()$$,
  'Stale secondary role display data alone never becomes authority or blocks a reconciled caps cutover'
);

select * from finish();
rollback;

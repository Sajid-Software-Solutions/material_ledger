begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(15);

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relname = any (array[
        'projects',
        'materialPlans',
        'materialRequests',
        'materials',
        'materialCategories',
        'materialUnits',
        'stockMovements',
        'notifications',
        'rentalUnits',
        'rentPayments',
        'goodsReceipts',
        'returns',
        'employees',
        'attendance',
        'leaveRecords',
        'config',
        'users',
        'auditLogs',
        'device_tokens'
      ])
  ),
  19::bigint,
  'The complete legacy collection prerequisite is tracked'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and relation.relname = any (array[
        'projects',
        'materialPlans',
        'materialRequests',
        'materials',
        'materialCategories',
        'materialUnits',
        'stockMovements',
        'notifications',
        'rentalUnits',
        'rentPayments',
        'goodsReceipts',
        'returns',
        'employees',
        'attendance',
        'leaveRecords',
        'config',
        'users',
        'auditLogs',
        'device_tokens'
      ])
  ),
  19::bigint,
  'RLS is enabled on every exposed legacy collection'
);

select ok(
  not has_table_privilege('authenticated', 'public.users', 'select'),
  'Legacy local users are not exposed through the Data API'
);

select ok(
  not has_table_privilege('authenticated', 'public."auditLogs"', 'select'),
  'Legacy client audit logs are not exposed through the Data API'
);

select ok(
  has_table_privilege('authenticated', 'public.device_tokens', 'insert')
    and has_table_privilege(
      'authenticated',
      'public.device_tokens',
      'select'
    ),
  'Device tokens have the table grants required for owner-scoped upsert'
);

select ok(
  not has_table_privilege('authenticated', 'public.projects', 'delete'),
  'Legacy project hard-delete is not granted'
);

select is(
  (
    select count(*)
    from auth.users
    where email like '%@yorks.local.test'
  ),
  8::bigint,
  'Exactly eight deterministic local Auth personas are seeded'
);

select is(
  (
    select array_agg(
      raw_app_meta_data ->> 'role'
      order by raw_app_meta_data ->> 'role'
    )
    from auth.users
    where email like '%@yorks.local.test'
  ),
  array[
    'accountant',
    'admin',
    'pr',
    'procurement',
    'project_engineer',
    'project_manager',
    'senior_mechanical_engineer',
    'site_engineer'
  ]::text[],
  'The local personas use the exact eight testable Yorks V1 role claims'
);

select is(
  (
    select count(distinct raw_app_meta_data ->> 'app_user_id')
    from auth.users
    where email like '%@yorks.local.test'
  ),
  8::bigint,
  'Every local persona has a stable distinct application user id'
);

select is(
  (
    select count(*)
    from auth.identities identity_record
    join auth.users auth_user on auth_user.id = identity_record.user_id
    where auth_user.email like '%@yorks.local.test'
      and identity_record.provider = 'email'
  ),
  8::bigint,
  'Every local persona has a deterministic email identity'
);

select is(
  (
    select count(*)
    from auth.users
    where email like '%@yorks.local.test'
      and raw_user_meta_data ?| array[
        'role',
        'app_user_id',
        'caps'
      ]
  ),
  0::bigint,
  'Authorization claims are absent from editable user metadata'
);

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select is(
  public.app_role(),
  'site_engineer',
  'Application role is read from app_metadata'
);

select is(
  public.app_user_id(),
  'usr-local-site-engineer',
  'Stable application user id is read from app_metadata'
);

select set_config(
  'request.jwt.claims',
  '{"role":"admin"}',
  true
);

select is(
  public.app_role(),
  '',
  'A top-level JWT role cannot grant application authority'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer","caps":[]}}',
  true
);

select throws_ok(
  $$insert into public.projects (id, data)
    values (
      '__batch1_no_legacy_promotion__',
      '{
        "id":"__batch1_no_legacy_promotion__",
        "lifecycleStatus":"planning",
        "assignedEngineerId":"usr-local-project-engineer",
        "designEngineerUserIds":["usr-local-project-engineer"]
      }'::jsonb
    )$$,
  '42501',
  'new row violates row-level security policy for table "projects"',
  'A V1 Project Engineer is not silently promoted into legacy Engineer policy'
);

select * from finish();
rollback;

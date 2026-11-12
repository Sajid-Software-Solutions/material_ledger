-- Deterministic local development personas. These addresses and the shared
-- password are intentionally public and must never be used outside local/test:
--   YorksLocalOnly!2026
-- Remote seeds require an explicit `--include-seed`; never use that flag for
-- production.

begin;
set local search_path = auth, public, extensions;

with personas(
  auth_user_id,
  email,
  full_name,
  app_role,
  app_user_id,
  capabilities
) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'project.engineer@yorks.local.test',
      'Local Project Engineer',
      'project_engineer',
      'usr-local-project-engineer',
      '[]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000002'::uuid,
      'site.engineer@yorks.local.test',
      'Local Site Engineer',
      'site_engineer',
      'usr-local-site-engineer',
      '[]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000003'::uuid,
      'procurement@yorks.local.test',
      'Local Procurement',
      'procurement',
      'usr-local-procurement',
      '[
        "view_commercials",
        "manage_commercials",
        "viewCommercials",
        "rentals",
        "writeRentals",
        "people",
        "writePeople",
        "goods",
        "approveLeave"
      ]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000004'::uuid,
      'admin@yorks.local.test',
      'Local Admin',
      'admin',
      'usr-local-admin',
      '[
        "view_commercials",
        "manage_commercials",
        "viewCommercials",
        "salary",
        "finance",
        "rentals",
        "writeRentals",
        "people",
        "writePeople",
        "goods",
        "approveLeave"
      ]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000009'::uuid,
      'senior.mechanical.engineer@yorks.local.test',
      'Local Senior Mechanical Engineer',
      'senior_mechanical_engineer',
      'usr-local-senior-mechanical-engineer',
      '[]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000010'::uuid,
      'project.manager@yorks.local.test',
      'Local Project Manager',
      'project_manager',
      'usr-local-project-manager',
      '[]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000013'::uuid,
      'accountant@yorks.local.test',
      'Local Accountant',
      'accountant',
      'usr-local-accountant',
      '[]'::jsonb
    ),
    (
      '10000000-0000-4000-8000-000000000014'::uuid,
      'pr@yorks.local.test',
      'Local PR',
      'pr',
      'usr-local-pr',
      '[]'::jsonb
    )
)
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  auth_user_id,
  'authenticated',
  'authenticated',
  email,
  crypt('YorksLocalOnly!2026', gen_salt('bf')),
  '2026-08-01 00:00:00+00'::timestamptz,
  jsonb_build_object(
    'provider', 'email',
    'providers', jsonb_build_array('email'),
    'role', app_role,
    'app_user_id', app_user_id,
    'caps', capabilities
  ),
  jsonb_build_object(
    'full_name', full_name,
    'must_change_password', false
  ),
  '2026-08-01 00:00:00+00'::timestamptz,
  '2026-08-01 00:00:00+00'::timestamptz,
  '',
  '',
  '',
  ''
from personas
on conflict (id) do update
set email = excluded.email,
    encrypted_password = excluded.encrypted_password,
    email_confirmed_at = excluded.email_confirmed_at,
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = excluded.updated_at;

with personas(auth_user_id, email) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'project.engineer@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000002'::uuid,
      'site.engineer@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000003'::uuid,
      'procurement@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000004'::uuid,
      'admin@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000009'::uuid,
      'senior.mechanical.engineer@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000010'::uuid,
      'project.manager@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000013'::uuid,
      'accountant@yorks.local.test'
    ),
    (
      '10000000-0000-4000-8000-000000000014'::uuid,
      'pr@yorks.local.test'
    )
)
insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  auth_user_id,
  auth_user_id::text,
  auth_user_id,
  jsonb_build_object(
    'sub', auth_user_id::text,
    'email', email,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  '2026-08-01 00:00:00+00'::timestamptz,
  '2026-08-01 00:00:00+00'::timestamptz,
  '2026-08-01 00:00:00+00'::timestamptz
from personas
on conflict (provider_id, provider) do update
set user_id = excluded.user_id,
    identity_data = excluded.identity_data,
    last_sign_in_at = excluded.last_sign_in_at,
    updated_at = excluded.updated_at;

commit;

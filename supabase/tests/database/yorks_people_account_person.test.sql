begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- User Management shows the People record of an account
-- (PRODUCT_DECISIONS section 56).
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003,
-- Admin ...0004, Senior Mechanical Engineer ...0009, Accountant ...0013,
-- PR ...0014. Fictional fixtures only.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
end;
$$;

select ok(
  has_function_privilege('authenticated',
    'public.v1_people_account_person(text)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_people_account_person(text)', 'execute'),
  'Signed-in users call it; anonymous callers do not'
);

-- A person linked to the Site Engineer's account -----------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select set_config('acct.person', (
  public.v1_people_save_person(jsonb_build_object(
    'full_name', 'Local Site Engineer',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Site Engineer',
    'category', 'staff'
  ), 0, 'a3010000-0000-4000-8000-000000000001') ->> 'id'
), true);
select lives_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a3010000-0000-4000-8000-000000000002')$$,
  current_setting('acct.person')),
  'HR/PRO links the Site Engineer account'
);

-- Who can see it --------------------------------------------------------------

reset role;
select set_config('acct.revisions', (
  select count(*)::text from public.v1_people_revisions
), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  public.v1_people_account_person('usr-local-site-engineer')
    #>> '{person,id}',
  current_setting('acct.person'),
  'Admin sees the person the account is linked to'
);
select is(
  public.v1_people_account_person('usr-local-site-engineer')
    #>> '{account,auth_user_id}',
  '10000000-0000-4000-8000-000000000002',
  'with the account it was asked about'
);
select is(
  (public.v1_people_account_person('usr-local-site-engineer')
    ->> 'can_link')::boolean,
  true, 'Admin may link'
);
select is(
  jsonb_typeof(
    public.v1_people_account_person('usr-local-procurement') -> 'person'
  ),
  'null', 'An account not linked has no person'
);
select throws_ok(
  $$select public.v1_people_account_person('usr-nobody')$$,
  'P0002', 'V1_PEOPLE_ACCOUNT_NOT_FOUND', 'An unknown account is refused'
);
reset role;
select is(
  (select count(*)::text from public.v1_people_revisions),
  current_setting('acct.revisions'),
  'Reading writes no history'
);
set local role authenticated;

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  (public.v1_people_account_person('usr-local-site-engineer')
    ->> 'can_link')::boolean,
  true, 'HR/PRO sees it and may link'
);

select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  public.v1_people_account_person('usr-local-site-engineer')
    #>> '{person,id}',
  current_setting('acct.person'),
  'The Accountant sees it'
);
select is(
  (public.v1_people_account_person('usr-local-site-engineer')
    ->> 'can_link')::boolean,
  false, 'but does not link accounts'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_people_account_person('usr-local-site-engineer')$$,
  '42501', null, 'A Project Engineer cannot see People records'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_people_account_person('usr-local-site-engineer')$$,
  '42501', null, 'A Site Engineer cannot, even for their own account'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_people_account_person('usr-local-site-engineer')$$,
  '42501', null, 'Procurement cannot'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009',
  'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_people_account_person('usr-local-site-engineer')$$,
  '42501', null,
  'User Management alone (Senior Mechanical Engineer) does not open People'
);

select * from finish();
rollback;

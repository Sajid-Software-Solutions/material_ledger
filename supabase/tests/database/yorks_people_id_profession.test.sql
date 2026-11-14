begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- The profession on the visa and ID, apart from the position in the
-- company (PRODUCT_DECISIONS section 53).
--
-- Local personas: Procurement ...0003, PR ...0014. Fictional fixtures only.

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

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');

-- A person keeps both --------------------------------------------------------

select set_config('pid.person', (
  public.v1_people_save_person(jsonb_build_object(
    'full_name', 'Test Engineer One',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Project Engineer',
    'id_profession', 'Mechanical Engineer',
    'category', 'staff'
  ), 0, 'a1010000-0000-4000-8000-000000000001') ->> 'id'
), true);
select is(
  (public.v1_people_get(current_setting('pid.person')::uuid)
    ->> 'id_profession'),
  'Mechanical Engineer',
  'The profession on ID is kept'
);
select is(
  (public.v1_people_get(current_setting('pid.person')::uuid)
    ->> 'profession'),
  'Project Engineer',
  'apart from the position in the company'
);

-- An older screen that does not send it keeps it.
select lives_ok(
  format($$select public.v1_people_save_person(jsonb_build_object(
    'worker_id', %L,
    'full_name', 'Test Engineer One',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Senior Project Engineer',
    'category', 'staff'
  ), 1, 'a1010000-0000-4000-8000-000000000002')$$,
  current_setting('pid.person')),
  'Saving without the profession on ID'
);
select is(
  (public.v1_people_get(current_setting('pid.person')::uuid)
    ->> 'id_profession'),
  'Mechanical Engineer',
  'keeps it'
);

-- A blank one clears it.
select lives_ok(
  format($$select public.v1_people_save_person(jsonb_build_object(
    'worker_id', %L,
    'full_name', 'Test Engineer One',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Senior Project Engineer',
    'id_profession', '',
    'category', 'staff'
  ), 2, 'a1010000-0000-4000-8000-000000000003')$$,
  current_setting('pid.person')),
  'Saving a blank profession on ID'
);
select is(
  (public.v1_people_get(current_setting('pid.person')::uuid)
    ->> 'id_profession'),
  null,
  'clears it'
);
select throws_ok(
  format($$select public.v1_people_save_person(jsonb_build_object(
    'worker_id', %L,
    'full_name', 'Test Engineer One',
    'employer_company', 'Example Contracting LLC',
    'id_profession', repeat('x', 121),
    'category', 'staff'
  ), 3, 'a1010000-0000-4000-8000-000000000004')$$,
  current_setting('pid.person')),
  '22023', 'V1_PEOPLE_INVALID',
  'A profession on ID over 120 characters is refused'
);

-- Procurement still cannot change people.
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  format($$select public.v1_people_save_person(jsonb_build_object(
    'worker_id', %L,
    'full_name', 'Test Engineer One',
    'employer_company', 'Example Contracting LLC',
    'id_profession', 'Welder',
    'category', 'staff'
  ), 3, 'a1010000-0000-4000-8000-000000000005')$$,
  current_setting('pid.person')),
  '42501', null,
  'Procurement cannot set a profession on ID'
);

-- The tracker -----------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select lives_ok(
  $$select public.v1_people_import(jsonb_build_object(
    'source_name', 'Example tracker',
    'people', jsonb_build_array(
      jsonb_build_object(
        'full_name', 'Test Engineer Two',
        'employer_company', 'Example Contracting LLC',
        'designation', 'Mechanical Engineer',
        'position', 'Senior Mechanical Engineer',
        'category', 'staff'),
      jsonb_build_object(
        'full_name', 'Test Helper Three',
        'employer_company', 'Example Contracting LLC',
        'designation', 'Helper',
        'category', 'labour'))),
    'a1010000-0000-4000-8000-000000000006')$$,
  'A tracker with a Position in Company column'
);
reset role;
select results_eq(
  $$select worker.designation, profile.id_profession
    from public.v1_workforce_workers worker
    join public.v1_people_profiles profile on profile.worker_id = worker.id
    where worker.full_name in ('Test Engineer Two', 'Test Helper Three')
    order by worker.full_name$$,
  $$values ('Senior Mechanical Engineer'::text, 'Mechanical Engineer'::text),
    ('Helper'::text, 'Helper'::text)$$,
  'The Profession column is the one on ID; the position is the designation'
);

-- A profession on ID kept here is never overwritten by the tracker; a blank
-- one is filled.
update public.v1_people_profiles profile
set id_profession = null
from public.v1_workforce_workers worker
where worker.id = profile.worker_id and worker.full_name = 'Test Helper Three';
set local role authenticated;
select lives_ok(
  $$select public.v1_people_import(jsonb_build_object(
    'source_name', 'Example tracker',
    'people', jsonb_build_array(
      jsonb_build_object(
        'full_name', 'Test Engineer Two',
        'employer_company', 'Example Contracting LLC',
        'designation', 'Electrical Engineer',
        'category', 'staff'),
      jsonb_build_object(
        'full_name', 'Test Helper Three',
        'employer_company', 'Example Contracting LLC',
        'designation', 'Helper',
        'category', 'labour'))),
    'a1010000-0000-4000-8000-000000000007')$$,
  'Importing the tracker again'
);
reset role;
select results_eq(
  $$select worker.designation, profile.id_profession
    from public.v1_workforce_workers worker
    join public.v1_people_profiles profile on profile.worker_id = worker.id
    where worker.full_name in ('Test Engineer Two', 'Test Helper Three')
    order by worker.full_name$$,
  $$values ('Senior Mechanical Engineer'::text, 'Mechanical Engineer'::text),
    ('Helper'::text, 'Helper'::text)$$,
  'keeps both of the first and fills the blank one of the second'
);

select * from finish();
rollback;

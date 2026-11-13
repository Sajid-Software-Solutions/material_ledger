begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004,
-- SME ...0009, Accountant ...0013, PR ...0014. Fictional fixtures only.

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

-- Catalogue, role templates and boundaries -----------------------------------

select is(
  (select count(*) from public.v1_capability_catalog catalog
   where catalog.capability_key in (
     'people_records.view', 'people_records.manage'
   )
     and catalog.module_key = 'people_records'
     and catalog.authorization_mode = 'enforced'
     and catalog.is_assignable),
  2::bigint,
  'Both people record capabilities are enforced and assignable'
);
select is(
  (select array_agg(role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key = 'people_records.view' and is_granted),
  array['accountant', 'admin', 'pr']::text[],
  'Only Admin, Accountant and PR hold people records by default'
);
select is(
  (select array_agg(role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key = 'people_records.manage' and can_delegate),
  array['admin', 'pr']::text[],
  'Only Admin and PR may delegate people records'
);
select ok(
  public.v1_accountant_may_hold_capability('people_records.view')
  and public.v1_accountant_may_hold_capability('people_records.manage')
  and public.v1_accountant_may_hold_capability('worker_records.view')
  and not public.v1_accountant_may_hold_capability('projects.create')
  and not public.v1_accountant_may_hold_capability('workforce.view'),
  'Accountant gains the two people record keys and nothing else'
);
select ok(
  public.v1_pr_may_hold_capability('people_records.view')
  and public.v1_pr_may_hold_capability('people_records.manage')
  and public.v1_pr_may_hold_capability('worker_records.view')
  and not public.v1_pr_may_hold_capability('projects.create'),
  'PR gains the two people record keys and nothing else'
);
select ok(
  not has_table_privilege('authenticated', 'public.v1_people_documents', 'select')
  and not has_table_privilege('authenticated', 'public.v1_people_profiles', 'select')
  and not has_table_privilege('authenticated', 'public.v1_people_revisions', 'select')
  and not has_function_privilege('anon', 'public.v1_people_list(jsonb)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_people_import_plan(jsonb,boolean,uuid,text,uuid)', 'execute'),
  'People records are reachable only through their functions'
);

-- PostgREST runs STABLE functions read-only, and every entry point syncs the
-- caller's profile first, so none of them may be STABLE or IMMUTABLE.
select is(
  (select count(*)::int from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'v1_people_%'
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.provolatile <> 'v'),
  0,
  'Every People function the app calls may write the caller profile'
);

-- Who may read ----------------------------------------------------------------

select set_config('ppl.today', public.v1_wf_today()::text, true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_people_overview()$$, '42501', null,
  'A Site Engineer cannot open people records'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_people_list('{}'::jsonb)$$, '42501', null,
  'A Project Engineer cannot list people records'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_people_overview()$$, '42501', null,
  'Procurement cannot open people records'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_people_overview()$$, '42501', null,
  'A Senior Mechanical Engineer cannot open people records'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select ok(
  (public.v1_people_overview() ->> 'can_manage')::boolean,
  'The Accountant opens and may manage people records'
);

-- Add a person and record documents -------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select set_config('ppl.person', (
  public.v1_people_save_person(jsonb_build_object(
      'full_name', 'Test Person One',
      'employer_company', 'Example Contracting',
      'designation', 'Mechanical Engineer',
      'category', 'staff',
      'arabic_name', 'شخص تجريبي',
      'date_of_birth', '1985-03-04'),
    0, '9e010000-0000-4000-8000-000000000001') ->> 'id'
), true);
reset role;
select ok(
  (select category = 'staff' and arabic_name = 'شخص تجريبي'
   from public.v1_people_profiles
   where worker_id = current_setting('ppl.person')::uuid),
  'PR adds a staff member with a profile'
);
set local role authenticated;
reset role;
select ok(
  (select worker_number like 'WR-%' and current_status = 'active'
     and worker_type = 'yorks_employee'
   from public.v1_workforce_workers
   where id = current_setting('ppl.person')::uuid),
  'The person is a Workforce worker, ready for crews and attendance'
);
set local role authenticated;
select is(
  public.v1_people_save_person(jsonb_build_object(
      'full_name', 'Test Person One',
      'employer_company', 'Example Contracting',
      'designation', 'Mechanical Engineer',
      'category', 'staff',
      'arabic_name', 'شخص تجريبي',
      'date_of_birth', '1985-03-04'),
    0, '9e010000-0000-4000-8000-000000000001') ->> 'id',
  current_setting('ppl.person'),
  'A retry returns the same person'
);
reset role;
select is(
  (select count(*)::int from public.v1_workforce_workers
   where full_name = 'Test Person One'),
  1, 'A retry does not add the person twice'
);
set local role authenticated;

select set_config('ppl.visa', (
  public.v1_people_save_document(jsonb_build_object(
      'worker_id', current_setting('ppl.person'),
      'kind', 'visa', 'number', 'VISA-TEST-1',
      'expiry_date', (current_setting('ppl.today')::date + 30)::text),
    0, '9e010000-0000-4000-8000-000000000002') -> 'documents' -> 0 ->> 'id'
), true);
select is(
  public.v1_people_get(current_setting('ppl.person')::uuid) ->> 'attention',
  'expiring', 'A visa ending in 30 days needs attention'
);
select throws_ok(
  format($$select public.v1_people_save_document(jsonb_build_object(
      'worker_id', %L, 'kind', 'visa',
      'expiry_date', (current_date + 400)::text),
    0, '9e010000-0000-4000-8000-000000000003')$$,
    current_setting('ppl.person')),
  '23505', 'V1_PEOPLE_DOCUMENT_EXISTS',
  'A second current visa must be recorded as a renewal'
);
select throws_ok(
  format($$select public.v1_people_save_document(jsonb_build_object(
      'worker_id', %L, 'document_id', %L, 'renew', true,
      'expiry_date', (current_date + 400)::text),
    2, '9e010000-0000-4000-8000-000000000004')$$,
    current_setting('ppl.person'), current_setting('ppl.visa')),
  '40001', null, 'A stale version cannot renew a document'
);
select is(
  (public.v1_people_save_document(jsonb_build_object(
      'worker_id', current_setting('ppl.person'),
      'document_id', current_setting('ppl.visa'), 'renew', true,
      'number', 'VISA-TEST-2',
      'expiry_date', (current_setting('ppl.today')::date + 730)::text),
    1, '9e010000-0000-4000-8000-000000000005')
   -> 'documents' -> 0 ->> 'number'),
  'VISA-TEST-2', 'Renewing the visa makes the new one current'
);
select ok(
  (select count(*) = 1 from jsonb_array_elements(
     public.v1_people_get(current_setting('ppl.person')::uuid)
       -> 'previous_documents') document
   where document ->> 'number' = 'VISA-TEST-1'
     and document ->> 'ended_reason' = 'renewed'),
  'The renewed visa is kept as history'
);
select is(
  public.v1_people_get(current_setting('ppl.person')::uuid) ->> 'attention',
  'ok', 'After renewal nothing needs attention'
);

-- Site passes: more than one may be current.
select is(
  jsonb_array_length(public.v1_people_save_document(jsonb_build_object(
      'worker_id', current_setting('ppl.person'),
      'kind', 'cicpa_pass', 'number', 'CNI-1',
      'expiry_date', (current_setting('ppl.today')::date - 3)::text,
      'sites', 'Plant A, Plant B'),
    0, '9e010000-0000-4000-8000-000000000006') -> 'documents'),
  2, 'A CICPA pass is recorded beside the visa'
);
select is(
  jsonb_array_length(public.v1_people_save_document(jsonb_build_object(
      'worker_id', current_setting('ppl.person'),
      'kind', 'cicpa_pass', 'number', 'CNI-2',
      'sites', 'Island site'),
    0, '9e010000-0000-4000-8000-000000000007') -> 'documents'),
  3, 'A second CICPA pass for another site may be held'
);
select is(
  public.v1_people_get(current_setting('ppl.person')::uuid) ->> 'attention',
  'expired', 'An expired pass makes the person need attention'
);

-- End a pass: a reason is required.
reset role;
select set_config('ppl.pass', (
  select document.id::text from public.v1_people_documents document
  where document.worker_id = current_setting('ppl.person')::uuid
    and document.document_number = 'CNI-1'
), true);
set local role authenticated;
select throws_ok(
  format($$select public.v1_people_end_document(%L, '', 1,
    '9e010000-0000-4000-8000-000000000008')$$, current_setting('ppl.pass')),
  '22023', 'V1_PEOPLE_REASON_REQUIRED', 'Ending a document needs a reason'
);
select is(
  jsonb_array_length(public.v1_people_end_document(
    current_setting('ppl.pass')::uuid, 'Pass returned to CICPA', 1,
    '9e010000-0000-4000-8000-000000000009') -> 'documents'),
  2, 'The ended pass leaves the current documents'
);

-- Edit the person with the version the form opened.
select throws_ok(
  format($$select public.v1_people_save_person(jsonb_build_object(
      'worker_id', %L, 'full_name', 'Test Person One',
      'employer_company', 'Example Contracting', 'category', 'staff'),
    7, '9e010000-0000-4000-8000-000000000010')$$,
    current_setting('ppl.person')),
  '40001', null, 'A stale person version is a conflict'
);
select is(
  public.v1_people_save_person(jsonb_build_object(
      'worker_id', current_setting('ppl.person'),
      'full_name', 'Test Person One', 'employer_company', 'Example Contracting',
      'designation', 'Senior Mechanical Engineer', 'category', 'staff',
      'unified_number', '9001'),
    1, '9e010000-0000-4000-8000-000000000011') ->> 'unified_number',
  '9001', 'The person is edited with the version the form opened'
);
reset role;
select ok(
  (select count(*) >= 6 from public.v1_people_revisions
   where worker_id = current_setting('ppl.person')::uuid),
  'Every change is in the history'
);
set local role authenticated;
reset role;
select ok(
  not exists (
    select 1 from public.v1_audit_events event
    where event.entity_id = current_setting('ppl.person')::uuid
      and (event.after_data::text like '%VISA-TEST%'
        or event.after_data::text like '%9001%')
  ),
  'The audit trail never holds an identity number'
);
set local role authenticated;

-- Register --------------------------------------------------------------------

select is(
  (public.v1_people_list(jsonb_build_object('category', 'staff',
    'search', 'visa-test-2')) ->> 'total')::int,
  1, 'The register finds a person by a document number'
);
select is(
  (public.v1_people_list(jsonb_build_object('category', 'labour',
    'search', 'Test Person One')) ->> 'total')::int,
  0, 'A staff member is not in the labour register'
);
select throws_ok(
  $$select public.v1_people_list('{"status": "bogus"}'::jsonb)$$,
  '22023', null, 'An unknown filter is refused'
);

-- Import ----------------------------------------------------------------------

select set_config('ppl.import', jsonb_build_object(
  'source_name', 'tracker.xlsx',
  'joining_date', current_setting('ppl.today'),
  'people', jsonb_build_array(
    jsonb_build_object('row', 5, 'full_name', 'Imported Fitter',
      'employer_company', 'Example Contracting', 'designation', 'Pipe Fitter',
      'category', 'labour',
      'documents', jsonb_build_array(
        jsonb_build_object('kind', 'visa',
          'expiry_date', (current_setting('ppl.today')::date + 200)::text),
        jsonb_build_object('kind', 'labour_card',
          'expiry_date', (current_setting('ppl.today')::date - 1)::text),
        jsonb_build_object('kind', 'cicpa_pass', 'number', 'CNI-9',
          'expiry_date', (current_setting('ppl.today')::date + 10)::text,
          'sites', 'Plant A'))),
    jsonb_build_object('row', 6, 'full_name', ' test  person ONE ',
      'employer_company', 'example contracting', 'category', 'staff',
      'documents', jsonb_build_array(
        jsonb_build_object('kind', 'iloe',
          'expiry_date', (current_setting('ppl.today')::date + 90)::text),
        jsonb_build_object('kind', 'visa',
          'expiry_date', (current_setting('ppl.today')::date + 100)::text))))
)::text, true);

select ok(
  (select (preview -> 'counts' ->> 'new')::int = 1
     and (preview -> 'counts' ->> 'update')::int = 1
     and (preview -> 'counts' ->> 'problem')::int = 0
   from (select public.v1_people_preview_import(
     current_setting('ppl.import')::jsonb) as preview) p),
  'The preview finds one new person and one update by name and company'
);
reset role;
select is(
  (select count(*)::int from public.v1_workforce_workers
   where full_name = 'Imported Fitter'),
  0, 'The preview writes nothing'
);
set local role authenticated;
select ok(
  (select (result -> 'counts' ->> 'documents_new')::int = 4
   from (select public.v1_people_import(current_setting('ppl.import')::jsonb,
     '9e010000-0000-4000-8000-000000000012') as result) r),
  'The import adds the new person with three documents, and an ILOE'
);
reset role;
select ok(
  (select expiry_date = current_setting('ppl.today')::date + 730
   from public.v1_people_documents
   where worker_id = current_setting('ppl.person')::uuid
     and kind = 'visa' and is_current),
  'An older visa in the sheet does not replace the newer one held'
);
set local role authenticated;
reset role;
select ok(
  (select category = 'labour' from public.v1_people_profiles profile
   join public.v1_workforce_workers worker on worker.id = profile.worker_id
   where worker.full_name = 'Imported Fitter'),
  'The imported person is Labour'
);
set local role authenticated;
select is(
  (public.v1_people_preview_import(current_setting('ppl.import')::jsonb)
   -> 'counts' ->> 'unchanged')::int,
  2, 'Importing the same sheet again changes nothing'
);
select throws_ok(
  $$select public.v1_people_import(jsonb_build_object(
    'people', jsonb_build_array(
      jsonb_build_object('full_name', 'Twin', 'employer_company', 'X'),
      jsonb_build_object('full_name', 'twin', 'employer_company', 'x'))),
    '9e010000-0000-4000-8000-000000000013')$$,
  '22023', 'V1_PEOPLE_IMPORT_HAS_PROBLEMS',
  'A person repeated in the file blocks the whole import'
);
reset role;
select is(
  (select count(*)::int from public.v1_workforce_workers
   where full_name in ('Twin', 'twin')),
  0, 'A refused import writes nothing'
);
set local role authenticated;

-- Overview ----------------------------------------------------------------------

select ok(
  (select (overview -> 'counts' ->> 'expired')::int >= 1
     and jsonb_array_length(overview -> 'attention') >= 2
   from (select public.v1_people_overview() as overview) o),
  'The overview counts expired documents and lists what needs attention'
);

-- History is immutable --------------------------------------------------------

reset role;
select throws_ok(
  $$update public.v1_people_revisions set reason = 'x'$$,
  '55000', 'V1_PEOPLE_HISTORY_IMMUTABLE', 'History cannot be edited'
);
select throws_ok(
  $$delete from public.v1_people_documents$$,
  '55000', 'V1_PEOPLE_HISTORY_IMMUTABLE', 'Documents are never deleted'
);

select * from finish();
rollback;

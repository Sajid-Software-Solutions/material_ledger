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
  (select count(*)::int from public.v1_capability_catalog catalog
   where catalog.capability_key in (
     'company_documents.view', 'company_documents.manage'
   ) and catalog.authorization_mode = 'enforced' and catalog.is_assignable),
  2,
  'Both company document capabilities are enforced and assignable'
);
select is(
  (select array_agg(distinct role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key like 'company_documents.%' and is_granted),
  array['accountant', 'admin', 'pr']::text[],
  'Only Admin, Accountant and PR hold company documents by default'
);
select is(
  (select array_agg(distinct role_name order by role_name)
   from public.v1_permission_role_defaults
   where capability_key like 'company_documents.%' and can_delegate),
  array['admin', 'pr']::text[],
  'Only Admin and PR may delegate company documents'
);
select ok(
  public.v1_accountant_may_hold_capability('company_documents.manage')
  and public.v1_accountant_may_hold_capability('people_records.view')
  and public.v1_accountant_may_hold_capability('worker_records.view')
  and not public.v1_accountant_may_hold_capability('projects.create'),
  'Accountant gains the two company keys and keeps its other boundaries'
);
select ok(
  public.v1_pr_may_hold_capability('company_documents.manage')
  and public.v1_pr_may_hold_capability('people_records.manage')
  and not public.v1_pr_may_hold_capability('projects.create'),
  'PR gains the two company keys and keeps its other boundaries'
);
select ok(
  not has_table_privilege('authenticated', 'public.v1_company_docs_records', 'select')
  and not has_table_privilege('authenticated', 'public.v1_company_docs_documents', 'select')
  and not has_table_privilege('authenticated', 'public.v1_company_docs_revisions', 'select')
  and not has_function_privilege('anon', 'public.v1_company_docs_list(jsonb)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_company_docs_import_plan(jsonb,boolean,uuid,text,uuid)', 'execute'),
  'Company documents are reachable only through their functions'
);
-- PostgREST runs STABLE functions read-only, and every entry point syncs the
-- caller's profile first, so none of them may be STABLE or IMMUTABLE.
select is(
  (select count(*)::int from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'v1_company_docs_%'
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.provolatile <> 'v'),
  0,
  'Every company document function the app calls may write the caller profile'
);

-- Who may read ----------------------------------------------------------------

select set_config('cd.today', public.v1_wf_today()::text, true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_company_docs_overview()$$, '42501', null,
  'A Site Engineer cannot open company documents'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_company_docs_list('{}'::jsonb)$$, '42501', null,
  'A Project Engineer cannot list company documents'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_company_docs_overview()$$, '42501', null,
  'Procurement cannot open company documents'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_company_docs_overview()$$, '42501', null,
  'A Senior Mechanical Engineer cannot open company documents'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select ok(
  (public.v1_company_docs_overview() ->> 'can_manage')::boolean,
  'The Accountant opens and may manage company documents'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_company_docs_save_record(
    '{"kind":"vehicle","name":"Test Van 1"}'::jsonb, 0,
    '9f020000-0000-4000-8000-000000000099')$$,
  '42501', null, 'A Site Engineer cannot add a company record'
);

-- Records and documents --------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select set_config('cd.vehicle', (
  public.v1_company_docs_save_record(jsonb_build_object(
      'kind', 'vehicle', 'name', 'Test Pickup 11111',
      'reference', '11111', 'owner', 'Example Contracting'),
    0, '9f020000-0000-4000-8000-000000000001') ->> 'id'), true);
select is(
  public.v1_company_docs_save_record(jsonb_build_object(
      'kind', 'vehicle', 'name', 'Test Pickup 11111',
      'reference', '11111', 'owner', 'Example Contracting'),
    0, '9f020000-0000-4000-8000-000000000001') ->> 'id',
  current_setting('cd.vehicle'),
  'A retry returns the same record'
);
select throws_ok(
  $$select public.v1_company_docs_save_record(
    '{"kind":"vehicle","name":"Test Van","details":{"job":"x"}}'::jsonb, 0,
    '9f020000-0000-4000-8000-000000000002')$$,
  '22023', null, 'Only a contract carries contract details'
);
select is(
  jsonb_array_length(public.v1_company_docs_save_document(jsonb_build_object(
      'record_id', current_setting('cd.vehicle'), 'kind', 'registration',
      'expiry_date', (current_setting('cd.today')::date + 20)::text),
    0, '9f020000-0000-4000-8000-000000000003') -> 'documents'),
  1, 'PR records the registration'
);
select is(
  public.v1_company_docs_get(current_setting('cd.vehicle')::uuid)
    ->> 'attention',
  'expiring', 'A registration ending in 20 days needs attention'
);
select set_config('cd.reg', (
  public.v1_company_docs_get(current_setting('cd.vehicle')::uuid)
    -> 'documents' -> 0 ->> 'id'), true);
select throws_ok(
  format($$select public.v1_company_docs_save_document(jsonb_build_object(
      'record_id', %L, 'document_id', %L, 'renew', true,
      'expiry_date', (current_date + 400)::text),
    5, '9f020000-0000-4000-8000-000000000004')$$,
    current_setting('cd.vehicle'), current_setting('cd.reg')),
  '40001', null, 'A stale version cannot renew a document'
);
select is(
  public.v1_company_docs_save_document(jsonb_build_object(
      'record_id', current_setting('cd.vehicle'),
      'document_id', current_setting('cd.reg'), 'renew', true,
      'expiry_date', (current_setting('cd.today')::date + 365)::text),
    1, '9f020000-0000-4000-8000-000000000005') ->> 'attention',
  'ok', 'Renewing the registration clears the attention'
);
select is(
  jsonb_array_length(public.v1_company_docs_get(
    current_setting('cd.vehicle')::uuid) -> 'previous_documents'),
  1, 'The renewed registration is kept as history'
);
select is(
  jsonb_array_length(public.v1_company_docs_save_document(jsonb_build_object(
      'record_id', current_setting('cd.vehicle'), 'kind', 'cicpa_pass',
      'sites', 'Plant A'),
    0, '9f020000-0000-4000-8000-000000000006') -> 'documents'),
  2, 'A vehicle pass may record only the sites it covers'
);
select throws_ok(
  format($$select public.v1_company_docs_save_document(jsonb_build_object(
      'record_id', %L, 'kind', 'registration'),
    0, '9f020000-0000-4000-8000-000000000007')$$,
    current_setting('cd.vehicle')),
  '22023', null, 'A document needs a number or an expiry'
);
select set_config('cd.pass', (
  select document ->> 'id'
  from jsonb_array_elements(public.v1_company_docs_get(
    current_setting('cd.vehicle')::uuid) -> 'documents') document
  where document ->> 'kind' = 'cicpa_pass'), true);
select throws_ok(
  format($$select public.v1_company_docs_end_document(%L, ' ', 1,
    '9f020000-0000-4000-8000-000000000008')$$, current_setting('cd.pass')),
  '22023', null, 'Ending a document needs a reason'
);
select is(
  jsonb_array_length(public.v1_company_docs_end_document(
    current_setting('cd.pass')::uuid, 'Pass handed back', 1,
    '9f020000-0000-4000-8000-000000000009') -> 'documents'),
  1, 'An ended pass leaves the current documents'
);

-- A contract keeps its job and pass counts.
select set_config('cd.contract', (
  public.v1_company_docs_save_record(jsonb_build_object(
      'kind', 'contract', 'name', 'LOA 900001', 'reference', '900001',
      'owner', 'Example Contracting',
      'details', jsonb_build_object('job', 'Test Plant', 'people', '12',
        'vehicles', 2, 'applied_people', '')),
    0, '9f020000-0000-4000-8000-000000000010') ->> 'id'), true);
select is(
  public.v1_company_docs_get(current_setting('cd.contract')::uuid) -> 'details',
  '{"job":"Test Plant","people":12,"vehicles":2}'::jsonb,
  'Contract details keep the job and the counts'
);
select throws_ok(
  format($$select public.v1_company_docs_save_record(jsonb_build_object(
      'record_id', %L, 'name', 'LOA 900001', 'details',
      jsonb_build_object('people', 'many')), 1,
    '9f020000-0000-4000-8000-000000000011')$$,
    current_setting('cd.contract')),
  '22023', null, 'A pass count is a whole number'
);

-- Archive and restore.
select throws_ok(
  format($$select public.v1_company_docs_set_archived(%L, true, '', 1,
    '9f020000-0000-4000-8000-000000000012')$$, current_setting('cd.contract')),
  '22023', null, 'Archiving needs a reason'
);
select is(
  public.v1_company_docs_set_archived(current_setting('cd.contract')::uuid,
    true, 'Contract finished', 1, '9f020000-0000-4000-8000-000000000013')
    ->> 'status',
  'archived', 'A finished contract is archived, not deleted'
);
select is(
  (public.v1_company_docs_list('{"kinds":["contract"]}'::jsonb) ->> 'total')::int,
  0, 'Archived records leave the register'
);
select is(
  (public.v1_company_docs_list(
    '{"kinds":["contract"],"include_archived":true}'::jsonb) ->> 'total')::int,
  1, 'Archived records can still be listed'
);
select throws_ok(
  $$select public.v1_company_docs_list('{"kinds":["person"]}'::jsonb)$$,
  '22023', null, 'An unknown kind is refused'
);

reset role;
select throws_ok(
  $$delete from public.v1_company_docs_revisions$$, '55000', null,
  'The history cannot be deleted'
);
select ok(
  (select count(*) from public.v1_company_docs_revisions
   where record_id = current_setting('cd.vehicle')::uuid) >= 4,
  'Every change is in the history'
);
select ok(
  exists (select 1 from public.v1_audit_events
    where event_type = 'company_document_renewed'),
  'Renewals are audited'
);
set local role authenticated;

-- Import --------------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('cd.payload', jsonb_build_object(
  'source_name', 'test tracker.xlsx',
  'records', jsonb_build_array(
    jsonb_build_object('row', 4, 'sheet', 'Licences', 'kind', 'entity',
      'name', 'TEST MAIN', 'reference', 'CN-0000001', 'documents',
      jsonb_build_array(
        jsonb_build_object('kind', 'licence',
          'expiry_date', (current_setting('cd.today')::date + 300)::text),
        jsonb_build_object('kind', 'labour_file', 'number', '12345'),
        jsonb_build_object('kind', 'pro_card', 'label', 'PRO card Test A',
          'expiry_date', (current_setting('cd.today')::date - 5)::text))),
    jsonb_build_object('row', 30, 'kind', 'vehicle',
      'name', 'Test Pickup 11111', 'reference', '11111', 'documents',
      jsonb_build_array(
        jsonb_build_object('kind', 'asateel_permit',
          'expiry_date', (current_setting('cd.today')::date + 90)::text),
        -- An older registration than the one held never replaces it.
        jsonb_build_object('kind', 'registration',
          'expiry_date', (current_setting('cd.today')::date + 10)::text))),
    jsonb_build_object('row', 2, 'sheet', 'Contracts', 'kind', 'contract',
      'name', 'LOA 900002', 'reference', '900002', 'owner', 'TEST MAIN',
      'details', jsonb_build_object('job', 'Test Island', 'people', 5),
      'documents', jsonb_build_array(jsonb_build_object('kind', 'contract',
        'number', '900002',
        'expiry_date', (current_setting('cd.today')::date + 30)::text))))
)::text, true);
select is(
  public.v1_company_docs_preview_import(current_setting('cd.payload')::jsonb)
    -> 'counts',
  '{"new": 2, "update": 1, "problem": 0, "unchanged": 0, "documents_new": 5,
    "documents_renewed": 0, "documents_updated": 0}'::jsonb,
  'The preview finds two new records and one update, matched by plate'
);
select is(
  public.v1_company_docs_import(current_setting('cd.payload')::jsonb,
    '9f020000-0000-4000-8000-000000000020') -> 'counts' ->> 'new',
  '2', 'The import adds the new records'
);
select is(
  public.v1_company_docs_import(current_setting('cd.payload')::jsonb,
    '9f020000-0000-4000-8000-000000000020') -> 'counts' ->> 'new',
  '2', 'A retried import returns the first result'
);
select is(
  public.v1_company_docs_preview_import(current_setting('cd.payload')::jsonb)
    -> 'counts' ->> 'unchanged',
  '3', 'Importing the same sheet again changes nothing'
);
select is(
  (select document ->> 'expiry_date'
   from jsonb_array_elements(public.v1_company_docs_get(
     current_setting('cd.vehicle')::uuid) -> 'documents') document
   where document ->> 'kind' = 'registration'),
  (current_setting('cd.today')::date + 365)::text,
  'The newer registration held is kept'
);
select is(
  public.v1_company_docs_preview_import(jsonb_build_object(
    'source_name', 'x', 'records', jsonb_build_array(
      jsonb_build_object('kind', 'item', 'name', 'Test Cert'),
      jsonb_build_object('kind', 'item', 'name', 'TEST  CERT'))))
    -> 'counts' ->> 'problem',
  '1', 'A record repeated in the file is a problem'
);
select throws_ok(
  $$select public.v1_company_docs_import(jsonb_build_object(
    'source_name', 'x', 'records', jsonb_build_array(
      jsonb_build_object('kind', 'item', 'name', ''))),
    '9f020000-0000-4000-8000-000000000021')$$,
  '22023', null, 'An import with problems is refused as a whole'
);
select ok(
  (select count(*) from jsonb_array_elements(
     public.v1_company_docs_overview() -> 'attention') item
   where item -> 'record' ->> 'name' = 'TEST MAIN'
     and item -> 'document' ->> 'status' = 'expired') = 1,
  'The overview lists the expired PRO card'
);
select is(
  (public.v1_company_docs_list(
    '{"status":"expired","search":"test main"}'::jsonb) ->> 'total')::int,
  1, 'The register filters by status and search'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Company document attachments (PRODUCT_DECISIONS section 48).
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

-- A vehicle with its registration, and a company with its licence.
insert into public.v1_company_docs_records (
  id, kind, name, reference, created_by_auth_user_id,
  updated_by_auth_user_id, updated_by_role
) values
  ('7e010000-0000-4000-8000-000000000001', 'vehicle', 'Test Pickup 22222',
   '22222', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('7e010000-0000-4000-8000-000000000002', 'entity', 'Example Contracting',
   'CN-0000009', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');
insert into public.v1_company_docs_documents (
  id, record_id, kind, document_number, expiry_date,
  created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
) values
  ('7e050000-0000-4000-8000-000000000001',
   '7e010000-0000-4000-8000-000000000001', 'registration', 'REG-TEST-1',
   date '2027-06-01', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('7e050000-0000-4000-8000-000000000002',
   '7e010000-0000-4000-8000-000000000002', 'licence', 'LIC-TEST-2',
   date '2027-06-01', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');

select set_config('ca.path1',
  'company/7e010000-0000-4000-8000-000000000001/7e030000-0000-4000-8000-000000000001.pdf',
  true);
select set_config('ca.path2',
  'company/7e010000-0000-4000-8000-000000000002/7e030000-0000-4000-8000-000000000002.png',
  true);

-- Storing files ---------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select lives_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":3072,"mimetype":"application/pdf"}'::jsonb)$$,
    current_setting('ca.path1')),
  'PR stores a vehicle registration copy'
);
select lives_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":5120,"mimetype":"image/png"}'::jsonb)$$,
    current_setting('ca.path2')),
  'PR stores a trade licence scan'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files',
      'company/7e010000-0000-4000-8000-000000000099/7e030000-0000-4000-8000-000000000003.pdf',
      '10000000-0000-4000-8000-000000000014',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A file for a record that does not exist is refused'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files',
      'people/7e010000-0000-4000-8000-000000000001/7e030000-0000-4000-8000-000000000004.pdf',
      '10000000-0000-4000-8000-000000000014',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A path outside the company folder is refused'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files',
      'company/7e010000-0000-4000-8000-000000000001/7e030000-0000-4000-8000-000000000005.pdf',
      '10000000-0000-4000-8000-000000000001',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A Project Engineer cannot store company files'
);

-- Recording them ------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  jsonb_array_length(public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('ca.path1'),
      'file_name', 'Mulkiya.pdf',
      'document_id', '7e050000-0000-4000-8000-000000000001'
    ),
    '7e040000-0000-4000-8000-000000000001'
  ) -> 'attachments'),
  1, 'The registration copy is attached to the vehicle'
);
select is(
  jsonb_array_length(public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('ca.path1'),
      'file_name', 'Mulkiya.pdf',
      'document_id', '7e050000-0000-4000-8000-000000000001'
    ),
    '7e040000-0000-4000-8000-000000000001'
  ) -> 'attachments'),
  1, 'A retry attaches it once'
);
select is(
  (public.v1_company_docs_list_attachments(
     '7e010000-0000-4000-8000-000000000001') -> 'attachments' -> 0),
  (public.v1_company_docs_list_attachments(
     '7e010000-0000-4000-8000-000000000001') -> 'attachments' -> 0)
    || jsonb_build_object(
      'document_kind', 'registration', 'size_bytes', 3072,
      'content_type', 'application/pdf', 'file_name', 'Mulkiya.pdf'
    ),
  'It says which document it copies; size and type come from storage'
);
select throws_ok(
  $$select public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000001',
    jsonb_build_object('object_path', current_setting('ca.path2'),
      'file_name', 'licence.png'),
    '7e040000-0000-4000-8000-000000000002')$$,
  '22023', 'V1_COMPANY_DOCS_ATTACHMENT_INVALID',
  'A file stored under another record cannot be attached here'
);
select throws_ok(
  $$select public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000002',
    jsonb_build_object('object_path', current_setting('ca.path2'),
      'file_name', 'licence.png',
      'document_id', '7e050000-0000-4000-8000-000000000001'),
    '7e040000-0000-4000-8000-000000000003')$$,
  '22023', 'V1_COMPANY_DOCS_ATTACHMENT_INVALID',
  'Another record''s document cannot be named'
);
select throws_ok(
  $$select public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'object_path', 'company/7e010000-0000-4000-8000-000000000002/7e030000-0000-4000-8000-000000000009.pdf',
      'file_name', 'missing.pdf'),
    '7e040000-0000-4000-8000-000000000004')$$,
  '22023', 'V1_COMPANY_DOCS_ATTACHMENT_NOT_STORED',
  'A file that was never stored cannot be attached'
);
select lives_ok(
  $$select public.v1_company_docs_add_attachment(
    '7e010000-0000-4000-8000-000000000002',
    jsonb_build_object('object_path', current_setting('ca.path2'),
      'file_name', 'licence.png', 'title', 'Trade licence 2027',
      'document_id', '7e050000-0000-4000-8000-000000000002'),
    '7e040000-0000-4000-8000-000000000005')$$,
  'A company has attachments too'
);
select throws_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-company-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":1,"mimetype":"application/pdf"}'::jsonb)$$,
    current_setting('ca.path1')),
  null, null, 'A recorded file is never replaced'
);

-- Who sees them -------------------------------------------------------------

select is(
  (public.v1_company_docs_attachment_counts() -> 'counts')
    ->> '7e010000-0000-4000-8000-000000000001',
  '1', 'The registers show how many files a record has'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select ok(
  jsonb_array_length(public.v1_company_docs_list_attachments(
    '7e010000-0000-4000-8000-000000000002') -> 'attachments') = 1
  and exists (select 1 from storage.objects
    where bucket_id = 'yorks-company-files'
      and name = current_setting('ca.path2')),
  'The Accountant sees and opens company files'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_company_docs_list_attachments(
    '7e010000-0000-4000-8000-000000000001')$$,
  '42501', null, 'A Senior Mechanical Engineer cannot see company files'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select ok(
  not exists (select 1 from storage.objects
    where bucket_id = 'yorks-company-files'),
  'Nor can a Project Engineer open them, even knowing the path'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_company_docs_attachment_counts()$$,
  '42501', null, 'Procurement cannot see company files'
);

-- Removing ------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  $$select public.v1_company_docs_remove_attachment(
    '7e030000-0000-4000-8000-000000000001', ' ',
    '7e040000-0000-4000-8000-000000000006')$$,
  '22023', 'V1_COMPANY_DOCS_REASON_REQUIRED', 'Removing needs a reason'
);
select is(
  jsonb_array_length(public.v1_company_docs_remove_attachment(
    '7e030000-0000-4000-8000-000000000001', 'Old registration card',
    '7e040000-0000-4000-8000-000000000007') -> 'attachments'),
  0, 'Admin removes the attachment'
);
select ok(
  not exists (select 1 from storage.objects
    where bucket_id = 'yorks-company-files'
      and name = current_setting('ca.path1')),
  'A removed file can no longer be opened'
);
reset role;
select ok(
  exists (select 1 from storage.objects
    where bucket_id = 'yorks-company-files'
      and name = current_setting('ca.path1'))
  and exists (select 1 from public.v1_company_docs_attachments
    where id = '7e030000-0000-4000-8000-000000000001'
      and removed_reason = 'Old registration card'),
  'The file and the row are kept'
);
select is(
  (select array_agg(action order by id) from public.v1_company_docs_revisions
   where entity = 'attachment'
     and record_id = '7e010000-0000-4000-8000-000000000001'),
  array['added', 'removed'], 'The record''s history shows both'
);
select throws_ok(
  $$delete from public.v1_company_docs_attachments
    where id = '7e030000-0000-4000-8000-000000000002'$$,
  '55000', 'V1_COMPANY_DOCS_HISTORY_IMMUTABLE', 'Attachments are never deleted'
);
select ok(
  not has_function_privilege('anon',
    'public.v1_company_docs_add_attachment(uuid,jsonb,uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_company_docs_attachments_json(uuid)', 'execute')
  and (select provolatile = 'v' from pg_proc
       where oid = 'public.v1_company_docs_list_attachments(uuid)'::regprocedure),
  'Anonymous callers have nothing, the projection is internal, reads are volatile'
);

select * from finish();
rollback;

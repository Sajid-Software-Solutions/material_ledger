begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- People attachments (PRODUCT_DECISIONS section 47).
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

-- A labourer with a passport, a staff member, and paths for their files.
insert into public.v1_workforce_workers (
  id, worker_number, full_name, designation, employer_company, worker_type,
  joining_date, created_by_auth_user_id, updated_by_auth_user_id
) values
  ('6e020000-0000-4000-8000-000000000001', 'ATT-1', 'Attach Labourer',
   'Helper', 'Example Manpower LLC', 'agency_worker', date '2025-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004'),
  ('6e020000-0000-4000-8000-000000000002', 'ATT-2', 'Attach Staff',
   'Engineer', 'Example Cooling LLC', 'yorks_employee', date '2025-01-01',
   '10000000-0000-4000-8000-000000000004',
   '10000000-0000-4000-8000-000000000004');
insert into public.v1_people_profiles (
  worker_id, category, created_by_auth_user_id, updated_by_auth_user_id,
  updated_by_role
) values
  ('6e020000-0000-4000-8000-000000000001', 'labour',
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('6e020000-0000-4000-8000-000000000002', 'staff',
   '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');
insert into public.v1_people_documents (
  id, worker_id, kind, document_number, expiry_date,
  created_by_auth_user_id, updated_by_auth_user_id, updated_by_role
) values
  ('6e050000-0000-4000-8000-000000000001',
   '6e020000-0000-4000-8000-000000000001', 'passport', 'P-ATTACH-1',
   date '2030-01-01', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr'),
  ('6e050000-0000-4000-8000-000000000002',
   '6e020000-0000-4000-8000-000000000002', 'visa', 'V-ATTACH-2',
   date '2030-01-01', '10000000-0000-4000-8000-000000000014',
   '10000000-0000-4000-8000-000000000014', 'pr');

select set_config('att.path1',
  'people/6e020000-0000-4000-8000-000000000001/6e030000-0000-4000-8000-000000000001.pdf',
  true);
select set_config('att.path2',
  'people/6e020000-0000-4000-8000-000000000002/6e030000-0000-4000-8000-000000000002.jpg',
  true);

-- Storing files ---------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select lives_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":2048,"mimetype":"application/pdf"}'::jsonb)$$,
    current_setting('att.path1')),
  'PR stores a passport copy for a labourer'
);
select lives_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":4096,"mimetype":"image/jpeg"}'::jsonb)$$,
    current_setting('att.path2')),
  'PR stores a visa copy for a staff member'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files',
      'people/6e020000-0000-4000-8000-000000000099/6e030000-0000-4000-8000-000000000003.pdf',
      '10000000-0000-4000-8000-000000000014',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A file for someone who is not a person is refused'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files',
      'people/6e020000-0000-4000-8000-000000000001/../secret.pdf',
      '10000000-0000-4000-8000-000000000014',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A path outside the person''s folder is refused'
);

select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files',
      'people/6e020000-0000-4000-8000-000000000001/6e030000-0000-4000-8000-000000000004.pdf',
      '10000000-0000-4000-8000-000000000009',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A Senior Mechanical Engineer cannot store People files'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files',
      'people/6e020000-0000-4000-8000-000000000001/6e030000-0000-4000-8000-000000000005.pdf',
      '10000000-0000-4000-8000-000000000001',
      '{"size":10,"mimetype":"application/pdf"}'::jsonb)$$,
  '42501', null, 'A Project Engineer cannot store People files'
);

-- Recording them ------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  jsonb_array_length(public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('att.path1'),
      'file_name', 'Passport copy.pdf',
      'document_id', '6e050000-0000-4000-8000-000000000001'
    ),
    '6e040000-0000-4000-8000-000000000001'
  ) -> 'attachments'),
  1, 'The passport copy is attached to the labourer'
);
select is(
  jsonb_array_length(public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('att.path1'),
      'file_name', 'Passport copy.pdf',
      'document_id', '6e050000-0000-4000-8000-000000000001'
    ),
    '6e040000-0000-4000-8000-000000000001'
  ) -> 'attachments'),
  1, 'A retry attaches it once'
);
select is(
  (public.v1_people_list_attachments('6e020000-0000-4000-8000-000000000001')
    -> 'attachments' -> 0),
  (public.v1_people_list_attachments('6e020000-0000-4000-8000-000000000001')
    -> 'attachments' -> 0)
    || jsonb_build_object(
      'document_kind', 'passport', 'size_bytes', 2048,
      'content_type', 'application/pdf', 'file_name', 'Passport copy.pdf'
    ),
  'It says which document it copies; size and type come from storage'
);
select lives_ok(
  $$select public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'object_path', current_setting('att.path2'),
      'file_name', 'visa.jpg', 'title', 'Visa page'
    ),
    '6e040000-0000-4000-8000-000000000002')$$,
  'Staff have attachments too'
);
select throws_ok(
  $$select public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('att.path2'),
      'file_name', 'visa.jpg'),
    '6e040000-0000-4000-8000-000000000003')$$,
  '22023', 'V1_PEOPLE_ATTACHMENT_INVALID',
  'A file stored under another person cannot be attached here'
);
select throws_ok(
  $$select public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', 'people/6e020000-0000-4000-8000-000000000001/6e030000-0000-4000-8000-000000000009.pdf',
      'file_name', 'missing.pdf'),
    '6e040000-0000-4000-8000-000000000004')$$,
  '22023', 'V1_PEOPLE_ATTACHMENT_NOT_STORED',
  'A file that was never stored cannot be attached'
);
select throws_ok(
  $$select public.v1_people_add_attachment(
    '6e020000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'object_path', current_setting('att.path1'),
      'file_name', 'x.pdf',
      'document_id', '6e050000-0000-4000-8000-000000000002'),
    '6e040000-0000-4000-8000-000000000005')$$,
  '22023', 'V1_PEOPLE_ATTACHMENT_INVALID',
  'Another person''s document cannot be named'
);
select throws_ok(
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('yorks-people-files', %L, '10000000-0000-4000-8000-000000000014',
      '{"size":1,"mimetype":"application/pdf"}'::jsonb)$$,
    current_setting('att.path1')),
  null, null, 'A recorded file is never replaced'
);

-- Who sees them -------------------------------------------------------------

select is(
  (public.v1_people_attachment_counts() -> 'counts')
    ->> '6e020000-0000-4000-8000-000000000001',
  '1', 'The register shows how many files a person has'
);
select ok(
  exists (select 1 from storage.objects
    where bucket_id = 'yorks-people-files'
      and name = current_setting('att.path1')),
  'PR opens the stored file'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  jsonb_array_length(public.v1_people_list_attachments(
    '6e020000-0000-4000-8000-000000000001') -> 'attachments'),
  1, 'The Accountant sees the attachments'
);
select ok(
  exists (select 1 from storage.objects
    where bucket_id = 'yorks-people-files'
      and name = current_setting('att.path1')),
  'The Accountant opens the stored file'
);
select is(
  (public.v1_people_list_attachments('6e020000-0000-4000-8000-000000000001')
    ->> 'can_manage')::boolean,
  true, 'The Accountant manages them, as People records (role default)'
);
select pg_temp.act('10000000-0000-4000-8000-000000000009', 'senior_mechanical_engineer');
select throws_ok(
  $$select public.v1_people_remove_attachment(
    '6e030000-0000-4000-8000-000000000001', 'Wrong file',
    '6e040000-0000-4000-8000-000000000006')$$,
  '42501', null, 'A Senior Mechanical Engineer cannot remove an attachment'
);
select throws_ok(
  $$select public.v1_people_list_attachments(
    '6e020000-0000-4000-8000-000000000001')$$,
  '42501', null, 'Nor see them'
);
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_people_list_attachments(
    '6e020000-0000-4000-8000-000000000001')$$,
  '42501', null, 'A Project Engineer cannot see People attachments'
);
select ok(
  not exists (select 1 from storage.objects
    where bucket_id = 'yorks-people-files'),
  'Nor open the files, even knowing the path'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_people_attachment_counts()$$,
  '42501', null, 'Procurement cannot see People attachments'
);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  (public.v1_people_list_attachments('6e020000-0000-4000-8000-000000000002')
    -> 'attachments' -> 0 ->> 'title'),
  'Visa page', 'Admin sees a staff member''s files'
);

-- Removing ------------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  $$select public.v1_people_remove_attachment(
    '6e030000-0000-4000-8000-000000000001', '  ',
    '6e040000-0000-4000-8000-000000000007')$$,
  '22023', 'V1_PEOPLE_REASON_REQUIRED', 'Removing needs a reason'
);
select is(
  jsonb_array_length(public.v1_people_remove_attachment(
    '6e030000-0000-4000-8000-000000000001', 'Scanned the wrong page',
    '6e040000-0000-4000-8000-000000000008') -> 'attachments'),
  0, 'PR removes the attachment'
);
select ok(
  not exists (select 1 from storage.objects
    where bucket_id = 'yorks-people-files'
      and name = current_setting('att.path1')),
  'A removed file can no longer be opened'
);
reset role;
select ok(
  exists (select 1 from storage.objects
    where bucket_id = 'yorks-people-files'
      and name = current_setting('att.path1'))
  and exists (select 1 from public.v1_people_attachments
    where id = '6e030000-0000-4000-8000-000000000001'
      and removed_reason = 'Scanned the wrong page'),
  'The file and the row are kept'
);
select is(
  (select array_agg(action order by id) from public.v1_people_revisions
   where entity = 'attachment'
     and worker_id = '6e020000-0000-4000-8000-000000000001'),
  array['added', 'removed'], 'The person''s history shows both'
);
select throws_ok(
  $$delete from public.v1_people_attachments
    where id = '6e030000-0000-4000-8000-000000000002'$$,
  '55000', 'V1_PEOPLE_HISTORY_IMMUTABLE', 'Attachments are never deleted'
);
select ok(
  not has_function_privilege('anon',
    'public.v1_people_add_attachment(uuid,jsonb,uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_people_attachments_json(uuid)', 'execute')
  and (select provolatile = 'v' from pg_proc
       where oid = 'public.v1_people_list_attachments(uuid)'::regprocedure),
  'Anonymous callers have nothing, the projection is internal, reads are volatile'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(12);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_prepare_rental_document_upload(jsonb,uuid)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.v1_rental_document_workspace_projection(uuid)',
    'execute'
  ),
  'Authenticated clients can reach rental documents only through trusted RPCs'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_prepare_rental_document_upload(
    '{
      "project_id":"84100000-0000-4000-8000-000000000010",
      "entity_type":"rental_property",
      "entity_id":"84100000-0000-4000-8000-000000000010",
      "classification":"commercial",
      "file_name":"lease.pdf",
      "mime_type":"application/pdf",
      "byte_size":12,
      "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "origin":"uploaded"
    }'::jsonb,
    '84100000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'V1_RENTAL_DOCUMENT_ADMIN_REQUIRED',
  'Project Engineer cannot prepare a rental lease upload'
);

select throws_ok(
  $$select public.v1_rental_document_workspace_projection(
    '84100000-0000-4000-8000-000000000010'
  )$$,
  '42501', 'V1_RENTAL_DOCUMENT_WORKSPACE_READ_DENIED',
  'Project Engineer cannot read rental lease documents'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select lives_ok(
  $$select public.v1_save_rental_property(
    '{
      "property_id":"84100000-0000-4000-8000-000000000010",
      "unit_code":"RU-DOC-01",
      "property_name":"Documented Shop",
      "property_type":"shop",
      "location":"Mussafah",
      "occupied":false
    }'::jsonb,
    null,
    '84100000-0000-4000-8000-000000000002'
  )$$,
  'Admin can create the rental target for controlled documents'
);

select throws_ok(
  $$select public.v1_prepare_rental_document_upload(
    '{
      "project_id":"84100000-0000-4000-8000-000000000010",
      "entity_type":"rental_property",
      "entity_id":"84100000-0000-4000-8000-000000000010",
      "classification":"operational",
      "file_name":"lease.pdf",
      "mime_type":"application/pdf",
      "byte_size":12,
      "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "origin":"uploaded"
    }'::jsonb,
    '84100000-0000-4000-8000-000000000003'
  )$$,
  '22023', 'V1_RENTAL_DOCUMENT_UPLOAD_PAYLOAD_INVALID',
  'Rental lease files cannot be downgraded from Commercial classification'
);

select lives_ok(
  $$select public.v1_prepare_rental_document_upload(
    '{
      "project_id":"84100000-0000-4000-8000-000000000010",
      "entity_type":"rental_property",
      "entity_id":"84100000-0000-4000-8000-000000000010",
      "classification":"commercial",
      "file_name":"lease.pdf",
      "mime_type":"application/pdf",
      "byte_size":12,
      "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "origin":"uploaded"
    }'::jsonb,
    '84100000-0000-4000-8000-000000000004'
  )$$,
  'Admin can prepare a private controlled lease upload'
);

set local role postgres;
select is(
  (
    select project_id
    from public.v1_document_upload_intents
    where idempotency_key = '84100000-0000-4000-8000-000000000004'
  ),
  null::uuid,
  'A rental upload never forges a project relationship'
);

select is(
  (
    select target_entity_type
    from public.v1_document_upload_intents
    where idempotency_key = '84100000-0000-4000-8000-000000000004'
  ),
  'rental_property',
  'The upload intent retains the exact rental property target'
);
create temporary table rental_resume_intent as
select id from public.v1_document_upload_intents
where idempotency_key='84100000-0000-4000-8000-000000000004';
grant select on rental_resume_intent to authenticated;
update public.v1_document_upload_intents
set created_at=clock_timestamp()-interval '16 minutes',
    expires_at=clock_timestamp()-interval '1 minute'
where id=(select id from rental_resume_intent);
set local role authenticated;
select is(
  public.v1_resume_document_upload((select id from rental_resume_intent),
    '84100000-0000-4000-8000-000000000004')->>'upload_intent_id',
  (select id::text from rental_resume_intent),
  'Admin renews the same expired commercial rental intent without forging project scope'
);

select lives_ok(
  $$select public.v1_prepare_rental_document_upload(
    '{
      "project_id":"84100000-0000-4000-8000-000000000010",
      "entity_type":"rental_property",
      "entity_id":"84100000-0000-4000-8000-000000000010",
      "classification":"commercial",
      "file_name":"lease.pdf",
      "mime_type":"application/pdf",
      "byte_size":12,
      "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "origin":"uploaded"
    }'::jsonb,
    '84100000-0000-4000-8000-000000000004'
  )$$,
  'A lost-response upload preparation retry replays the original result'
);

set local role postgres;
select is(
  (
    select count(*)::integer
    from public.v1_document_upload_intents
    where idempotency_key = '84100000-0000-4000-8000-000000000004'
  ),
  1,
  'Upload preparation retry cannot duplicate an intent'
);
set local role authenticated;

select is(
  jsonb_array_length(
    public.v1_rental_document_workspace_projection(
      '84100000-0000-4000-8000-000000000010'
    ) -> 'documents'
  ),
  0,
  'An unfinalized upload intent is never shown as a saved lease document'
);

select * from finish();
rollback;

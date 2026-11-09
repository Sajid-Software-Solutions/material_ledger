begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(28);

select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.v1_supplier_document_upload_metadata'::regclass,
     'public.v1_supplier_document_version_metadata'::regclass
   )),
  'Supplier document metadata tables enforce RLS'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.v1_supplier_document_upload_metadata', 'select'
  )
    and not has_table_privilege(
      'authenticated',
      'public.v1_supplier_document_version_metadata',
      'select'
    )
    and has_table_privilege(
      'service_role',
      'public.v1_supplier_document_version_metadata',
      'insert'
    )
    and not has_function_privilege(
      'authenticated',
      'public.v1_finalize_supplier_document_metadata()',
      'execute'
    ),
  'Metadata is reachable only through the protected supplier RPC/finalizer path'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'forged.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('a', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'other'
    ), '98100000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'V1_SUPPLIER_DOCUMENT_WRITE_DENIED',
  'Project Engineer cannot prepare supplier business evidence'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'untyped.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('b', 64),
      'origin', 'uploaded'
    ), '98100000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_UPLOAD_PAYLOAD_INVALID',
  'A controlled supplier document type is mandatory'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'unknown-type.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('c', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'quotation'
    ), '98100000-0000-4000-8000-000000000003'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_UPLOAD_PAYLOAD_INVALID',
  'An uncontrolled supplier document type is rejected'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'delivery-note.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('d', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note'
    ), '98100000-0000-4000-8000-000000000004'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_UPLOAD_PAYLOAD_INVALID',
  'Delivery Note requires a business reference'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'invoice.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('e', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'invoice',
      'business_reference', 'INV-001'
    ), '98100000-0000-4000-8000-000000000005'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_CLASSIFICATION_INVALID',
  'An Invoice cannot be mislabeled as operational evidence'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'oversized-notes.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('f', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'other',
      'supplier_document_notes', repeat('n', 1001)
    ), '98100000-0000-4000-8000-000000000006'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_UPLOAD_PAYLOAD_INVALID',
  'Supplier document notes are bounded to 1000 characters'
);

select ok(
  (public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'dn-9001.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('1', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note',
      'business_reference', '  DN-9001  ',
      'supplier_document_notes', '  Signed original  '
    ), '98100000-0000-4000-8000-000000000007'
  ) ->> 'object_path') like
    'documents/suppliers/00000000-0000-4000-8000-000000000389/%/content',
  'Procurement can prepare typed supplier evidence'
);

select is(
  public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'dn-9001.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('1', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note',
      'business_reference', '  DN-9001  ',
      'supplier_document_notes', '  Signed original  '
    ), '98100000-0000-4000-8000-000000000007'
  ) ->> 'upload_intent_id',
  public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'dn-9001.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('1', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note',
      'business_reference', '  DN-9001  ',
      'supplier_document_notes', '  Signed original  '
    ), '98100000-0000-4000-8000-000000000007'
  ) ->> 'upload_intent_id',
  'An exact prepare retry returns the same upload intent'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'operational',
      'file_name', 'dn-9001.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('1', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note',
      'business_reference', 'DN-CHANGED'
    ), '98100000-0000-4000-8000-000000000007'
  )$$,
  '22023', 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'An idempotency key cannot authorize changed business metadata'
);

set local role postgres;
select ok(
  exists(
    select 1
    from public.v1_supplier_document_upload_metadata metadata
    join public.v1_document_upload_intents intent
      on intent.id = metadata.upload_intent_id
    where intent.idempotency_key =
        '98100000-0000-4000-8000-000000000007'
      and metadata.supplier_document_type = 'delivery_note'
      and metadata.business_reference = 'DN-9001'
      and metadata.notes = 'Signed original'
  ),
  'Prepare persists normalized pending metadata beside the upload intent'
);

create temporary table v1_supplier_metadata_initial_intent as
select intent.id upload_intent_id, intent.object_path
from public.v1_document_upload_intents intent
where intent.idempotency_key = '98100000-0000-4000-8000-000000000007';
grant select on table v1_supplier_metadata_initial_intent
  to authenticated, service_role;
update public.v1_document_upload_intents
set created_at=clock_timestamp()-interval '16 minutes',
    expires_at=clock_timestamp()-interval '1 minute'
where id=(select upload_intent_id from v1_supplier_metadata_initial_intent);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select is(
  public.v1_resume_document_upload(
    (select upload_intent_id from v1_supplier_metadata_initial_intent),
    '98100000-0000-4000-8000-000000000007')->>'upload_intent_id',
  (select upload_intent_id::text from v1_supplier_metadata_initial_intent),
  'Procurement renews its expired supplier intent while retaining original typed metadata'
);
select lives_ok(
  $$insert into storage.objects(bucket_id, name, owner_id, metadata)
    values (
      'yorks-documents',
      (select object_path from v1_supplier_metadata_initial_intent),
      auth.uid()::text,
      '{"size":12,"mimetype":"application/pdf"}'::jsonb
    )$$,
  'The typed supplier upload intent permits its private Storage object'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.v1_create_document_version(
    (select upload_intent_id from v1_supplier_metadata_initial_intent),
    repeat('1', 64), 12, 'application/pdf'
  )$$,
  'Finalization atomically creates the document version and metadata snapshot'
);
select lives_ok(
  $$select public.v1_create_document_version(
    (select upload_intent_id from v1_supplier_metadata_initial_intent),
    repeat('1', 64), 12, 'application/pdf'
  )$$,
  'A finalizer retry remains idempotent'
);

set local role postgres;
select ok(
  (select count(*) = 1
   from public.v1_supplier_document_version_metadata metadata
   join public.v1_document_upload_intents intent
     on intent.id = metadata.upload_intent_id
   where intent.idempotency_key =
       '98100000-0000-4000-8000-000000000007')
    and exists(
      select 1
      from public.v1_supplier_document_version_metadata metadata
      join public.v1_document_upload_intents intent
        on intent.id = metadata.upload_intent_id
      where intent.idempotency_key =
          '98100000-0000-4000-8000-000000000007'
        and metadata.supplier_document_type = 'delivery_note'
        and metadata.business_reference = 'DN-9001'
        and metadata.notes = 'Signed original'
    ),
  'Finalizer retry cannot duplicate or alter the version metadata'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select ok(
  exists(
    select 1
    from jsonb_array_elements(
      public.v1_supplier_document_workspace_projection(
        '00000000-0000-4000-8000-000000000389'
      ) -> 'documents'
    ) document_record
    where document_record -> 'current_version'
      @> '{"supplier_document_type":"delivery_note","business_reference":"DN-9001","supplier_document_notes":"Signed original"}'::jsonb
  ),
  'Protected supplier workspace exposes the exact current metadata snapshot'
);

set local role postgres;
select throws_ok(
  $$update public.v1_supplier_document_version_metadata
    set notes = 'rewritten'$$,
  '42501', 'V1_SUPPLIER_DOCUMENT_METADATA_IMMUTABLE',
  'A finalized supplier document metadata snapshot is immutable'
);

create temporary table v1_supplier_metadata_document as
select intent.finalized_document_id document_id
from public.v1_document_upload_intents intent
where intent.idempotency_key = '98100000-0000-4000-8000-000000000007';
grant select on table v1_supplier_metadata_document to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'document_id', (select document_id from v1_supplier_metadata_document),
      'classification', 'operational',
      'file_name', 'dn-9001-revision-2.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 14,
      'sha256', repeat('2', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'delivery_note',
      'business_reference', 'DN-9001-REV-2',
      'supplier_document_notes', 'Corrected signed copy'
    ), '98100000-0000-4000-8000-000000000008'
  )$$,
  'A new revision may carry a corrected reference and note'
);

set local role postgres;
create temporary table v1_supplier_metadata_revision_intent as
select intent.id upload_intent_id, intent.object_path
from public.v1_document_upload_intents intent
where intent.idempotency_key = '98100000-0000-4000-8000-000000000008';
grant select on table v1_supplier_metadata_revision_intent
  to authenticated, service_role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$insert into storage.objects(bucket_id, name, owner_id, metadata)
    values (
      'yorks-documents',
      (select object_path from v1_supplier_metadata_revision_intent),
      auth.uid()::text,
      '{"size":14,"mimetype":"application/pdf"}'::jsonb
    )$$,
  'The replacement upload receives its own immutable Storage object'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.v1_create_document_version(
    (select upload_intent_id from v1_supplier_metadata_revision_intent),
    repeat('2', 64), 14, 'application/pdf'
  )$$,
  'The replacement finalizer persists revision-two metadata'
);

set local role postgres;
select ok(
  (select count(*) = 2
   from public.v1_supplier_document_version_metadata metadata
   where metadata.document_id = (
     select document_id from v1_supplier_metadata_document
   ))
    and exists(
      select 1
      from public.v1_supplier_document_version_metadata metadata
      join public.v1_document_versions version_record
        on version_record.id = metadata.document_version_id
      where metadata.document_id = (
          select document_id from v1_supplier_metadata_document
        )
        and version_record.revision_number = 1
        and metadata.business_reference = 'DN-9001'
        and metadata.notes = 'Signed original'
    )
    and exists(
      select 1
      from public.v1_supplier_document_version_metadata metadata
      join public.v1_document_versions version_record
        on version_record.id = metadata.document_version_id
      where metadata.document_id = (
          select document_id from v1_supplier_metadata_document
        )
        and version_record.revision_number = 2
        and metadata.business_reference = 'DN-9001-REV-2'
        and metadata.notes = 'Corrected signed copy'
    ),
  'Each revision preserves its exact type, reference, and note snapshot'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'document_id', (select document_id from v1_supplier_metadata_document),
      'classification', 'operational',
      'file_name', 'changed-type.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 14,
      'sha256', repeat('3', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'packing_list'
    ), '98100000-0000-4000-8000-000000000009'
  )$$,
  '22023', 'V1_SUPPLIER_DOCUMENT_TYPE_IMMUTABLE',
  'A replacement cannot change the controlled document family'
);

select lives_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'commercial',
      'file_name', 'invoice-9001.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('4', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'invoice',
      'business_reference', 'INV-9001'
    ), '98100000-0000-4000-8000-000000000010'
  )$$,
  'Procurement with live commercial authority can prepare an Invoice'
);

select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'admin_restricted',
      'file_name', 'restricted.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('5', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'other'
    ), '98100000-0000-4000-8000-000000000011'
  )$$,
  '42501', 'V1_SUPPLIER_DOCUMENT_WRITE_DENIED',
  'Procurement cannot prepare Admin Restricted supplier evidence'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'admin_restricted',
      'file_name', 'restricted.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('6', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'other'
    ), '98100000-0000-4000-8000-000000000012'
  )$$,
  'Admin can prepare Admin Restricted supplier evidence'
);

set local role postgres;
insert into public.v1_user_capabilities (
  auth_user_id, capability, is_granted, reason, changed_by_auth_user_id
) values (
  '10000000-0000-4000-8000-000000000003',
  'manage_commercials', false,
  'Supplier metadata commercial revocation proof',
  '10000000-0000-4000-8000-000000000004'
) on conflict (auth_user_id, capability) do update set
  is_granted = excluded.is_granted,
  reason = excluded.reason,
  changed_by_auth_user_id = excluded.changed_by_auth_user_id,
  updated_at = clock_timestamp();

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_prepare_supplier_document_upload(
    jsonb_build_object(
      'project_id', '00000000-0000-4000-8000-000000000389',
      'entity_type', 'supplier',
      'entity_id', '00000000-0000-4000-8000-000000000389',
      'classification', 'commercial',
      'file_name', 'revoked-invoice.pdf',
      'mime_type', 'application/pdf',
      'byte_size', 12,
      'sha256', repeat('7', 64),
      'origin', 'uploaded',
      'supplier_document_type', 'invoice',
      'business_reference', 'INV-REVOKED'
    ), '98100000-0000-4000-8000-000000000013'
  )$$,
  '42501', 'V1_SUPPLIER_DOCUMENT_WRITE_DENIED',
  'A live commercial-authority revocation blocks Invoice upload'
);

select * from finish();
rollback;

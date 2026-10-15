begin;

create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_prepare_accounts_document_upload(jsonb,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_get_accounts_documents(uuid,text,text,boolean)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_get_accounts_activity(uuid,text,text,uuid,timestamptz,timestamptz,integer,integer)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_get_accounts_export(text,uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_refresh_accounts_due_notifications()',
    'execute'
  )
  and not has_table_privilege(
    'authenticated','public.v1_accounts_document_metadata','select'
  ),
  'T06 exposes role-shaped RPCs while metadata and reminder internals stay private'
);

insert into public.v1_projects(
  id,project_ref,name,project_site,state,current_action_owner_role,
  created_by_auth_user_id,created_by_role
) values(
  '39610000-0000-4000-8000-000000000001','R39-T06-001',
  'Accounts document controls','Abu Dhabi','active','project_engineer',
  '10000000-0000-4000-8000-000000000004','admin'
);

insert into public.v1_project_scopes(
  id,project_id,scope_kind,scope_code,name,is_immutable
) values(
  '39620000-0000-4000-8000-000000000001',
  '39610000-0000-4000-8000-000000000001',
  'building','b01','Building 01',false
);

insert into public.v1_project_members(
  project_id,member_auth_user_id,project_role,effective_from,reason,
  assigned_by_auth_user_id,assigned_by_role
) values(
  '39610000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','project_engineer',
  clock_timestamp()-interval '1 day','T06 project engineer fixture',
  '10000000-0000-4000-8000-000000000004','admin'
),(
  '39610000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002','site_engineer',
  clock_timestamp()-interval '1 day','T06 site engineer fixture',
  '10000000-0000-4000-8000-000000000004','admin'
);

create temporary table v1_r39_t06_results(
  result_key text primary key,
  payload jsonb not null
);
grant select,insert,update on v1_r39_t06_results to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

insert into v1_r39_t06_results(result_key,payload)
select 'initialize',public.v1_initialize_project_commercial_baseline(
  '39610000-0000-4000-8000-000000000001',
  '2400000.00','AED','5.0000',20,10,
  jsonb_build_array(jsonb_build_object(
    'building_scope_id','39620000-0000-4000-8000-000000000001',
    'allocation_percent','100.0000'
  )),null,'{"always_required":false}'::jsonb,
  'Initialize T06 project','39690000-0000-4000-8000-000000000001'
);

reset role;

insert into public.v1_documents(
  id,classification,created_by_auth_user_id,created_by_role
) values(
  '39630000-0000-4000-8000-000000000001','commercial',
  '10000000-0000-4000-8000-000000000004','admin'
);
insert into public.v1_document_versions(
  id,document_id,revision_number,object_path,original_file_name,mime_type,
  byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role
) values(
  '39631000-0000-4000-8000-000000000001',
  '39630000-0000-4000-8000-000000000001',1,
  'documents/r39-t06/contract.pdf','R39-T06 Contract.pdf','application/pdf',
  2048,repeat('a',64),'uploaded',
  '10000000-0000-4000-8000-000000000004','admin'
);
update public.v1_documents
set current_version_id='39631000-0000-4000-8000-000000000001'
where id='39630000-0000-4000-8000-000000000001';
insert into public.v1_accounts_document_metadata(document_id,document_type)
values('39630000-0000-4000-8000-000000000001','contract');
insert into public.v1_document_links(
  id,document_id,project_id,entity_type,entity_id,
  linked_by_auth_user_id,linked_by_role
) values(
  '39632000-0000-4000-8000-000000000001',
  '39630000-0000-4000-8000-000000000001',
  '39610000-0000-4000-8000-000000000001','accounts_baseline_revision',
  (select current_baseline_revision_id
    from public.v1_accounts_project_commercial_profiles
    where project_id='39610000-0000-4000-8000-000000000001'),
  '10000000-0000-4000-8000-000000000004','admin'
);

insert into public.v1_audit_events(
  event_type,entity_type,entity_id,project_id,actor_auth_user_id,actor_role,
  actor_exact_role,idempotency_key,after_data
) values(
  'accounts.client_claim.ready_for_accounts','accounts_client_claim',
  '39640000-0000-4000-8000-000000000001',
  '39610000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','project_engineer',
  'project_engineer','39690000-0000-4000-8000-000000000002',
  '{"claim_reference":"R39-T06-CLM001","claim_amount":"500000.00"}'::jsonb
),(
  'accounts.supplier_bill.created','accounts_supplier_bill',
  '39640000-0000-4000-8000-000000000002',
  '39610000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003','procurement',
  'procurement','39690000-0000-4000-8000-000000000003',
  '{"supplier_invoice_reference":"SUP-T06-001","match_status":"blocked"}'::jsonb
);

select ok(
  exists(select 1 from public.v1_notifications
    where recipient_auth_user_id='10000000-0000-4000-8000-000000000013'
      and event_code='accounts_claim_ready'
      and entity_id='39640000-0000-4000-8000-000000000001')
  and exists(select 1 from public.v1_notifications
    where recipient_auth_user_id='10000000-0000-4000-8000-000000000003'
      and event_code='accounts_supplier_evidence_incomplete'
      and entity_id='39640000-0000-4000-8000-000000000002'),
  'Authoritative audit transitions derive scoped Accountant and Procurement notifications'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

insert into v1_r39_t06_results(result_key,payload)
select 'admin_documents',public.v1_get_accounts_documents(
  '39610000-0000-4000-8000-000000000001',null,null,false
);
select ok(
  (select jsonb_array_length(payload->'documents')=1
      and payload->'documents'->0->>'accounts_document_type'='contract'
      and payload->'documents'->0->'current_version'->>'sha256'=repeat('a',64)
      and jsonb_array_length(payload->'upload_targets')>=1
      and (payload->>'can_upload')::boolean
    from v1_r39_t06_results where result_key='admin_documents'),
  'Accounts document projection includes immutable versions, checksum, targets, and upload authority'
);

insert into v1_r39_t06_results(result_key,payload)
select 'admin_prepare',public.v1_prepare_accounts_document_upload(
  jsonb_build_object(
    'project_id','39610000-0000-4000-8000-000000000001',
    'entity_type','accounts_baseline_revision',
    'entity_id',(select payload->>'baseline_revision_id'
      from v1_r39_t06_results where result_key='initialize'),
    'document_id',null,'accounts_document_type','contract_variation',
    'classification','commercial','file_name','Variation 01.pdf',
    'mime_type','application/pdf','byte_size',4096,'sha256',repeat('b',64),
    'origin','uploaded','source_entity_type',null,'source_entity_id',null,
    'source_revision',null
  ),'39690000-0000-4000-8000-000000000004'
);

reset role;
update public.v1_document_upload_intents
set created_at=clock_timestamp()-interval '16 minutes',
    expires_at=clock_timestamp()-interval '1 minute'
where id=(select (payload->>'upload_intent_id')::uuid
  from v1_r39_t06_results where result_key='admin_prepare');
insert into v1_r39_t06_results(result_key,payload)
select 'prepare_metadata',jsonb_build_object(
  'captured',exists(select 1
    from public.v1_accounts_document_upload_metadata metadata
    where metadata.upload_intent_id=(select (payload->>'upload_intent_id')::uuid
      from v1_r39_t06_results where result_key='admin_prepare')
      and metadata.document_type='contract_variation')
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select is(
  public.v1_resume_document_upload(
    (select (payload->>'upload_intent_id')::uuid
      from v1_r39_t06_results where result_key='admin_prepare'),
    '39690000-0000-4000-8000-000000000004')->>'upload_intent_id',
  (select payload->>'upload_intent_id'
    from v1_r39_t06_results where result_key='admin_prepare'),
  'An authorized Accounts upload renews its original expired commercial intent'
);
select ok(
  (select payload->>'bucket_id'='yorks-documents'
      and payload->>'planned_revision_number'='1'
    from v1_r39_t06_results where result_key='admin_prepare')
  and (select (payload->>'captured')::boolean
    from v1_r39_t06_results where result_key='prepare_metadata'),
  'Accounts upload preparation reuses the private bucket and captures the controlled document type'
);

select throws_ok(
  $sql$select public.v1_prepare_accounts_document_upload(
    jsonb_build_object(
      'project_id','39610000-0000-4000-8000-000000000001',
      'entity_type','accounts_baseline_revision',
      'entity_id',(select payload->>'baseline_revision_id'
        from v1_r39_t06_results where result_key='initialize'),
      'document_id',null,'accounts_document_type','client_invoice',
      'classification','operational','file_name','invoice.pdf',
      'mime_type','application/pdf','byte_size',10,'sha256',repeat('c',64),
      'origin','uploaded','source_entity_type',null,'source_entity_id',null,
      'source_revision',null
    ),'39690000-0000-4000-8000-000000000005'
  )$sql$,
  '22023','R39_ACCOUNTS_DOCUMENT_CLASSIFICATION_INVALID',
  'Commercial Accounts evidence cannot be downgraded to operational classification'
);

insert into v1_r39_t06_results(result_key,payload)
select 'activity',public.v1_get_accounts_activity(
  '39610000-0000-4000-8000-000000000001',null,null,null,null,null,50,0
);
select ok(
  (select (payload->>'total')::integer>=3
      and jsonb_array_length(payload->'entries')>=3
      and payload->'entries'->0 ? 'actor_display_name'
    from v1_r39_t06_results where result_key='activity'),
  'Accounts activity is paged, attributable, and sourced from append-only audit facts'
);

insert into v1_r39_t06_results(result_key,payload)
select 'export',public.v1_get_accounts_export(
  'project_summary','39610000-0000-4000-8000-000000000001',
  '39690000-0000-4000-8000-000000000006'
);

reset role;
insert into v1_r39_t06_results(result_key,payload)
select 'export_audit',jsonb_build_object(
  'captured',exists(select 1 from public.v1_audit_events
    where event_type='accounts.export.generated'
      and idempotency_key='39690000-0000-4000-8000-000000000006')
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select ok(
  (select payload->>'report_kind'='project_summary'
      and payload->>'project_reference'='R39-T06-001'
      and payload->>'currency'='AED'
      and jsonb_array_length(payload->'columns')=13
      and jsonb_array_length(payload->'rows')=1
    from v1_r39_t06_results where result_key='export')
  and (select (payload->>'captured')::boolean
    from v1_r39_t06_results where result_key='export_audit'),
  'Export projection has one structured source model and records an attributable audit event'
);

select ok(
  (
    select bool_and(
      payload->>'report_kind'=kind
      and payload->>'project_reference'='R39-T06-001'
      and jsonb_typeof(payload->'columns')='array'
      and jsonb_array_length(payload->'columns')>0
      and jsonb_typeof(payload->'rows')='array'
      and not exists (
        select 1
        from jsonb_array_elements(payload->'rows') row_value
        where jsonb_array_length(row_value)
          <> jsonb_array_length(payload->'columns')
      )
    )
    from unnest(array[
      'commercial_baseline','building_allocations','stage_allocations',
      'billing_progress','progress_history','client_claims','claim_lines',
      'client_invoices','certifications','client_receipts','pdc_register',
      'pdc_events','supplier_bills','supplier_payments','accounts_documents',
      'accounts_activity'
    ]) kind
    cross join lateral (
      select public.v1_get_accounts_export(
        kind,'39610000-0000-4000-8000-000000000001',gen_random_uuid()
      ) payload
    ) report
  ),
  'Complete project backup exposes every authorized Accounts register with a stable tabular shape'
);

select throws_ok(
  $$select public.v1_get_accounts_export(
    'unsupported','39610000-0000-4000-8000-000000000001',gen_random_uuid()
  )$$,
  '22023','R39_ACCOUNTS_EXPORT_KIND_INVALID',
  'Unknown export kinds fail closed'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
insert into v1_r39_t06_results(result_key,payload)
select 'site_documents',public.v1_get_accounts_documents(
  '39610000-0000-4000-8000-000000000001',null,null,false
);
select is(
  (select jsonb_array_length(payload->'documents')
    from v1_r39_t06_results where result_key='site_documents'),
  0,
  'Site Engineer project access never reveals protected commercial documents'
);
select throws_ok(
  $$select public.v1_get_accounts_export(
    'project_summary','39610000-0000-4000-8000-000000000001',
    '39690000-0000-4000-8000-000000000007'
  )$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED',
  'Site Engineer cannot export Accounts registers'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select throws_ok(
  $$select public.v1_get_accounts_documents(
    '39610000-0000-4000-8000-000000000001',null,null,false
  )$$,
  '42501','R39_ACCOUNTS_ACCESS_DENIED',
  'Procurement supplier-cost authority does not unlock the client Accounts document register'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',
  true
);
select throws_like(
  $$select public.v1_refresh_accounts_due_notifications()$$,
  '%permission denied for function v1_refresh_accounts_due_notifications%',
  'Only the trusted service reminder job can materialize due-state notifications'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select ok(
  (select count(*)
   from public.v1_capability_catalog catalog
   where public.v1_accounts_is_capability_key(catalog.capability_key)
     and catalog.status = 'operational'
     and catalog.authorization_mode = 'enforced'
     and catalog.is_assignable) = 15
  and (select count(*)
   from public.v1_capability_catalog catalog
   where public.v1_accounts_is_capability_key(catalog.capability_key)
     and catalog.status = 'planned'
     and catalog.authorization_mode = 'shadow'
     and not catalog.is_assignable) = 0,
  'The six T02 consumers remain operational after the accepted T03-T06 promotions'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_project_commercial_profiles'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_baseline_revisions'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_baseline_building_allocations'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_baseline_stage_allocations'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_billing_progress'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_billing_progress_revisions'::regclass)
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_baseline_revisions', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_billing_progress', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_billing_progress_revisions', 'update'
  ),
  'All T02 relations are RLS protected and unavailable through direct Data API access'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_initialize_project_commercial_baseline(uuid,text,text,text,integer,integer,jsonb,jsonb,jsonb,text,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_suggest_billing_progress(uuid,uuid,integer,text,text,uuid[],text,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_get_project_commercial_baseline(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_list_project_commercial_baseline_revisions(uuid,integer,integer)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_list_billing_progress_revisions(uuid,uuid,integer,integer)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_accounts_materialize_baseline_dimensions(uuid,uuid,jsonb,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_accounts_stage_value(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_accounts_stage_value(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_accounts_baseline_snapshot(uuid,boolean)',
    'execute'
  ),
  'Authenticated callers receive only public T02 RPC seams, never internal helpers'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  (
    '39210000-0000-4000-8000-000000000001', 'R39-T02-001',
    'R39 Accounts baseline and progress test', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39210000-0000-4000-8000-000000000002', 'R39-T02-002',
    'R39 Accounts correlation guard test', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values
  (
    '39220000-0000-4000-8000-000000000001',
    '39210000-0000-4000-8000-000000000001',
    'common', 'common', 'Common / All Buildings', true
  ),
  (
    '39220000-0000-4000-8000-000000000002',
    '39210000-0000-4000-8000-000000000001',
    'building', 'b01', 'Building 01', false
  ),
  (
    '39220000-0000-4000-8000-000000000003',
    '39210000-0000-4000-8000-000000000001',
    'building', 'b02', 'Building 02', false
  ),
  (
    '39220000-0000-4000-8000-000000000004',
    '39210000-0000-4000-8000-000000000002',
    'building', 'other', 'Other Project Building', false
  ),
  (
    '39220000-0000-4000-8000-000000000005',
    '39210000-0000-4000-8000-000000000002',
    'building', 'other-b', 'Other Project Building B', false
  ),
  (
    '39220000-0000-4000-8000-000000000006',
    '39210000-0000-4000-8000-000000000002',
    'building', 'other-c', 'Other Project Building C', false
  ),
  (
    '39220000-0000-4000-8000-000000000007',
    '39210000-0000-4000-8000-000000000001',
    'building', 'archived', 'Archived Building', false
  );

update public.v1_project_scopes
set is_active = false
where id = '39220000-0000-4000-8000-000000000007';

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  (
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001', 'project_engineer',
    clock_timestamp() - interval '1 day', 'T02 confirmation authority',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002', 'site_engineer',
    clock_timestamp() - interval '1 day', 'T02 suggestion authority',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

-- One operational reference may support T02 progress. The commercial fixture
-- proves that a project link alone cannot make protected evidence Site-safe.
insert into public.v1_documents (
  id, classification, created_by_auth_user_id, created_by_role
) values
  (
    '39240000-0000-4000-8000-000000000001', 'operational',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39240000-0000-4000-8000-000000000002', 'commercial',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39240000-0000-4000-8000-000000000003', 'operational',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39240000-0000-4000-8000-000000000004', 'operational',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39240000-0000-4000-8000-000000000005', 'operational',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39240000-0000-4000-8000-000000000006', 'operational',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_document_versions (
  id, document_id, revision_number, object_path, original_file_name,
  mime_type, byte_size, sha256, origin,
  uploaded_by_auth_user_id, uploaded_by_role
) values
  (
    '39241000-0000-4000-8000-000000000001',
    '39240000-0000-4000-8000-000000000001', 1,
    'r39/t02/operational-progress.pdf', 'operational-progress.pdf',
    'application/pdf', 128, repeat('a', 64), 'uploaded',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39241000-0000-4000-8000-000000000002',
    '39240000-0000-4000-8000-000000000002', 1,
    'r39/t02/commercial-progress.pdf', 'commercial-progress.pdf',
    'application/pdf', 128, repeat('b', 64), 'uploaded',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39241000-0000-4000-8000-000000000003',
    '39240000-0000-4000-8000-000000000003', 1,
    'r39/t02/other-project.pdf', 'other-project.pdf',
    'application/pdf', 128, repeat('c', 64), 'uploaded',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39241000-0000-4000-8000-000000000004',
    '39240000-0000-4000-8000-000000000004', 1,
    'r39/t02/cross-linked.pdf', 'cross-linked.pdf',
    'application/pdf', 128, repeat('d', 64), 'uploaded',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39241000-0000-4000-8000-000000000006',
    '39240000-0000-4000-8000-000000000006', 1,
    'r39/t02/archived.pdf', 'archived.pdf',
    'application/pdf', 128, repeat('e', 64), 'uploaded',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

update public.v1_documents
set current_version_id = case id
  when '39240000-0000-4000-8000-000000000001'::uuid
    then '39241000-0000-4000-8000-000000000001'::uuid
  when '39240000-0000-4000-8000-000000000003'::uuid
    then '39241000-0000-4000-8000-000000000003'::uuid
  when '39240000-0000-4000-8000-000000000004'::uuid
    then '39241000-0000-4000-8000-000000000004'::uuid
  when '39240000-0000-4000-8000-000000000006'::uuid
    then '39241000-0000-4000-8000-000000000006'::uuid
  else '39241000-0000-4000-8000-000000000002'::uuid
end
where id in (
  '39240000-0000-4000-8000-000000000001',
  '39240000-0000-4000-8000-000000000002',
  '39240000-0000-4000-8000-000000000003',
  '39240000-0000-4000-8000-000000000004',
  '39240000-0000-4000-8000-000000000006'
);

insert into public.v1_document_links (
  id, document_id, project_id, entity_type, entity_id,
  linked_by_auth_user_id, linked_by_role
) values
  (
    '39242000-0000-4000-8000-000000000001',
    '39240000-0000-4000-8000-000000000001',
    '39210000-0000-4000-8000-000000000001', 'project',
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000002',
    '39240000-0000-4000-8000-000000000002',
    '39210000-0000-4000-8000-000000000001', 'project',
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000003',
    '39240000-0000-4000-8000-000000000003',
    '39210000-0000-4000-8000-000000000002', 'project',
    '39210000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000004',
    '39240000-0000-4000-8000-000000000004',
    '39210000-0000-4000-8000-000000000001', 'project',
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000005',
    '39240000-0000-4000-8000-000000000004',
    '39210000-0000-4000-8000-000000000002', 'project',
    '39210000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000006',
    '39240000-0000-4000-8000-000000000005',
    '39210000-0000-4000-8000-000000000001', 'project',
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39242000-0000-4000-8000-000000000007',
    '39240000-0000-4000-8000-000000000006',
    '39210000-0000-4000-8000-000000000001', 'project',
    '39210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_accounts_document_metadata (
  document_id, document_type, archived_at, archived_by_auth_user_id,
  archive_reason
) values (
  '39240000-0000-4000-8000-000000000006', 'progress_evidence',
  clock_timestamp(), '10000000-0000-4000-8000-000000000004',
  'T02 archived evidence fixture'
);

select ok(
  has_function_privilege('authenticated',
    'public.v1_accounts_search_progress_evidence(uuid,text,uuid[],integer)',
    'execute')
  and not has_function_privilege('anon',
    'public.v1_accounts_search_progress_evidence(uuid,text,uuid[],integer)',
    'execute')
  and not has_function_privilege('authenticated',
    'public.v1_accounts_validate_evidence_documents(uuid,uuid[])',
    'execute'),
  'Evidence search is authenticated; command validator remains an internal seam'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  jsonb_array_length(result -> 'documents') = 1
  and result #>> '{documents,0,file_name}' = 'operational-progress.pdf'
  and result #>> '{documents,0,current_version_id}' =
    '39241000-0000-4000-8000-000000000001'
  and jsonb_array_length(result -> 'selected') = 1
  and result #>> '{selected,0,id}' =
    '39240000-0000-4000-8000-000000000001'
  and not result::text like '%other-project.pdf%'
  and not result::text like '%commercial-progress.pdf%'
  and not result ? 'contract_value',
  'Site Engineer sees one authorized current document without commercial values'
)
from (
  select public.v1_accounts_search_progress_evidence(
    '39210000-0000-4000-8000-000000000001', null,
    array[
      '39240000-0000-4000-8000-000000000001'::uuid,
      '39240000-0000-4000-8000-000000000002'::uuid,
      '39240000-0000-4000-8000-000000000003'::uuid,
      '39240000-0000-4000-8000-000000000004'::uuid,
      '39240000-0000-4000-8000-000000000005'::uuid,
      '39240000-0000-4000-8000-000000000006'::uuid
    ], 20
  ) as result
) evidence;

select ok(
  jsonb_array_length(result -> 'documents') = 0
  and jsonb_array_length(result -> 'selected') = 0,
  'Unfinalized and archived evidence cannot be selected; archived names are hidden'
)
from (
  select public.v1_accounts_search_progress_evidence(
    '39210000-0000-4000-8000-000000000001', 'archived',
    array[
      '39240000-0000-4000-8000-000000000005'::uuid,
      '39240000-0000-4000-8000-000000000006'::uuid
    ], 20
  ) as result
) evidence;

select ok(
  jsonb_array_length(result -> 'documents') = 0
  and jsonb_array_length(result -> 'selected') = 0,
  'Searching by a cross-project file name or selecting its ID reveals nothing'
)
from (
  select public.v1_accounts_search_progress_evidence(
    '39210000-0000-4000-8000-000000000001', 'other-project',
    array['39240000-0000-4000-8000-000000000003'::uuid], 20
  ) as result
) evidence;

select ok(
  jsonb_array_length(result -> 'selected') = 0,
  'A readable project link cannot expose evidence with another unreadable live link'
)
from (
  select public.v1_accounts_search_progress_evidence(
    '39210000-0000-4000-8000-000000000001', 'cross-linked',
    array['39240000-0000-4000-8000-000000000004'::uuid], 20
  ) as result
) evidence;

select throws_ok(
  $$select public.v1_accounts_search_progress_evidence(
    '39210000-0000-4000-8000-000000000001', null,
    '{}'::uuid[], 21)$$,
  '22023', 'R39_ACCOUNTS_EVIDENCE_SEARCH_INVALID',
  'Unbounded result limits are rejected by the server'
);

reset role;

create temporary table v1_r39_t02_results (
  result_key text primary key,
  payload jsonb not null
);
grant select, insert, update on table v1_r39_t02_results to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

insert into v1_r39_t02_results (result_key, payload)
select 'initialize', public.v1_initialize_project_commercial_baseline(
  '39210000-0000-4000-8000-000000000001',
  '1000000.00', 'AED', '5.0000', null, null,
  jsonb_build_array(
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000002',
      'allocation_percent', '60.0000'
    ),
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000003',
      'allocation_percent', '40.0000'
    )
  ),
  null,
  '{"always_required":true}'::jsonb,
  'Approve the initial commercial baseline',
  '39290000-0000-4000-8000-000000000001'
);

select ok(
  (payload ->> 'replayed')::boolean = false
  and payload ->> 'status' = 'current'
  and (payload ->> 'record_version')::integer = 1
  and (payload ->> 'baseline_revision_number')::integer = 1,
  'Admin initializes one explicit-VAT versioned baseline'
)
from v1_r39_t02_results where result_key = 'initialize';

select ok(
  (public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001',
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '60.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '40.0000'
      )
    ), null, '{"always_required":true}'::jsonb,
    'Approve the initial commercial baseline',
    '39290000-0000-4000-8000-000000000001'
  ) ->> 'replayed')::boolean,
  'An identical initialize retry reconciles to the original response'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001',
    '1000001.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '60.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '40.0000'
      )
    ), null, '{"always_required":true}'::jsonb,
    'Changed payload reusing one command key',
    '39290000-0000-4000-8000-000000000001'
  )$$,
  '22023', 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'An idempotency key cannot be reused with a different payload'
);

reset role;

select ok(
  (select count(*) from public.v1_accounts_baseline_revisions
   where project_id = '39210000-0000-4000-8000-000000000001') = 1
  and (select count(*) from public.v1_accounts_billing_progress
   where project_id = '39210000-0000-4000-8000-000000000001') = 10
  and not exists (
    select 1 from public.v1_accounts_baseline_building_allocations
    where project_scope_id = '39220000-0000-4000-8000-000000000001'
  )
  and (select row(payment_terms_days, reminder_lead_days)::text
    from public.v1_accounts_baseline_revisions
    where project_id = '39210000-0000-4000-8000-000000000001'
      and status = 'current') = '(90,10)',
  'Initialization applies protected 90/10 defaults, five stages per physical building and excludes Common'
);

select is(
  (select string_agg(
     stage_key || ':' || allocation_percent::text,
     ',' order by display_order
   )
   from public.v1_accounts_baseline_stage_allocations
   where project_id = '39210000-0000-4000-8000-000000000001'),
  'design:10.0000,material_supply:50.0000,installation:30.0000,commissioning_handover:5.0000,energizing:5.0000',
  'Default stage allocations remain exactly 10/50/30/5/5'
);

select throws_ok(
  $command$
  do $body$
  declare
    v_allocation_id uuid;
  begin
    select allocation.id into v_allocation_id
    from public.v1_accounts_baseline_building_allocations allocation
    where allocation.project_id =
      '39210000-0000-4000-8000-000000000001'
    order by allocation.id
    limit 1;
    delete from public.v1_accounts_billing_progress
    where building_allocation_id = v_allocation_id;
    delete from public.v1_accounts_baseline_building_allocations
    where id = v_allocation_id;
    set constraints v1_accounts_validate_building_totals immediate;
  end
  $body$;
  $command$,
  '23514', 'R39_ACCOUNTS_INVALID_BUILDING_ALLOCATIONS',
  'Deferred allocation validation handles DELETE through OLD and rejects an invalid total'
);
set constraints all deferred;

create temporary table v1_r39_t02_target as
select progress.id as progress_entry_id
from public.v1_accounts_billing_progress progress
where progress.project_id = '39210000-0000-4000-8000-000000000001'
  and progress.project_scope_id = '39220000-0000-4000-8000-000000000002'
  and progress.stage_key = 'design';
grant select on table v1_r39_t02_target to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '100.001', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '100.0000'
      )
    ), null, '{}'::jsonb, 'Invalid precision',
    '39290000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_NUMERIC',
  'Money scale is rejected before any constrained cast can round it'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    '0.00', 'AED', '0.0000', null, null,
    jsonb_build_array(jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '100.0000'
    )), null, '{}'::jsonb, 'Reject zero baseline',
    '39290000-0000-4000-8000-000000000021'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_CONTRACT_VALUE',
  'AT-BL-001 rejects a zero contract baseline'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    '-1.00', 'AED', '0.0000', null, null,
    jsonb_build_array(jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '100.0000'
    )), null, '{}'::jsonb, 'Reject negative baseline',
    '39290000-0000-4000-8000-000000000022'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_CONTRACT_VALUE',
  'AT-BL-001 rejects a negative contract baseline'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    'not-money', 'AED', '0.0000', null, null,
    jsonb_build_array(jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '100.0000'
    )), null, '{}'::jsonb, 'Reject malformed baseline',
    '39290000-0000-4000-8000-000000000023'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_NUMERIC',
  'Malformed client money never reaches numeric authority'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    'NaN', 'AED', '0.0000', null, null,
    jsonb_build_array(jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '100.0000'
    )), null, '{}'::jsonb, 'Reject NaN baseline',
    '39290000-0000-4000-8000-000000000024'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_NUMERIC',
  'NaN text never reaches numeric authority'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    '1.00', 'AED', '0.0000', 30, 31,
    jsonb_build_array(jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '100.0000'
    )), null, '{}'::jsonb, 'Reject reminder beyond terms',
    '39290000-0000-4000-8000-000000000025'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_TERMS',
  'AT-BL-005 rejects reminder lead greater than payment terms'
);

select throws_ok(
  $$select public.v1_initialize_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000002',
    '1.00', 'AED', '0.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000004',
        'allocation_percent', '33.3330'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000005',
        'allocation_percent', '33.3330'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000006',
        'allocation_percent', '33.3330'
      )
    ), null, '{}'::jsonb, 'Reject 99.999 allocation total',
    '39290000-0000-4000-8000-000000000026'
  )$$,
  '23514', 'R39_ACCOUNTS_INVALID_BUILDING_ALLOCATIONS',
  'AT-BL-002 rejects 99.999 percent outside the approved tolerance'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '50.0000'
      )
    ), null, '{}'::jsonb, 'Invalid allocation total',
    '39290000-0000-4000-8000-000000000003'
  )$$,
  '23514', 'R39_ACCOUNTS_INVALID_BUILDING_ALLOCATIONS',
  'Physical-building allocations must total one hundred percent'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '50.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '50.0000'
      )
    ), null, '{}'::jsonb, 'Reject duplicate building scope',
    '39290000-0000-4000-8000-000000000018'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_BUILDING_ALLOCATIONS',
  'Duplicate physical-building allocation IDs fail before persistence'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '60.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '40.0000'
      )
    ), jsonb_build_array(
      jsonb_build_object(
        'stage_key', 'duplicate', 'stage_label', 'One',
        'allocation_percent', '50.0000', 'position', 1
      ),
      jsonb_build_object(
        'stage_key', 'duplicate', 'stage_label', 'Two',
        'allocation_percent', '50.0000', 'position', 2
      )
    ), '{}'::jsonb, 'Reject duplicate stage key',
    '39290000-0000-4000-8000-000000000019'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_STAGE_ALLOCATIONS',
  'Duplicate billing-stage keys fail before persistence'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '60.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '40.0000'
      )
    ), jsonb_build_array(
      jsonb_build_object(
        'stage_key', 'stage_one', 'stage_label', 'One',
        'allocation_percent', '50.0000', 'position', 1
      ),
      jsonb_build_object(
        'stage_key', 'stage_two', 'stage_label', 'Two',
        'allocation_percent', '50.0000', 'position', 1
      )
    ), '{}'::jsonb, 'Reject duplicate stage position',
    '39290000-0000-4000-8000-000000000020'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_STAGE_ALLOCATIONS',
  'Duplicate billing-stage positions fail before persistence'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '60.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '40.0000'
      )
    ), null, '{"invented_rule":true}'::jsonb,
    'Unknown policy keys must fail closed',
    '39290000-0000-4000-8000-000000000016'
  )$$,
  '22023', 'R39_ACCOUNTS_REVIEW_POLICY_INVALID',
  'Management review policy rejects every unapproved configuration key'
);

select throws_ok(
  $$select public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1000000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000001',
        'allocation_percent', '100.0000'
      )
    ), null, '{}'::jsonb, 'Common is not physical',
    '39290000-0000-4000-8000-000000000004'
  )$$,
  '23514', 'R39_ACCOUNTS_COMMON_SCOPE_FORBIDDEN',
  'Common scope cannot be inserted as a physical commercial allocation'
);

select throws_ok(
  $$update public.v1_accounts_billing_progress
    set suggested_percent = 99 where project_id =
      '39210000-0000-4000-8000-000000000001'$$,
  '42501', 'permission denied for table v1_accounts_billing_progress',
  'Authenticated callers cannot bypass progress commands with a direct update'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  not ((public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) -> 'baseline') ? 'contract_value')
  and not exists (
    select 1
    from jsonb_array_elements(public.v1_get_project_commercial_baseline(
      '39210000-0000-4000-8000-000000000001'
    ) -> 'building_allocations') allocation
    where allocation ? 'allocated_value'
  )
  and not exists (
    select 1
    from jsonb_array_elements(public.v1_get_project_commercial_baseline(
      '39210000-0000-4000-8000-000000000001'
    ) -> 'stage_allocations') allocation
    where allocation ? 'stage_value'
  ),
  'Site baseline projection omits every protected monetary key'
);

select ok(
  jsonb_array_length(public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) -> 'physical_buildings') = 2
  and not exists (
    select 1
    from jsonb_array_elements(public.v1_get_project_commercial_baseline(
      '39210000-0000-4000-8000-000000000001'
    ) -> 'physical_buildings') building
    where building ->> 'scope_code' in ('common', 'archived')
  )
  and jsonb_array_length(public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) -> 'stage_templates') = 5
  and (
    select sum((stage ->> 'allocation_percent')::numeric)
    from jsonb_array_elements(public.v1_get_project_commercial_baseline(
      '39210000-0000-4000-8000-000000000001'
    ) -> 'stage_templates') stage
  ) = 100.0000,
  'Baseline editor projection supplies only active physical buildings and the protected 100 percent stage template'
);

select ok(
  not ((public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001', null, null, null, null
  ) -> 'totals') ? 'contract_value')
  and not exists (
    select 1
    from jsonb_array_elements(public.v1_list_billing_progress(
      '39210000-0000-4000-8000-000000000001', null, null, null, null
    ) -> 'progress') progress
    where progress ? 'stage_value'
       or progress ? 'confirmed_eligible'
       or progress ? 'previously_claimed_amount'
       or progress ? 'available_to_claim'
  ),
  'Site progress projection omits all money and eligibility values'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    1, '-1.0000', 'Range validation', '{}'::uuid[],
    'Reject negative progress',
    '39290000-0000-4000-8000-000000000027'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_PROGRESS_PERCENT',
  'AT-PROG-001 rejects negative Site progress'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    1, '101.0000', 'Range validation', '{}'::uuid[],
    'Reject progress above one hundred',
    '39290000-0000-4000-8000-000000000028'
  )$$,
  '22023', 'R39_ACCOUNTS_INVALID_PROGRESS_PERCENT',
  'AT-PROG-001 rejects Site progress above one hundred'
);

insert into v1_r39_t02_results (result_key, payload)
select 'suggest', public.v1_suggest_billing_progress(
  '39210000-0000-4000-8000-000000000001',
  (select progress_entry_id from v1_r39_t02_target),
  1, '80.0000', 'Site progress observation', '{}'::uuid[],
  'Site suggestion after inspection',
  '39290000-0000-4000-8000-000000000005'
);

select ok(
  payload ->> 'status' = 'not_required'
  and (payload ->> 'record_version')::integer = 2
  and not (payload ->> 'replayed')::boolean,
  'Site Engineer records a reasoned suggestion without needing a document'
)
from v1_r39_t02_results where result_key = 'suggest';

select ok(
  (public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    1, '80.0000', 'Site progress observation', '{}'::uuid[],
    'Site suggestion after inspection',
    '39290000-0000-4000-8000-000000000005'
  ) ->> 'replayed')::boolean,
  'A suggestion retry reconciles without a second revision'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '30.0000', null,
    array['39240000-0000-4000-8000-000000000002'::uuid],
    'Protected evidence must fail closed',
    '39290000-0000-4000-8000-000000000006'
  )$$,
  '22023', 'R39_ACCOUNTS_EVIDENCE_DOCUMENT_INVALID',
  'Commercial evidence is rejected even when linked to the project'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '30.0000', null,
    array['39240000-0000-4000-8000-000000000003'::uuid],
    'Cross-project evidence must fail closed',
    '39290000-0000-4000-8000-000000000030'
  )$$,
  '22023', 'R39_ACCOUNTS_EVIDENCE_DOCUMENT_INVALID',
  'Direct command substitution with a different project document is rejected'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '30.0000', null,
    array['39240000-0000-4000-8000-000000000004'::uuid],
    'Cross-linked evidence must fail closed',
    '39290000-0000-4000-8000-000000000031'
  )$$,
  '22023', 'R39_ACCOUNTS_EVIDENCE_DOCUMENT_INVALID',
  'The save command rejects a project-linked document with another unreadable link'
);

select throws_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '20.0000', 'Unauthorized Site confirmation',
    array['39240000-0000-4000-8000-000000000001'::uuid],
    'Site cannot confirm',
    '39290000-0000-4000-8000-000000000007'
  )$$,
  '42501', 'R39_ACCOUNTS_ACCESS_DENIED',
  'Site Engineer cannot confirm commercial progress'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '60.0000', 'Summary is not confirmation evidence', '{}'::uuid[],
    'Try confirmation without an authorized document',
    '39290000-0000-4000-8000-000000000008'
  )$$,
  '22023', 'R39_ACCOUNTS_CONFIRMATION_EVIDENCE_REQUIRED',
  'An increase cannot be confirmed from a summary alone'
);

insert into v1_r39_t02_results (result_key, payload)
select 'confirm', public.v1_confirm_billing_progress(
  '39210000-0000-4000-8000-000000000001',
  (select progress_entry_id from v1_r39_t02_target),
  2, '60.0000', 'Confirmed against operational report',
  array['39240000-0000-4000-8000-000000000001'::uuid],
  'Project Engineer confirms inspected progress',
  '39290000-0000-4000-8000-000000000009'
);

select ok(
  payload ->> 'status' = 'pending'
  and (payload ->> 'record_version')::integer = 3,
  'Configured management review blocks newly confirmed value as pending'
)
from v1_r39_t02_results where result_key = 'confirm';

select throws_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '61.0000', 'Stale competing confirmation',
    array['39240000-0000-4000-8000-000000000001'::uuid],
    'Competing writer must refresh',
    '39290000-0000-4000-8000-000000000010'
  )$$,
  '40001', 'R39_ACCOUNTS_STALE_VERSION',
  'Optimistic versioning rejects a competing stale progress write'
);

select ok(
  jsonb_typeof(public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000002', 'design', null, null
  ) #> '{progress,0,stage_value}') = 'string'
  and public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000002', 'design', null, null
  ) #>> '{progress,0,stage_value}' = '60000.00'
  and public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000002', 'design', null, null
  ) #>> '{progress,0,suggested_percent}' = '80.0000'
  and public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000002', 'design', null, null
  ) #>> '{progress,0,confirmed_percent}' = '60.0000'
  and public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000002', 'design', null, null
  ) #>> '{progress,0,confirmed_eligible}' = '36000.00',
  'AT-PROG-003 preserves 80/60 facts and derives eligibility only from confirmed 60%'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

insert into v1_r39_t02_results (result_key, payload)
select 'review', public.v1_review_commercial_progress(
  '39210000-0000-4000-8000-000000000001',
  (select progress_entry_id from v1_r39_t02_target),
  3, 'approved', 'Management verified the operational evidence',
  '39290000-0000-4000-8000-000000000011'
);

select ok(
  payload ->> 'status' = 'approved'
  and (payload ->> 'record_version')::integer = 4,
  'Authorized management approves a pending progress confirmation'
)
from v1_r39_t02_results where result_key = 'review';

select ok(
  (public.v1_review_commercial_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    3, 'approved', 'Management verified the operational evidence',
    '39290000-0000-4000-8000-000000000011'
  ) ->> 'replayed')::boolean,
  'A review retry reconciles without duplicating the audit revision'
);

select ok(
  jsonb_array_length(public.v1_list_billing_progress_revisions(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target), null, 50
  ) -> 'revisions') = 3
  and (select string_agg(value ->> 'action', ',' order by
        (value ->> 'revision_number')::integer)
    from jsonb_array_elements(public.v1_list_billing_progress_revisions(
      '39210000-0000-4000-8000-000000000001',
      (select progress_entry_id from v1_r39_t02_target), null, 50
    ) -> 'revisions') value) = 'suggested,confirmed,reviewed'
  and jsonb_typeof(public.v1_list_billing_progress_revisions(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target), null, 50
  ) #> '{revisions,0,new_confirmed_percent}') = 'string',
  'Append-only revision projection preserves the full typed before/after story'
);

with first_page as (
  select public.v1_list_billing_progress_revisions(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target), null, 1
  ) as payload
), second_page as (
  select public.v1_list_billing_progress_revisions(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    (first_page.payload ->> 'next_cursor')::integer,
    1
  ) as payload
  from first_page
)
select ok(
  (select payload ->> 'next_cursor' = '3' from first_page)
  and (select payload #>> '{revisions,0,revision_number}' = '3'
       from first_page)
  and (select payload #>> '{revisions,0,revision_number}' = '2'
       from second_page),
  'Progress history uses the immutable revision number as a tie-safe cursor'
);

reset role;

create or replace function public.v1_accounts_consumed_claim_amount(
  p_progress_entry_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$ select 13000::numeric; $$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    4, '10.0000', null, '{}'::uuid[],
    'Reduction must respect downstream claims',
    '39290000-0000-4000-8000-000000000012'
  )$$,
  '23514', 'R39_ACCOUNTS_CONFIRMED_BELOW_CLAIMED_BASIS',
  'The protected T03 seam prevents confirmation below consumed claim basis'
);

reset role;
create or replace function public.v1_accounts_consumed_claim_amount(
  p_progress_entry_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$ select 0::numeric; $$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    4, '50.0000', null, '{}'::uuid[],
    'Approved controlled decrease without new evidence',
    '39290000-0000-4000-8000-000000000030'
  )$$,
  'An equal or decreased confirmation has no generic evidence requirement'
);

reset role;

select throws_ok(
  $$insert into public.v1_accounts_baseline_stage_allocations (
      baseline_revision_id, project_id, stage_key, stage_name,
      display_order, allocation_percent
    ) values (
      (select current_baseline_revision_id
       from public.v1_accounts_project_commercial_profiles
       where project_id = '39210000-0000-4000-8000-000000000001'),
      '39210000-0000-4000-8000-000000000002',
      'cross_project', 'Cross project', 99, 1
    )$$,
  '23514', 'R39_ACCOUNTS_STAGE_PROJECT_MISMATCH',
  'Stage allocation rows cannot cross project and baseline dimensions'
);

select throws_ok(
  $$insert into public.v1_accounts_baseline_building_allocations (
      baseline_revision_id, project_id, project_scope_id, allocation_percent
    ) values (
      (select current_baseline_revision_id
       from public.v1_accounts_project_commercial_profiles
       where project_id = '39210000-0000-4000-8000-000000000001'),
      '39210000-0000-4000-8000-000000000001',
      '39220000-0000-4000-8000-000000000004', 1
    )$$,
  '23514', 'R39_ACCOUNTS_BUILDING_PROJECT_MISMATCH',
  'Building allocation rows cannot reference another project scope'
);

select throws_ok(
  $$insert into public.v1_accounts_billing_progress (
      project_id, baseline_revision_id, building_allocation_id,
      stage_allocation_id, project_scope_id, stage_key
    ) select
      '39210000-0000-4000-8000-000000000002',
      progress.baseline_revision_id, progress.building_allocation_id,
      progress.stage_allocation_id, progress.project_scope_id,
      progress.stage_key
    from public.v1_accounts_billing_progress progress
    where progress.id = (select progress_entry_id from v1_r39_t02_target)$$,
  '23514', 'R39_ACCOUNTS_PROGRESS_DIMENSION_MISMATCH',
  'Progress rows cannot combine dimensions from another project'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

insert into v1_r39_t02_results (result_key, payload)
select 'revise', public.v1_revise_project_commercial_baseline(
  '39210000-0000-4000-8000-000000000001', 1,
  '1200000.00', 'AED', '5.0000', null, null,
  jsonb_build_array(
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000002',
      'allocation_percent', '50.0000'
    ),
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000003',
      'allocation_percent', '50.0000'
    )
  ), null, '{}'::jsonb,
  'Approved baseline revision after scope review',
  '39290000-0000-4000-8000-000000000013'
);

select ok(
  payload ->> 'status' = 'current'
  and (payload ->> 'baseline_revision_number')::integer = 2
  and (payload ->> 'record_version')::integer = 2,
  'Admin revises the baseline through a new immutable current revision'
)
from v1_r39_t02_results where result_key = 'revise';

select ok(
  (public.v1_revise_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001', 1,
    '1200000.00', 'AED', '5.0000', null, null,
    jsonb_build_array(
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000002',
        'allocation_percent', '50.0000'
      ),
      jsonb_build_object(
        'building_scope_id', '39220000-0000-4000-8000-000000000003',
        'allocation_percent', '50.0000'
      )
    ), null, '{}'::jsonb,
    'Approved baseline revision after scope review',
    '39290000-0000-4000-8000-000000000013'
  ) ->> 'replayed')::boolean,
  'A baseline revision retry reconciles to the committed revision'
);

insert into v1_r39_t02_results (result_key, payload)
select 'baseline_history_admin',
       public.v1_list_project_commercial_baseline_revisions(
         '39210000-0000-4000-8000-000000000001', 50
       );

select ok(
  (payload #>> '{revisions,0,record_version}')::integer = 2
  and payload #>> '{revisions,0,approved_by_role}' = 'admin'
  and payload #>> '{revisions,0,approved_by_exact_role}' = 'admin'
  and jsonb_array_length(
    payload #> '{revisions,0,before,building_allocations}'
  ) = 2
  and jsonb_array_length(
    payload #> '{revisions,0,after,stage_allocations}'
  ) = 5
  and payload #>> '{revisions,0,before,contract_value}' = '1000000.00'
  and payload #>> '{revisions,0,after,contract_value}' = '1200000.00',
  'Baseline history preserves complete before/after allocations, version and approving authority'
)
from v1_r39_t02_results where result_key = 'baseline_history_admin';

with first_page as (
  select public.v1_list_project_commercial_baseline_revisions(
    '39210000-0000-4000-8000-000000000001', null::integer, 1
  ) as payload
), second_page as (
  select public.v1_list_project_commercial_baseline_revisions(
    '39210000-0000-4000-8000-000000000001',
    (first_page.payload ->> 'next_cursor')::integer,
    1
  ) as payload
  from first_page
)
select ok(
  (select payload ->> 'next_cursor' = '2' from first_page)
  and (select payload #>> '{revisions,0,revision_number}' = '2'
       from first_page)
  and (select payload #>> '{revisions,0,revision_number}' = '1'
       from second_page)
  and (select payload -> 'next_cursor' = 'null'::jsonb from second_page),
  'Baseline history is bounded and cursor-paginated beyond the first page'
);

reset role;

select ok(
  (select count(*) from public.v1_accounts_baseline_revisions
   where project_id = '39210000-0000-4000-8000-000000000001') = 2
  and (select count(*) from public.v1_accounts_baseline_revisions
   where project_id = '39210000-0000-4000-8000-000000000001'
     and status = 'current') = 1
  and exists (
    select 1 from public.v1_accounts_baseline_revisions old_revision
    join public.v1_accounts_baseline_revisions new_revision
      on new_revision.id = old_revision.superseded_by_revision_id
    where old_revision.project_id = '39210000-0000-4000-8000-000000000001'
      and old_revision.revision_number = 1
      and old_revision.status = 'superseded'
      and new_revision.revision_number = 2
      and new_revision.status = 'current'
  )
  and (select count(*) from public.v1_accounts_billing_progress
   where project_id = '39210000-0000-4000-8000-000000000001') = 20
  and (select count(*) from public.v1_accounts_billing_progress revision_two
    join public.v1_accounts_baseline_revisions baseline
      on baseline.id = revision_two.baseline_revision_id
    where revision_two.project_id = '39210000-0000-4000-8000-000000000001'
      and baseline.revision_number = 2
      and revision_two.suggested_percent = 0
      and revision_two.confirmed_percent = 0) = 10,
  'Revision two preserves immutable history and starts a clean progress matrix'
);

select ok(
  (select audit.before_data ? 'building_allocations'
       and audit.before_data ? 'stage_allocations'
       and audit.after_data ? 'building_allocations'
       and audit.after_data ? 'stage_allocations'
   from public.v1_audit_events audit
   where audit.project_id = '39210000-0000-4000-8000-000000000001'
     and audit.event_type = 'accounts_baseline_revised'
   order by audit.occurred_at desc
   limit 1),
  'Baseline revision audit retains complete old and new allocation snapshots'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  not ((public.v1_list_project_commercial_baseline_revisions(
    '39210000-0000-4000-8000-000000000001', 50
  ) #> '{revisions,0}') ? 'contract_value')
  and not ((public.v1_list_project_commercial_baseline_revisions(
    '39210000-0000-4000-8000-000000000001', 50
  ) #> '{revisions,0,before}') ? 'contract_value')
  and not ((public.v1_list_project_commercial_baseline_revisions(
    '39210000-0000-4000-8000-000000000001', 50
  ) #> '{revisions,0,after}') ? 'contract_value')
  and not exists (
    select 1 from jsonb_array_elements(
      public.v1_list_project_commercial_baseline_revisions(
        '39210000-0000-4000-8000-000000000001', 50
      ) #> '{revisions,0,after,building_allocations}'
    ) allocation
    where allocation ? 'allocated_value'
  ),
  'Site baseline history keeps non-money authority facts but omits all commercial values'
);

reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

select ok(
  (public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) -> 'baseline') ? 'contract_value'
  and (public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) #>> '{commands,revise_baseline}')::boolean = false
  and (public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) #>> '{commands,confirm_progress}')::boolean = false,
  'Accountant can read protected Accounts values but receives no T02 mutation command'
);

select throws_ok(
  $$select public.v1_suggest_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    1, '1.0000', 'Accountant cannot suggest', '{}'::uuid[],
    'Deny Accountant technical mutation',
    '39290000-0000-4000-8000-000000000014'
  )$$,
  '42501', 'R39_ACCOUNTS_ACCESS_DENIED',
  'Accountant remains hard-separated from technical progress mutation'
);

reset role;
insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, reason,
  changed_by_auth_user_id
) values (
  '39280000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000013',
  'view_project_accounts', 'deny', 'project',
  'T02 proves a live person-specific deny overrides role defaults',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_permission_assignment_projects (
  assignment_id, project_id
) values (
  '39280000-0000-4000-8000-000000000001',
  '39210000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

select throws_ok(
  $$select public.v1_get_accounts_foundation(
    '39210000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'R39_ACCOUNTS_FOUNDATION_ACCESS_DENIED',
  'Foundation admission respects a live person-specific deny instead of role defaults'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select throws_ok(
  $$select public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'R39_ACCOUNTS_ACCESS_DENIED',
  'Procurement does not inherit project-commercial baseline visibility'
);

reset role;
update public.v1_permission_role_defaults
set is_granted = false, updated_at = clock_timestamp()
where role_name = 'project_engineer'
  and capability_key = 'view_project_commercial_values';

create temporary table v1_r39_t02_value_hidden_target as
select progress.id as progress_entry_id
from public.v1_accounts_billing_progress progress
join public.v1_accounts_baseline_revisions baseline
  on baseline.id = progress.baseline_revision_id
where progress.project_id = '39210000-0000-4000-8000-000000000001'
  and baseline.status = 'current'
  and progress.project_scope_id = '39220000-0000-4000-8000-000000000002'
  and progress.stage_key = 'design';
grant select on table v1_r39_t02_value_hidden_target to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select ok(
  not ((public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) -> 'baseline') ? 'contract_value')
  and (public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) #>> '{capabilities,can_confirm}')::boolean
  and not (public.v1_get_project_commercial_baseline(
    '39210000-0000-4000-8000-000000000001'
  ) #>> '{capabilities,can_view_values}')::boolean,
  'FR-059: confirmation authority remains independent from commercial-value visibility'
);

select lives_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_value_hidden_target),
    1, '5.0000', 'Current operational evidence',
    array['39240000-0000-4000-8000-000000000001'::uuid],
    'Confirm without reading the monetary value',
    '39290000-0000-4000-8000-000000000015'
  )$$,
  'A Project Engineer can confirm progress without receiving money in the response shape'
);

reset role;

update public.v1_document_links
set removed_at = clock_timestamp(),
    removed_by_auth_user_id = '10000000-0000-4000-8000-000000000004',
    removed_by_role = 'admin',
    removal_reason = 'T02 idempotent replay evidence-unlink fixture'
where id = '39242000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select ok(
  (public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '60.0000', 'Confirmed against operational report',
    array['39240000-0000-4000-8000-000000000001'::uuid],
    'Project Engineer confirms inspected progress',
    '39290000-0000-4000-8000-000000000009'
  ) ->> 'replayed')::boolean,
  'A committed command replay survives later evidence unlinking'
);

select throws_ok(
  $$select public.v1_confirm_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    (select progress_entry_id from v1_r39_t02_target),
    2, '59.0000', 'Confirmed against operational report',
    array['39240000-0000-4000-8000-000000000001'::uuid],
    'Project Engineer confirms inspected progress',
    '39290000-0000-4000-8000-000000000009'
  )$$,
  '22023', 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'Evidence lifecycle changes never weaken changed-payload idempotency conflicts'
);

reset role;

-- Projection-only fixture: a later confirmation summary with no document must
-- not inherit an older suggestion's document IDs.
update public.v1_accounts_billing_progress progress
set suggested_percent = 10,
    suggested_evidence_summary = 'Earlier suggestion evidence',
    suggested_evidence_document_ids =
      array['39240000-0000-4000-8000-000000000001'::uuid],
    suggested_by_auth_user_id =
      '10000000-0000-4000-8000-000000000002',
    suggested_by_exact_role = 'site_engineer',
    suggested_at = clock_timestamp(),
    confirmed_percent = 0,
    confirmed_evidence_summary = 'Confirmation summary only',
    confirmed_evidence_document_ids = '{}'::uuid[],
    confirmed_by_auth_user_id =
      '10000000-0000-4000-8000-000000000001',
    confirmed_by_exact_role = 'project_engineer',
    confirmed_at = clock_timestamp(),
    record_version = 2,
    updated_at = clock_timestamp()
from public.v1_accounts_baseline_revisions baseline
where baseline.id = progress.baseline_revision_id
  and baseline.status = 'current'
  and progress.project_id = '39210000-0000-4000-8000-000000000001'
  and progress.project_scope_id = '39220000-0000-4000-8000-000000000003'
  and progress.stage_key = 'design';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select ok(
  public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000003', 'design', null, null
  ) #>> '{progress,0,evidence_summary}' = 'Confirmation summary only'
  and jsonb_array_length(public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000001',
    '39220000-0000-4000-8000-000000000003', 'design', null, null
  ) #> '{progress,0,evidence_document_ids}') = 0,
  'Current evidence context comes atomically from confirmation, never mixed with suggestion IDs'
);

insert into v1_r39_t02_results (result_key, payload)
select 'rounding_baseline', public.v1_initialize_project_commercial_baseline(
  '39210000-0000-4000-8000-000000000002',
  '1.00', 'AED', '0.0000', null, null,
  jsonb_build_array(
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000004',
      'allocation_percent', '33.3333'
    ),
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000005',
      'allocation_percent', '33.3333'
    ),
    jsonb_build_object(
      'building_scope_id', '39220000-0000-4000-8000-000000000006',
      'allocation_percent', '33.3334'
    )
  ), null, '{}'::jsonb,
  'Approve one-dirham residual reconciliation fixture',
  '39290000-0000-4000-8000-000000000017'
);

reset role;

select is(
  (select sum(public.v1_accounts_stage_value(progress.id))::numeric(20,2)
   from public.v1_accounts_billing_progress progress
   where progress.project_id = '39210000-0000-4000-8000-000000000002'),
  1.00::numeric,
  'Largest-remainder Building x Stage values reconcile exactly to the contract baseline'
);

update public.v1_accounts_billing_progress
set confirmed_percent = 100,
    confirmed_by_auth_user_id =
      '10000000-0000-4000-8000-000000000004',
    confirmed_by_exact_role = 'admin',
    confirmed_at = clock_timestamp(),
    review_status = 'not_required',
    record_version = record_version + 1,
    updated_at = clock_timestamp()
where project_id = '39210000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select ok(
  public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000002', null, null, null, null
  ) #>> '{totals,contract_value}' = '1.00'
  and public.v1_list_billing_progress(
    '39210000-0000-4000-8000-000000000002', null, null, null, null
  ) #>> '{totals,confirmed_eligible}' = '1.00',
  'One-hundred-percent confirmed progress reconciles exactly with the fixed-precision baseline'
);

reset role;

select ok(
  (select count(*) from public.v1_accounts_client_claims) = 0
  and (select count(*) from public.v1_accounts_client_invoices) = 0
  and (select count(*) from public.v1_accounts_supplier_bills) = 0,
  'T02 commands do not create T03 or T04 workflow records'
);

select ok(
  (select count(*)
   from public.v1_audit_events audit
   where audit.project_id = '39210000-0000-4000-8000-000000000001'
     and audit.event_type = any(array[
       'accounts_baseline_initialized', 'accounts_baseline_revised',
       'accounts_progress_suggested', 'accounts_progress_confirmed',
       'accounts_progress_reviewed'
     ]::text[])) >= 6
  and not has_table_privilege(
    'authenticated', 'public.v1_audit_events', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_audit_events', 'update'
  ),
  'Every committed T02 command writes server-owned append-only audit evidence'
);

select * from finish();
rollback;

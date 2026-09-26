begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(41);

select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.v1_material_request_private_drafts'::regclass)
  and (select relrowsecurity from pg_class
    where oid = 'public.v1_material_request_work_assignments'::regclass)
  and not has_table_privilege(
    'authenticated', 'public.v1_material_request_private_drafts', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_material_request_work_assignments', 'select'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_raise_version_conflict(text)', 'execute'
  ),
  'Phase 2 working data is RLS protected and command-only'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_create_project(
    '{
      "project_ref":"MR-PH2-001",
      "name":"Phase 2 collaboration proof",
      "parties":{},
      "initial_members":[{
        "auth_user_id":"10000000-0000-4000-8000-000000000002",
        "project_role":"site_engineer",
        "reason":"Request creator"
      }],
      "buildings":[{"code":"ph2","name":"Phase 2 Building"}],
      "attachments":[]
    }'::jsonb,
    'b2000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'Project Engineer creates the Phase 2 fixture project'
);

select lives_ok(
  $$select public.v1_set_project_state(
    jsonb_build_object(
      'project_id', (select id from public.v1_projects
        where project_ref = 'MR-PH2-001'),
      'state', 'active', 'expected_version', 1,
      'reason', 'Ready for Phase 2 proof'
    ),
    'b2000000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Phase 2 fixture project is activated'
);

set local role postgres;
create temporary table v1_ph2_targets as
select project.id as project_id,
  (select scope.id from public.v1_project_scopes scope
    where scope.project_id = project.id and scope.scope_kind = 'building'
    limit 1) as scope_id
from public.v1_projects project where project.project_ref = 'MR-PH2-001';
grant select on table v1_ph2_targets to authenticated;

insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, delivery_note,
  state, record_version, created_by_auth_user_id, requester_display_name,
  requester_project_role, requester_exact_role, current_action_owner_role,
  current_action_code, submitted_at, created_at, updated_at
) values (
  'b2100000-0000-4000-8000-000000000001',
  (select project_id from v1_ph2_targets),
  (select scope_id from v1_ph2_targets),
  'MR-PH2-001-MR001', 'Returned damper request', 'normal', 'Store A',
  'changes_requested', 3,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer',
  'site_engineer', 'site_engineer', 'site_engineer',
  'request_changes_required', clock_timestamp(),
  clock_timestamp() - interval '2 days', clock_timestamp()
);

insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state,
  record_version, created_by_auth_user_id, requester_display_name,
  requester_project_role, requester_exact_role, current_action_owner_role,
  current_action_code, submitted_at, created_at, updated_at
)
select gen_random_uuid(), (select project_id from v1_ph2_targets),
  (select scope_id from v1_ph2_targets),
  'MR-PH2-001-MR' || lpad((series + 1)::text, 3, '0'),
  'Phase 2 paged request ' || series, 'normal', 'submitted', 1,
  '10000000-0000-4000-8000-000000000002', 'Local Site Engineer',
  'site_engineer', 'site_engineer', 'project_engineer',
  'request_approval_required', clock_timestamp(),
  clock_timestamp() - make_interval(hours => series),
  clock_timestamp() - make_interval(hours => series)
from generate_series(1, 15) series;

insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description,
  requested_qty, unit
) values (
  'b2110000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000001', 1, 'custom',
  'Phase 2 smoke damper', 2, 'Nos'
);

insert into public.v1_material_request_revision_snapshots (
  id, request_id, request_record_version, snapshot_reason, title, timing,
  delivery_note, lines, captured_at
) values
(
  'b2120000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000001', 1, 'legacy_baseline',
  'Returned damper request', 'normal', 'Store A',
  '[{"id":"b2110000-0000-4000-8000-000000000001","item_description":"Phase 2 smoke damper","brand_origin":null,"technical_attributes":{},"requested_qty":1,"unit":"Nos"}]'::jsonb,
  clock_timestamp() - interval '2 days'
),
(
  'b2120000-0000-4000-8000-000000000002',
  'b2100000-0000-4000-8000-000000000001', 3,
  'submitted_for_approval', 'Returned damper request', 'normal', 'Store B',
  '[{"id":"b2110000-0000-4000-8000-000000000001","item_description":"Phase 2 smoke damper","brand_origin":null,"technical_attributes":{},"requested_qty":2,"unit":"Nos"},{"id":"b2110000-0000-4000-8000-000000000002","item_description":"Added access door","brand_origin":null,"technical_attributes":{},"requested_qty":1,"unit":"Nos"}]'::jsonb,
  clock_timestamp()
);

insert into public.v1_material_request_decisions (
  id, request_id, request_record_version, decision, reason,
  decided_by_auth_user_id, decided_by_role, decided_by_exact_role,
  decided_by_display_name_snapshot, created_at
) values (
  'b2130000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000001', 2, 'returned',
  'Increase quantity and confirm the store.',
  '10000000-0000-4000-8000-000000000001', 'project_engineer',
  'project_engineer', 'Local Project Engineer',
  clock_timestamp() - interval '1 day'
);

insert into public.v1_material_request_comments (
  id, request_id, body, author_auth_user_id, author_role,
  author_exact_role, author_display_name_snapshot, created_at
)
select gen_random_uuid(), 'b2100000-0000-4000-8000-000000000001',
  'Phase 2 comment ' || series,
  '10000000-0000-4000-8000-000000000002', 'site_engineer',
  'site_engineer', 'Local Site Engineer',
  clock_timestamp() - make_interval(mins => 22 - series)
from generate_series(1, 21) series;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

create temporary table v1_ph2_private_payload as
select jsonb_build_object(
  'draft_id', 'b2200000-0000-4000-8000-000000000001',
  'expected_sync_version', 0,
  'client_updated_at', clock_timestamp(),
  'draft_data', jsonb_build_object(
    'project_id', (select project_id from v1_ph2_targets),
    'scope_id', (select scope_id from v1_ph2_targets),
    'title', 'Private cross-device draft', 'timing', 'normal',
    'scheduled_date', null, 'delivery_note', null, 'lines', '[]'::jsonb
  )
) as payload;
grant select on table v1_ph2_private_payload to authenticated;

select is(
  (public.v1_sync_material_request_private_draft(
    (select payload from v1_ph2_private_payload),
    'b2200000-0000-4000-8000-000000000002'
  ) ->> 'sync_version')::integer,
  1,
  'Owner creates a versioned private recovery draft'
);

select is(
  (public.v1_sync_material_request_private_draft(
    (select payload from v1_ph2_private_payload),
    'b2200000-0000-4000-8000-000000000002'
  ) ->> 'sync_version')::integer,
  1,
  'Private draft retry is idempotent before version validation'
);

set local role postgres;
select is(
  (select count(*) from public.v1_material_request_private_drafts
    where draft_id = 'b2200000-0000-4000-8000-000000000001'),
  1::bigint,
  'Private draft retry leaves one owner row'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_sync_material_request_private_draft(
    jsonb_set((select payload from v1_ph2_private_payload),
      '{client_updated_at}', to_jsonb(clock_timestamp())),
    'b2200000-0000-4000-8000-000000000003'
  )$$,
  '40001', 'V1_PRIVATE_DRAFT_VERSION_CONFLICT',
  'A stale device cannot overwrite the account draft'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select is(
  public.v1_get_my_material_request_private_draft(
    'b2200000-0000-4000-8000-000000000001'
  ),
  null::jsonb,
  'Even Admin cannot read another user private draft'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select is(
  jsonb_array_length(public.v1_list_my_material_request_private_drafts()),
  1,
  'Owner sees the recovery draft on another device'
);

select is(
  jsonb_array_length(public.v1_list_material_request_summaries() -> 'items'),
  15,
  'The lightweight register defaults to fifteen recent requests'
);
select is(
  (public.v1_list_material_request_summaries() ->> 'total_count')::integer,
  16,
  'The register reports an authoritative total beyond the current page'
);
select is(
  (public.v1_list_material_request_summaries(
    p_register_view => 'mine'
  ) ->> 'total_count')::integer,
  16,
  'My Material Requests contains only the current creator owned register'
);
select is(
  (public.v1_list_material_request_summaries(
    p_register_view => 'assigned'
  ) ->> 'total_count')::integer,
  0,
  'Assigned Material Requests starts empty before a responsibility claim'
);
select ok(
  (public.v1_list_material_request_summaries() ->> 'has_more')::boolean,
  'The first summary page declares the next page'
);
select ok(
  not ((public.v1_list_material_request_summaries() -> 'items' -> 0)
    ?| array['lines', 'comments']),
  'Summary rows do not expose heavy line or comment collections'
);
select is(
  (public.v1_list_material_request_summaries(
    p_search => 'smoke damper'
  ) ->> 'total_count')::integer,
  1,
  'Server search includes controlled request item descriptions'
);
select is(
  (public.v1_list_material_request_summaries(
    p_metric => 'open'
  ) -> 'metrics' ->> 'open')::integer,
  16,
  'Server metrics remain authoritative across pagination'
);

create temporary table v1_ph2_comment_page as
select public.v1_list_material_request_comments(
  'b2100000-0000-4000-8000-000000000001', null, null, 20
) as page;
grant select on table v1_ph2_comment_page to authenticated;
select is(
  jsonb_array_length((select page from v1_ph2_comment_page) -> 'items'),
  20,
  'Comment history returns a bounded latest page'
);
select ok(
  ((select page from v1_ph2_comment_page) ->> 'has_more')::boolean,
  'Comment history exposes an older page cursor'
);
select is(
  jsonb_array_length(public.v1_list_material_request_comments(
    'b2100000-0000-4000-8000-000000000001',
    ((select page from v1_ph2_comment_page) ->> 'next_before_created_at')::timestamptz,
    ((select page from v1_ph2_comment_page) ->> 'next_before_id')::uuid,
    20
  ) -> 'items'),
  1,
  'The keyset cursor retrieves the remaining older comment once'
);
select is(
  jsonb_array_length((public.v1_material_request_projection(
    'b2100000-0000-4000-8000-000000000001'
  ) -> 'comments')),
  20,
  'Full detail embeds only the latest twenty comments'
);

select is(
  (public.v1_get_material_request_work_assignment(
    'b2100000-0000-4000-8000-000000000001'
  ) ->> 'assignment_version')::integer,
  0,
  'Responsibility starts visibly unassigned'
);
select is(
  (public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":3,"expected_assignment_version":0,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000002","reason":null}'::jsonb,
    'b2300000-0000-4000-8000-000000000001'
  ) ->> 'assignment_version')::integer,
  1,
  'Eligible current owner can claim responsibility without changing state'
);
select is(
  (public.v1_list_material_request_summaries(
    p_register_view => 'assigned'
  ) ->> 'total_count')::integer,
  1,
  'Assigned Material Requests reflects the server confirmed responsibility'
);
select is(
  (public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":3,"expected_assignment_version":0,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000002","reason":null}'::jsonb,
    'b2300000-0000-4000-8000-000000000001'
  ) ->> 'assignment_version')::integer,
  1,
  'Claim retry returns the first committed response'
);

set local role postgres;
select is(
  (select count(*) from public.v1_audit_events
    where event_type = 'material_request_work_claimed'
      and entity_id = 'b2100000-0000-4000-8000-000000000001'),
  1::bigint,
  'Claim retry produces one immutable audit event'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":3,"expected_assignment_version":1,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000001","reason":null}'::jsonb,
    'b2300000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'V1_MATERIAL_REQUEST_REASSIGN_REASON_REQUIRED',
  'Changing an existing assignee requires an auditable reason'
);
select is(
  (public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":3,"expected_assignment_version":1,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000001","reason":"Project Engineer will coordinate the revision."}'::jsonb,
    'b2300000-0000-4000-8000-000000000003'
  ) ->> 'assignment_version')::integer,
  2,
  'Responsibility can be reassigned to an eligible project stakeholder'
);

set local role postgres;
select is(
  (select count(*) from public.v1_notifications
    where event_code = 'material_request_work_assigned'
      and recipient_auth_user_id =
        '10000000-0000-4000-8000-000000000001'),
  1::bigint,
  'Reassignment notifies exactly the new responsible stakeholder'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":3,"expected_assignment_version":1,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000002","reason":"Stale tab"}'::jsonb,
    'b2300000-0000-4000-8000-000000000004'
  )$$,
  '40001', 'V1_MATERIAL_REQUEST_ASSIGNMENT_VERSION_CONFLICT',
  'A stale responsibility update cannot overwrite a newer assignment'
);

select is(
  (public.v1_material_request_change_summary(
    'b2100000-0000-4000-8000-000000000001'
  ) ->> 'items_added')::integer,
  1,
  'Returned-request summary identifies newly added items'
);
select is(
  (public.v1_material_request_change_summary(
    'b2100000-0000-4000-8000-000000000001'
  ) ->> 'quantity_or_unit_changed')::integer,
  1,
  'Returned-request summary identifies quantity changes'
);
select ok(
  (public.v1_material_request_change_summary(
    'b2100000-0000-4000-8000-000000000001'
  ) ->> 'delivery_note_changed')::boolean,
  'Returned-request summary identifies delivery-note changes'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select is(
  (public.v1_list_material_request_summaries() ->> 'total_count')::integer,
  16,
  'Admin receives the complete authorized company register'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select is(
  (public.v1_list_material_request_summaries() ->> 'total_count')::integer,
  15,
  'Procurement sees submitted requests but not a returned Engineering draft'
);

set local role postgres;
update public.v1_material_requests set state = 'cancelled',
  current_action_owner_role = 'none', current_action_code = 'none',
  cancelled_at = clock_timestamp(),
  cancelled_by_auth_user_id = '10000000-0000-4000-8000-000000000001',
  cancellation_reason = 'Terminal assignment proof',
  record_version = record_version + 1
where id = 'b2100000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_assign_material_request_work(
    '{"request_id":"b2100000-0000-4000-8000-000000000001","expected_request_version":4,"expected_assignment_version":2,"assignee_auth_user_id":"10000000-0000-4000-8000-000000000002","reason":"Must stay terminal"}'::jsonb,
    'b2300000-0000-4000-8000-000000000005'
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_ASSIGNMENT_DENIED',
  'Cancelled requests cannot be claimed or reassigned'
);

select throws_ok(
  $$select public.v1_delete_my_material_request_private_draft(
    '{"draft_id":"b2200000-0000-4000-8000-000000000001","expected_sync_version":2}'::jsonb,
    'b2400000-0000-4000-8000-000000000003'
  )$$,
  '40001',
  'V1_PRIVATE_DRAFT_VERSION_CONFLICT',
  'A direct stale delete retains the established 40001 conflict contract'
);
select set_config('request.method', 'POST', true);
select throws_ok(
  $$select public.v1_delete_my_material_request_private_draft(
    '{"draft_id":"b2200000-0000-4000-8000-000000000001","expected_sync_version":2}'::jsonb,
    'b2400000-0000-4000-8000-000000000002'
  )$$,
  'PGRST',
  jsonb_build_object(
    'code', '40001',
    'message', 'V1_PRIVATE_DRAFT_VERSION_CONFLICT',
    'details', null,
    'hint', null
  )::text,
  'A stale REST delete returns one non-retryable 409 conflict envelope'
);
select lives_ok(
  $$select public.v1_delete_my_material_request_private_draft(
    '{"draft_id":"b2200000-0000-4000-8000-000000000001","expected_sync_version":1}'::jsonb,
    'b2400000-0000-4000-8000-000000000001'
  )$$,
  'Owner can remove the cross-device recovery copy after submission or discard'
);
select set_config('request.method', '', true);
select throws_ok(
  $$select public.v1_get_my_material_request_private_draft('b2200000-0000-4000-8000-000000000001')$$,
  '55000', 'V1_PRIVATE_DRAFT_DELETED',
  'Owner receives confirmed retirement on another device'
);

set local role anon;
select throws_ok(
  $$select public.v1_list_material_request_summaries()$$,
  '42501', 'permission denied for function v1_list_material_request_summaries',
  'Anonymous callers cannot execute the summary register RPC'
);

select * from finish();
rollback;
